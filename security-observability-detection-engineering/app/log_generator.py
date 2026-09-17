import argparse
import json
import random
import socket
import time
from datetime import datetime, timezone
from pathlib import Path


def build_log_entry(event_type: str, **kwargs) -> dict:
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "hostname": socket.gethostname(),
        "event_type": event_type,
    }

    entry.update(kwargs)
    return entry


def emit_normal_event():
    event_type = random.choice(
        [
            "login_attempt",
            "api_access",
            "security_alert",
        ]
    )

    if event_type == "login_attempt":
        success = random.random() > 0.15

        return build_log_entry(
            "login_attempt",
            username=random.choice(
                ["alice", "bob", "carol", "service-api"]
            ),
            ip_address=f"10.0.0.{random.randint(10, 200)}",
            success=success,
            status="success" if success else "failed",
        )

    if event_type == "api_access":
        return build_log_entry(
            "api_access",
            method=random.choice(["GET", "POST", "PUT"]),
            path=random.choice(
                ["/login", "/api/profile", "/api/orders", "/health"]
            ),
            status_code=random.choice(
                [200, 200, 200, 201, 400, 401, 403, 404]
            ),
            ip_address=f"10.0.0.{random.randint(10, 200)}",
            response_ms=random.randint(30, 900),
        )

    severity = random.choice(
        ["info", "warning", "critical"]
    )

    return build_log_entry(
        "security_alert",
        severity=severity,
        rule=random.choice(
            [
                "unexpected-login-pattern",
                "request-anomaly",
                "suspicious-api-access",
            ]
        ),
        source_ip=f"10.0.0.{random.randint(10, 200)}",
    )


def emit_attack_sequence(output):
    attacker_ip = "10.0.0.66"

    for attempt in range(1, 9):
        entry = build_log_entry(
            "login_attempt",
            username="admin",
            ip_address=attacker_ip,
            success=False,
            status="failed",
            sequence=attempt,
            attack_simulation=True,
        )

        output.write(json.dumps(entry) + "\n")
        output.flush()

        time.sleep(0.15)

    alert = build_log_entry(
        "security_alert",
        severity="critical",
        rule="brute-force-authentication",
        source_ip=attacker_ip,
        description="Repeated failed authentication activity detected",
        attack_simulation=True,
    )

    output.write(json.dumps(alert) + "\n")
    output.flush()


def run(
    log_path: str,
    interval_range: tuple[float, float],
    attack: bool,
    count: int,
) -> None:
    path = Path(log_path)

    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with path.open(
        "a",
        encoding="utf-8",
    ) as output:

        if attack:
            emit_attack_sequence(output)

        for _ in range(count):
            entry = emit_normal_event()

            output.write(
                json.dumps(entry) + "\n"
            )
            output.flush()

            time.sleep(
                random.uniform(*interval_range)
            )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--log-path",
        default="logs/security.log",
    )

    parser.add_argument(
        "--count",
        type=int,
        default=40,
    )

    parser.add_argument(
        "--attack",
        action="store_true",
    )

    parser.add_argument(
        "--min-interval",
        type=float,
        default=0.05,
    )

    parser.add_argument(
        "--max-interval",
        type=float,
        default=0.20,
    )

    args = parser.parse_args()

    run(
        log_path=args.log_path,
        interval_range=(
            args.min_interval,
            args.max_interval,
        ),
        attack=args.attack,
        count=args.count,
    )


if __name__ == "__main__":
    main()
