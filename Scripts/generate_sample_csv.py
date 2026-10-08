#!/usr/bin/env python3
"""Generate a realistic build_times.csv in the xcode-build-time-recorder format.

Usage: generate_sample_csv.py OUTPUT.csv [--days 120] [--seed 7]
"""
import argparse
import csv
import random
from datetime import datetime, timedelta, timezone

HEADER = [
    "started_at", "completed_at", "duration_seconds", "build_kind", "status",
    "artifact_updated", "scheme", "configuration", "sdk", "project", "user",
    "hostname", "hardware_model", "cpu_count", "xcode_version", "git_branch",
    "git_commit",
]

# project, scheme, typical incremental seconds, typical full seconds, builds/workday
PROJECTS = [
    ("Totos", "Totos", 18, 210, 22),
    ("NativeFactory", "NativeFactory-Dev", 42, 520, 14),
    ("LottieMeasure", "LottieMeasure", 9, 95, 8),
]
BRANCHES = ["main", "feature/charts", "feature/onboarding", "fix/crash-on-launch", "release/2.4"]
TZ = timezone(timedelta(hours=1))


def fmt(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S%z")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    parser.add_argument("--days", type=int, default=120)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    rng = random.Random(args.seed)

    now = datetime.now(TZ)
    rows = []
    for day_offset in range(args.days, -1, -1):
        day = (now - timedelta(days=day_offset)).replace(hour=0, minute=0, second=0, microsecond=0)
        weekend = day.weekday() >= 5
        # Slow drift: builds get a bit slower over time, then a fix lands.
        drift = 1 + 0.25 * (1 - day_offset / args.days) - (0.2 if day_offset < 20 else 0)
        for project, scheme, incr, full, per_day in PROJECTS:
            count = rng.randint(0, 3) if weekend else max(0, int(rng.gauss(per_day, per_day / 3)))
            times = sorted(day + timedelta(hours=rng.uniform(8.5, 19), minutes=rng.uniform(0, 59)) for _ in range(count))
            branch = rng.choice(BRANCHES)
            for i, started in enumerate(times):
                if started > now:
                    continue
                kind = "full" if (i == 0 and rng.random() < 0.5) or rng.random() < 0.04 else "incremental"
                if rng.random() < 0.15:
                    branch = rng.choice(BRANCHES)
                commit = "%07x" % rng.getrandbits(28)
                base = (full if kind == "full" else incr) * drift
                common = [kind]
                tail = [scheme, "Debug", "iphonesimulator26.0", project, "dan", "studio",
                        "Mac15,6", "12", "2600", branch, commit]
                if rng.random() < 0.08:
                    rows.append([fmt(started), "", ""] + common + ["failed-or-cancelled", ""] + tail)
                    continue
                no_op = kind == "incremental" and rng.random() < 0.12
                duration = max(1, int(rng.uniform(1, 3) if no_op else rng.lognormvariate(0, 0.35) * base))
                completed = started + timedelta(seconds=duration)
                rows.append([fmt(started), fmt(completed), str(duration)] + common
                            + ["succeeded", "no" if no_op else "yes"] + tail)

    with open(args.output, "w", newline="") as handle:
        handle.write(",".join(HEADER) + "\n")
        writer = csv.writer(handle, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writerows(rows)
    print(f"Wrote {len(rows)} builds to {args.output}")


if __name__ == "__main__":
    main()
