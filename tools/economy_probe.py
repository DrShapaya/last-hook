"""Deterministic sensitivity probe, NOT a prediction of player retention.

Run: python tools/economy_probe.py
Uses balance.json and explicit assumed skill/pace/loot behaviour; real sessions
are recorded by the game in profile.json/run_history for later calibration.
"""
import json
import math
import random
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BALANCE = json.loads((ROOT / "game/data/balance.json").read_text(encoding="utf-8"))
CAPS = [6, 6, 3, 6, 6, 6, 6]


def upgrade_cost(kind, level):
    if kind == 2:
        return BALANCE["tip_prices"][level - 1]
    return round(BALANCE["upgrade_prices"][level - 1] * BALANCE["upgrade_weights"][kind])


def height_gold(height):
    return sum(2 + min((band - 1) // 20, 7) for band in range(1, int(height) + 1))


def simulate(seed, base_skill, learned_skill, seconds_per_grip, replace_chance, policy):
    rng = random.Random(seed)
    levels = [1] * 7
    gold, zone, seconds, runs = 0, 1, 0.0, 0
    first_buy = first_summit = None
    while levels != CAPS and seconds < 24 * 3600:
        bag = []
        movement = sum(levels[i] - 1 for i in (0, 1, 2, 6))
        skill = min(.997, base_skill + (learned_skill - base_skill) *
                    (1 - math.exp(-seconds / 2400)) + movement * .0015)
        height = 0.0
        transfers = 0
        while transfers < 40:
            if rng.random() > skill:
                break
            transfers += 1
            height = transfers * 3.0
            current_zone = min(6, 1 + int(height // 20))
            while zone < current_zone:
                zone += 1
                gold += BALANCE["new_zone_gold_per_index"] * zone
            if transfers % 2 == 0 and rng.random() < .72:
                tier = min(5, int(height // 20))
                if tier >= levels[3]:
                    continue
                value = BALANCE["loot_values"][tier]
                if len(bag) < levels[3]:
                    bag.append(value)
                elif min(bag) < value and rng.random() < replace_chance:
                    bag.remove(min(bag))
                    bag.append(value)
        success = transfers == 40
        seconds += 18 + max(1, transfers) * seconds_per_grip / (1 + movement * .017)
        payout = height_gold(height)
        payout += sum(bag) if success else math.floor(sum(bag) * BALANCE["recovery_percents"][levels[5]-1] / 100)
        if success:
            payout += BALANCE["summit_repeat_bonus"]
            if first_summit is None:
                first_summit = seconds / 60
                payout += BALANCE["first_summit_gold"]
        gold += payout
        runs += 1
        for _ in range(35):
            affordable = [i for i in range(7) if levels[i] < (CAPS[i] if i == 2 else min(6, max(2, zone))) and
                          gold >= upgrade_cost(i, levels[i])]
            if not affordable:
                break
            priority = (3, 5, 0, 6, 1, 2, 4) if policy == "loot" else (0, 6, 1, 3, 2, 5, 4)
            # Keep early upgrades broad, then follow a player's preference.
            kind = min(affordable, key=lambda i: (levels[i], priority.index(i)))
            gold -= upgrade_cost(kind, levels[kind])
            levels[kind] += 1
            if first_buy is None:
                first_buy = seconds / 60
    return {"first_buy_minutes": first_buy, "first_summit_minutes": first_summit,
            "full_kit_minutes": seconds / 60, "runs": runs, "completed": levels == CAPS}


def main():
    scenarios = {"beginner": (.88, .975, 6.2, .25), "regular": (.94, .988, 5.0, .65),
                 "experienced": (.975, .995, 4.2, .90)}
    report = {"status": "assumption_based_sensitivity_probe_not_playtest",
              "target_minutes": [210, 420], "trials_per_policy": 30,
              "assumptions": {name: dict(zip(("initial_transfer_success", "learned_transfer_success",
                    "seconds_per_transfer", "replacement_probability"), values)) for name, values in scenarios.items()},
              "results": {}}
    for name, values in scenarios.items():
        for policy in ("movement", "loot"):
            trials = [simulate(7319 + trial, *values, policy) for trial in range(30)]
            report["results"][name + "_" + policy] = {
                key: round(statistics.median(t[key] for t in trials if t[key] is not None), 1)
                for key in ("first_buy_minutes", "first_summit_minutes", "full_kit_minutes", "runs")}
            report["results"][name + "_" + policy]["all_completed"] = all(t["completed"] for t in trials)
    report["repeat_height_gold"] = {"200m": height_gold(20), "1200m": height_gold(120)}
    output = ROOT / "artifacts/economy-probe-v9.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report["results"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
