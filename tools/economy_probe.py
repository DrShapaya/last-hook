"""Deterministic sensitivity probe, NOT a prediction of player retention.

Run: python tools/economy_probe.py
Uses balance.json and explicit assumed skill/pace/loot behaviour; real sessions
are recorded by the game in profile.json/run_history for later calibration.
"""
import argparse
import json
import math
import random
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BALANCE = json.loads((ROOT / "game/data/balance.json").read_text(encoding="utf-8"))
CAPS = [6, 6, 4, 6, 6, 6, 6]


def upgrade_cost(kind, level):
    if kind == 2:
        return BALANCE["tip_prices"][level - 1]
    return math.floor(BALANCE["upgrade_prices"][level - 1] * BALANCE["upgrade_weights"][kind] + .5)


def height_gold(height):
    bands = max(0, math.floor(height * BALANCE["meters_per_unit"] / 10))
    return sum(2 + min((band - 1) // 20, 7) for band in range(1, bands + 1))


def simulate(seed, base_skill, learned_skill, seconds_per_grip, replace_chance, policy):
    rng = random.Random(seed)
    levels = [1] * 7
    gold, zone, seconds, runs = 0, 1, 0.0, 0
    first_buy = first_summit = None
    purchases = 0
    milestones = {}
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
            current_zone = min(6, 1 + int(height // BALANCE["zone_units"]))
            while zone < current_zone:
                zone += 1
                gold += BALANCE["new_zone_gold_per_index"] * zone
            if transfers % 2 == 0 and rng.random() < .72:
                tier = min(5, int(height // BALANCE["zone_units"]))
                value = BALANCE["loot_values"][tier]
                # Optional rare detour; all tiers fit even the starter bag.
                if rng.random() < .2:
                    value = math.floor(value * 1.8 + .5)
                if len(bag) < BALANCE["capacities"][levels[3] - 1]:
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
            purchases += 1
            seconds += 6  # Assumed time in equipment menu per transaction.
            if first_buy is None:
                first_buy = seconds / 60
            for fraction in (.25, .5, .75):
                if purchases >= math.ceil(sum(cap-1 for cap in CAPS) * fraction):
                    milestones.setdefault(f"purchases_{int(fraction*100)}_minutes", seconds / 60)
    return {"first_buy_minutes": first_buy, "first_summit_minutes": first_summit,
            **milestones, "full_kit_minutes": seconds / 60 if levels == CAPS else None,
            "runs": runs, "completed": levels == CAPS}


def evaluate(trial_count):
    scenarios = {"beginner": (.88, .975, 6.2, .25), "regular": (.94, .988, 5.0, .65),
                 "experienced": (.975, .995, 4.2, .90)}
    report = {"status": "assumption_based_sensitivity_probe_not_playtest",
              "target_minutes": [210, 420], "trials_per_policy": trial_count, "seed_start": 7319,
              "shared_assumptions": {"transfer_rise":3,"summit_transfers":40,"menu_seconds_per_run":18,
                  "menu_seconds_per_purchase":6,"loot_chance_per_two_transfers":.72,"rare_find_probability":.2,
                  "movement_skill_per_level":.0015,"movement_pace_per_level":.017,"revives":False,
                  "exclusions":"No geometry/input simulation or location purchases. Real human pace may differ."},
              "assumptions": {name: dict(zip(("initial_transfer_success", "learned_transfer_success",
                    "seconds_per_transfer", "replacement_probability"), values)) for name, values in scenarios.items()},
              "results": {}}
    for name, values in scenarios.items():
        for policy in ("movement", "loot"):
            trials = [simulate(7319 + trial, *values, policy) for trial in range(trial_count)]
            report["results"][name + "_" + policy] = {
                key: round(statistics.median(t[key] for t in trials if t.get(key) is not None), 1)
                     if any(t.get(key) is not None for t in trials) else None
                for key in ("first_buy_minutes", "first_summit_minutes", "purchases_25_minutes",
                            "purchases_50_minutes", "purchases_75_minutes", "full_kit_minutes", "runs")}
            report["results"][name + "_" + policy]["all_completed"] = all(t["completed"] for t in trials)
    report["repeat_height_gold"] = {"200m": height_gold(20), "1200m": height_gold(120)}
    prices = [[upgrade_cost(kind, level) for level in range(1, cap)] for kind, cap in enumerate(CAPS)]
    report["prices_by_track"] = prices
    report["total_upgrade_gold"] = sum(map(sum, prices))
    report["last_level_share"] = round(prices[0][-1] / sum(prices[0]), 3)
    # Same base kit, one ordinary top-tier find, 6.2 s/transfer + 18 s menu.
    # Compare controlled early exits with a repeat summit; exclude first bonuses.
    report["controlled_reset_gold_per_cycle_minute"] = {}
    for height in (20, 40, 80, 120):
        value = BALANCE["loot_values"][min(5, int(height // BALANCE["zone_units"]))]
        success = height == BALANCE["summit_units"]
        payout = height_gold(height) + (value if success else math.floor(value * .3))
        if success: payout += BALANCE["summit_repeat_bonus"]
        report["controlled_reset_gold_per_cycle_minute"][str(height * BALANCE["meters_per_unit"])] = round(payout*60/(18+math.ceil(height/3)*6.2),1)
    return report


def main():
    global BALANCE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compare", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/economy-probe-v12.json")
    parser.add_argument("--trials", type=int, default=100)
    args = parser.parse_args()
    if args.trials < 1: parser.error("--trials must be positive")
    report = {"current": evaluate(args.trials)}
    if args.compare:
        BALANCE = json.loads(args.compare.read_text(encoding="utf-8-sig"))
        report["previous"] = evaluate(args.trials)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({key: {"total_upgrade_gold":value["total_upgrade_gold"],"results":value["results"]}
                      for key,value in report.items()}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
