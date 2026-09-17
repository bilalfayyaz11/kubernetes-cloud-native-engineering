from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from datetime import datetime, timezone
import json

LOG_PATH = Path("/data/alertmanager-webhooks.jsonl")


class Handler(BaseHTTPRequestHandler):

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)

        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw.decode("utf-8", errors="replace")}

        record = {
            "received_at": datetime.now(timezone.utc).isoformat(),
            "payload": payload,
        }

        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

        with LOG_PATH.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record) + "\n")

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")

    def log_message(self, fmt, *args):
        return


HTTPServer(("0.0.0.0", 5001), Handler).serve_forever()
