"""Summarize actual local attempts; input may also be an automated-test profile.

python tools/analyze_sessions.py path/to/profile.json --output artifacts/sessions.json
Never changes the profile or infers enjoyment/retention from automated runs.
"""
import argparse
import json
import statistics
from collections import Counter
from pathlib import Path


def summarize(profile):
    history = [run for run in profile.get("run_history", []) if run.get("seconds", 0) > 0]
    seconds = sum(run["seconds"] for run in history)
    shots = sum(run.get("shots", 0) for run in history)
    catches = sum(run.get("catches", 0) for run in history)
    recurring = [run for run in history if "finish_gold" in run]
    balance = json.loads((Path(__file__).resolve().parents[1] / "game/data/balance.json").read_text(encoding="utf-8"))
    recurring_gold = sum(run["height_gold"] + run["loot_gold"] + run["finish_gold"] -
                         (balance["first_summit_gold"] if run.get("first_summit") else 0)
                         for run in recurring)
    recurring_seconds = sum(run["seconds"] for run in recurring)
    return {
        "status": "observed_attempts_input_provenance_must_be_checked",
        "note": "Last 30 attempts only. Gameplay time excludes menus and pauses. Automated input is not a human playtest.",
        "attempts": len(history),
        "gameplay_minutes": round(seconds / 60, 2),
        "wins": sum(bool(run.get("success")) for run in history),
        "median_attempt_seconds": round(statistics.median(run["seconds"] for run in history), 1) if history else None,
        "median_height_m": statistics.median(run.get("height", 0) for run in history) if history else None,
        "gold_per_gameplay_minute": round(sum(run.get("gold", 0) for run in history) * 60 / seconds, 1) if seconds else None,
        "recurring_gold_per_gameplay_minute": round(recurring_gold * 60 / recurring_seconds, 1) if recurring_seconds else None,
        "recurring_sample_size": len(recurring),
        "catch_percent": round(catches * 100 / shots, 1) if shots else None,
        "failures": dict(Counter(run.get("reason") or "unspecified" for run in history if not run.get("success"))),
        "kits_observed": [list(kit) for kit in sorted({tuple(run.get("levels", [])) for run in history})],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = summarize(json.loads(args.profile.read_text(encoding="utf-8-sig")))
    output = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output + "\n", encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
