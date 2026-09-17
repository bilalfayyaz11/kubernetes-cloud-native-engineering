import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path


def load_logs(log_path: str) -> list[dict]:
    entries = []

    path = Path(log_path)

    if not path.exists():
        return entries

    with path.open(
        encoding="utf-8",
    ) as handle:

        for line in handle:
            line = line.strip()

            if not line:
                continue

            try:
                entries.append(
                    json.loads(line)
                )
            except json.JSONDecodeError:
                continue

    return entries


def detect_brute_force(
    entries: list[dict],
    threshold: int = 5,
) -> dict[str, int]:

    failures = defaultdict(int)

    for entry in entries:

        if entry.get("event_type") != "login_attempt":
            continue

        success = entry.get("success")

        if success is False or success is None:
            ip = entry.get("ip_address")

            if ip:
                failures[ip] += 1

    return {
        ip: count
        for ip, count in failures.items()
        if count >= threshold
    }


def detect_http_anomalies(entries: list[dict]) -> dict:
    status_counts = Counter()
    suspicious_sources = Counter()

    for entry in entries:

        if entry.get("event_type") != "api_access":
            continue

        status = entry.get("status_code")
        ip = entry.get("ip_address")

        if status is not None:
            status_counts[str(status)] += 1

        if status in {
            400,
            401,
            403,
            404,
            429,
        }:
            if ip:
                suspicious_sources[ip] += 1

    return {
        "status_counts": dict(status_counts),
        "suspicious_sources": dict(suspicious_sources),
    }


def summarize(
    entries: list[dict],
    threshold: int = 5,
) -> dict:

    event_counts = Counter(
        entry.get(
            "event_type",
            "unknown",
        )
        for entry in entries
    )

    brute_force = detect_brute_force(
        entries,
        threshold,
    )

    critical_alerts = [
        entry
        for entry in entries
        if (
            entry.get("event_type") == "security_alert"
            and entry.get("severity") == "critical"
        )
    ]

    http_anomalies = detect_http_anomalies(
        entries
    )

    return {
        "total_entries": len(entries),
        "event_counts": dict(event_counts),
        "brute_force_sources": brute_force,
        "critical_alerts": critical_alerts,
        "http_anomalies": http_anomalies,
    }


def print_human_report(report: dict) -> None:
    print("===== SECURITY LOG ANALYSIS =====")

    print()
    print("=== Event Counts ===")

    for event_type, count in sorted(
        report["event_counts"].items()
    ):
        print(
            f"{event_type}: {count}"
        )

    print()
    print("=== Brute-Force Sources ===")

    if report["brute_force_sources"]:
        for ip, count in sorted(
            report[
                "brute_force_sources"
            ].items()
        ):
            print(
                f"{ip}: {count} failed logins"
            )
    else:
        print("none")

    print()
    print("=== Critical Alerts ===")

    if report["critical_alerts"]:
        for alert in report[
            "critical_alerts"
        ]:
            print(
                json.dumps(
                    alert,
                    sort_keys=True,
                )
            )
    else:
        print("none")

    print()
    print("=== HTTP Status Counts ===")

    for status, count in sorted(
        report[
            "http_anomalies"
        ][
            "status_counts"
        ].items()
    ):
        print(
            f"{status}: {count}"
        )

    print()
    print(
        "=== Suspicious HTTP Sources ==="
    )

    suspicious = report[
        "http_anomalies"
    ][
        "suspicious_sources"
    ]

    if suspicious:
        for ip, count in sorted(
            suspicious.items()
        ):
            print(
                f"{ip}: {count} suspicious responses"
            )
    else:
        print("none")


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--log-path",
        default="logs/security.log",
    )

    parser.add_argument(
        "--threshold",
        type=int,
        default=5,
    )

    parser.add_argument(
        "--json-output",
    )

    args = parser.parse_args()

    entries = load_logs(
        args.log_path
    )

    report = summarize(
        entries,
        args.threshold,
    )

    print_human_report(
        report
    )

    if args.json_output:
        output_path = Path(
            args.json_output
        )

        output_path.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        output_path.write_text(
            json.dumps(
                report,
                indent=2,
                sort_keys=True,
            )
        )


if __name__ == "__main__":
    main()
