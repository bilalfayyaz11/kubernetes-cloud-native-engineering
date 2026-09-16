import json
import os
import ssl
import subprocess
from urllib.parse import urlsplit
from http.server import BaseHTTPRequestHandler, HTTPServer


PUBLIC_KEY = os.getenv(
    "COSIGN_PUBLIC_KEY",
    "/keys/cosign.pub"
)

REGISTRY_ENDPOINT = os.getenv(
    "REGISTRY_ENDPOINT",
    ""
)


class AdmissionHandler:
    def __init__(self, public_key_path: str) -> None:
        self.public_key_path = public_key_path

    def registry_reference(self, image_ref: str) -> str:
        if (
            REGISTRY_ENDPOINT
            and image_ref.startswith("localhost:5000/")
        ):
            return image_ref.replace(
                "localhost:5000",
                REGISTRY_ENDPOINT,
                1,
            )

        return image_ref

    def verify_image(self, image_ref: str) -> tuple[bool, str]:
        verification_ref = self.registry_reference(image_ref)

        command = [
            "cosign",
            "verify",
            "--key",
            self.public_key_path,
            "--insecure-ignore-tlog=true",
            "--allow-http-registry",
            verification_ref,
        ]

        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=8,
                check=False,
            )
        except Exception as exc:
            return False, f"Cosign execution error: {exc}"

        if result.returncode == 0:
            return True, ""

        message = (
            result.stderr.strip()
            or result.stdout.strip()
            or "signature verification failed"
        )

        return False, message

    def handle(self, admission_review: dict) -> dict:
        request = admission_review.get("request", {})
        uid = request.get("uid", "")

        response = {
            "apiVersion": "admission.k8s.io/v1",
            "kind": "AdmissionReview",
            "response": {
                "uid": uid,
                "allowed": False,
            },
        }

        try:
            obj = request.get("object") or {}
            spec = obj.get("spec") or {}

            containers = []

            containers.extend(
                spec.get("initContainers") or []
            )

            containers.extend(
                spec.get("containers") or []
            )

            if not containers:
                response["response"]["status"] = {
                    "message": "No container images found in Pod request."
                }
                return response

            failures = []

            for container in containers:
                image = container.get("image", "")

                if not image:
                    failures.append(
                        f"{container.get('name', '<unnamed>')}: "
                        "image reference missing"
                    )
                    continue

                verified, message = self.verify_image(image)

                if not verified:
                    failures.append(
                        f"{image}: {message}"
                    )

            if failures:
                response["response"]["status"] = {
                    "message": (
                        "Image signature policy denied Pod: "
                        + " | ".join(failures)
                    )
                }
                return response

            response["response"]["allowed"] = True
            response["response"]["status"] = {
                "message": (
                    "All container images have valid "
                    "Cosign signatures."
                )
            }

            return response

        except Exception as exc:
            response["response"]["allowed"] = False
            response["response"]["status"] = {
                "message": (
                    "Admission verification internal error: "
                    f"{exc}"
                )
            }

            return response


POLICY = AdmissionHandler(PUBLIC_KEY)


class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        request_path = urlsplit(self.path).path

        if request_path != "/validate":
            self.send_response(404)
            self.end_headers()
            return

        try:
            length = int(
                self.headers.get("Content-Length", "0")
            )

            payload = self.rfile.read(length)
            review = json.loads(payload)

            response = POLICY.handle(review)

            encoded = json.dumps(response).encode()

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "application/json",
            )
            self.send_header(
                "Content-Length",
                str(len(encoded)),
            )
            self.end_headers()

            self.wfile.write(encoded)

        except Exception as exc:
            body = json.dumps({
                "apiVersion": "admission.k8s.io/v1",
                "kind": "AdmissionReview",
                "response": {
                    "allowed": False,
                    "status": {
                        "message": (
                            "Webhook request processing "
                            f"failed: {exc}"
                        )
                    },
                },
            }).encode()

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "application/json",
            )
            self.send_header(
                "Content-Length",
                str(len(body)),
            )
            self.end_headers()

            self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(
            "%s - %s"
            % (
                self.address_string(),
                fmt % args,
            ),
            flush=True,
        )


def main():
    server = HTTPServer(
        ("0.0.0.0", 8443),
        RequestHandler,
    )

    context = ssl.SSLContext(
        ssl.PROTOCOL_TLS_SERVER
    )

    context.load_cert_chain(
        certfile="/tls/tls.crt",
        keyfile="/tls/tls.key",
    )

    server.socket = context.wrap_socket(
        server.socket,
        server_side=True,
    )

    print(
        "Signature policy webhook listening on :8443",
        flush=True,
    )

    server.serve_forever()


if __name__ == "__main__":
    main()
