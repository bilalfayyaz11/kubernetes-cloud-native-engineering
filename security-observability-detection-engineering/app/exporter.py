import argparse
import random
import threading
import time
from prometheus_client import (
    Counter,
    Gauge,
    Histogram,
    start_http_server,
)

LOGIN_ATTEMPTS = Counter(
    "security_login_attempts",
    "Authentication attempts",
    ["status"],
)

FAILED_LOGINS = Counter(
    "security_failed_logins_per_ip",
    "Failed authentication attempts by source IP",
    ["ip_address"],
)

API_RESPONSE = Histogram(
    "security_api_response_seconds",
    "Security-relevant API response latency",
)

ACTIVE_SESSIONS = Gauge(
    "security_active_sessions",
    "Current active sessions",
)

HTTP_REQUESTS = Counter(
    "security_http_requests",
    "Observed HTTP requests",
    ["method", "status"],
)

MODE = Gauge(
    "security_exporter_attack_mode",
    "Exporter operating mode where 1 means attack simulation enabled",
)


def emit_normal():
    while True:
        success = random.random() > 0.10

        if success:
            LOGIN_ATTEMPTS.labels(status="success").inc()
            HTTP_REQUESTS.labels(method="POST", status="200").inc()
        else:
            ip = f"10.0.0.{random.randint(10, 200)}"
            LOGIN_ATTEMPTS.labels(status="failed").inc()
            FAILED_LOGINS.labels(ip_address=ip).inc()
            HTTP_REQUESTS.labels(method="POST", status="401").inc()

        API_RESPONSE.observe(random.uniform(0.05, 0.45))
        ACTIVE_SESSIONS.set(random.randint(10, 80))

        time.sleep(random.uniform(0.7, 1.5))


def emit_attack():
    attack_ip = "10.0.0.66"

    while True:
        for _ in range(8):
            LOGIN_ATTEMPTS.labels(status="failed").inc()
            FAILED_LOGINS.labels(ip_address=attack_ip).inc()
            HTTP_REQUESTS.labels(method="POST", status="401").inc()
            API_RESPONSE.observe(random.uniform(1.8, 2.8))

        for _ in range(10):
            HTTP_REQUESTS.labels(method="GET", status="404").inc()

        ACTIVE_SESSIONS.set(random.randint(120, 200))

        time.sleep(1)


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--mode",
        choices=["normal", "attack"],
        default="normal",
    )

    parser.add_argument(
        "--port",
        type=int,
        default=8000,
    )

    args = parser.parse_args()

    start_http_server(args.port)

    if args.mode == "attack":
        MODE.set(1)
        worker = threading.Thread(
            target=emit_attack,
            daemon=True,
        )
    else:
        MODE.set(0)
        worker = threading.Thread(
            target=emit_normal,
            daemon=True,
        )

    worker.start()

    while True:
        time.sleep(30)


if __name__ == "__main__":
    main()
