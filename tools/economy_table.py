"""Deterministic economy table for the chat 4 balance (NOT a player prediction).

Run: python tools/economy_table.py [--output docs/validation/chat4-economy.json]

Inputs: game/data/balance.json and the placement statistics of generator v15
(docs/validation/chat4-loot-fixture.json, written by tools/loot_fixture.gd).
Three explicit skill profiles climb run after run with expected values only
(no random numbers): reached share of the expedition, summit chance, share of
coins and branch finds taken. After every run the profile buys the cheapest
unlocked upgrade it can afford. Everything assumed is listed in PROFILES.
"""
import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
B = json.loads((ROOT / "game/data/balance.json").read_text(encoding="utf-8"))
LOOT = json.loads((ROOT / "docs/validation/chat4-loot-fixture.json").read_text(encoding="utf-8"))

# reach: expected share of the expedition reached on the first run, gain per
# run, summit: chance once the whole route is reached, coins/branch: share of
# main-path coins and of branch finds taken, minutes: a full summit climb.
PROFILES = {
    "novice":  {"reach": .30, "gain": .07, "summit": .35, "coins": .45, "branch": .15, "minutes": 9.0},
    "learned": {"reach": .55, "gain": .12, "summit": .60, "coins": .60, "branch": .35, "minutes": 6.5},
    "expert":  {"reach": .85, "gain": .15, "summit": .85, "coins": .75, "branch": .60, "minutes": 5.0},
}
MENU_MINUTES = .5


def rnd(x):
    return math.floor(x + .5)


def price(kind, level):
    if kind == 2:
        return B["hook_prices"][level - 1]
    return rnd(B["upgrade_prices"][level - 1] * B["upgrade_weights"][kind])


def max_level(kind):
    return len(B["hook_counts"]) if kind == 2 else len(B["slowmo_seconds"]) if kind == 7 else len(B["rope_lengths"])


def height_gold(units):
    bands = max(0, math.floor(units * B["meters_per_unit"] / 10))
    return sum(2 + min((band - 1) // 20, 7) for band in range(1, bands + 1))


def unlocked(state):
    result = 1
    for target in range(2, len(B["upgrade_gates"]) + 1):
        gate = B["upgrade_gates"][target - 1]
        if "acts" in gate and state["acts"] < gate["acts"]:
            break
        if "summit_or_contracts" in gate and not state["summit"] and state["contracts"] < gate["summit_or_contracts"]:
            break
        result = target
    return result


def tier_values(location):
    scale = B["location_value_scale"][location]
    return [rnd(v * scale) for v in B["loot_values"]]


def run_income(profile, state, location, reach, success, early_only=False):
    """Expected gold of one run, split by source."""
    height = B["locations"][location]["height_units"]
    stats = LOOT[str(location)]
    share = 1.0 if success else reach
    units = height * share
    capacity = B["capacities"][state["levels"][3] - 1]
    # Coins: main-path coins scale with the climbed share, branch coins
    # (scatter and caches) with the branch habit as well.
    main_coins = (stats["roles"].get("main_coin", 0) + stats["roles"]["main_safe"] / 2) * B["coins"]["single"]
    branch_coins = stats["coin_gold"] - main_coins
    coins = share * (profile["coins"] * main_coins + profile["branch"] * branch_coins)
    # Bag: the best tiers reached fill the slots (the player swaps by hand).
    top = max(0, min(5, int(share * 6 - 1e-9)))
    values = sorted(tier_values(location)[: top + 1], reverse=True)
    seen = max(1, round(stats["families"]["valuable"] * share))
    slots = min(capacity, seen)
    bag = sum(values[i % len(values)] for i in range(slots))
    recovery = 100 if success else B["recovery_percents"][state["levels"][5] - 1]
    loot = bag if success else math.floor(bag * recovery / 100)
    finish = B["summit_repeat_bonus"] if success else 0
    contract = 0
    if success and not early_only:
        contract = profile["branch"] * B["contracts"]["gold"][location] * (1 if state["contracts"] < 9 else B["contracts"]["repeat_share"])
    zone = 0
    zones = min(6, 1 + int(units // B["zone_units"]))
    while state["zones"] < zones:
        state["zones"] += 1
        zone += B["new_zone_gold_per_index"] * state["zones"]
    if success and not state["summit"]:
        finish += B["first_summit_gold"]
    return {"height": height_gold(units), "coins": coins, "bag": loot, "finish": finish, "contract": contract, "zones": zone}


def simulate(name, profile, hours=6.0):
    state = {"levels": [1] * 8, "gold": 0.0, "acts": 1, "summit": False, "contracts": 0.0, "zones": 1, "tokens": 0.0,
             "sets": {}, "diamonds": 0, "locations": 1, "cleared": 0}
    minutes = 0.0
    run = 0
    totals = {"height": 0.0, "coins": 0.0, "bag": 0.0, "finish": 0.0, "contract": 0.0, "zones": 0.0}
    milestones = {}
    incomes = []
    location = 0
    while minutes < hours * 60:
        run += 1
        reach = min(1.0, profile["reach"] + profile["gain"] * (run - 1) + .02 * sum(l - 1 for l in state["levels"]))
        success_chance = profile["summit"] if reach >= 1.0 else 0.0
        # Expected values: a run is a blend of success and failure.
        win = run_income(profile, dict(state, zones=state["zones"]), location, reach, True) if success_chance else None
        lose = run_income(profile, state, location, reach, False)
        income = {k: success_chance * (win[k] if win else 0) + (1 - success_chance) * lose[k] for k in lose}
        if win and success_chance:
            state["zones"] = max(state["zones"], 6)
        for k in totals:
            totals[k] += income[k]
        state["gold"] += sum(income.values())
        incomes.append(sum(income.values()))
        state["acts"] = max(state["acts"], 1 + (reach > 1 / 3) + (reach > 2 / 3))
        if success_chance:
            state["contracts"] += success_chance * profile["branch"]
            # Tokens: the first completion of a contract, and one per three
            # set parts carried to the summit (sets of three parts).
            parts = LOOT[str(location)]["set_parts"] * profile["branch"]
            state["tokens"] += success_chance * (profile["branch"] + parts / B["set_parts"])
            state["diamonds"] += success_chance * (B["first_summit_diamonds"] if not state["summit"] else B["summit_repeat_diamonds"])
            if success_chance >= .5 or run > 3:
                if not state["summit"]:
                    milestones.setdefault("first_summit_min", round(minutes + profile["minutes"], 1))
                state["summit"] = True
        minutes += profile["minutes"] * max(.25, reach) + MENU_MINUTES
        # Expeditions: the second one after the first summit and 2500 gold.
        unlock2 = B["locations"][1]["unlock"]
        if state["locations"] == 1 and state["summit"] and state["gold"] >= unlock2["gold"]:
            state["gold"] -= unlock2["gold"]
            state["locations"] = 2
            location = 1
            milestones["second_expedition_min"] = round(minutes, 1)
        unlock3 = B["locations"][2]["unlock"]
        if state["locations"] == 2 and location == 1 and success_chance and reach >= 1.0:
            state["cleared"] = 2
        if state["locations"] == 2 and state["cleared"] >= 2 and state["tokens"] >= unlock3["tokens"] and state["diamonds"] >= unlock3["diamonds"]:
            state["locations"] = 3
            location = 2
            milestones["third_expedition_min"] = round(minutes, 1)
        # Buy the cheapest unlocked level the wallet allows.
        bought = True
        while bought:
            bought = False
            options = []
            for kind in range(8):
                level = state["levels"][kind]
                if level >= max_level(kind) or (kind != 2 and level + 1 > unlocked(state)):
                    continue
                options.append((price(kind, level), kind))
            options.sort()
            if options and options[0][0] <= state["gold"]:
                cost, kind = options[0]
                state["gold"] -= cost
                state["levels"][kind] += 1
                bought = True
                milestones.setdefault("first_purchase_min", round(minutes, 1))
                milestones.setdefault("first_purchase_run", run)
                if state["levels"][kind] == 3 and kind in (0, 1, 6):
                    milestones.setdefault("first_specialization_min", round(minutes, 1))
        if all(state["levels"][k] >= max_level(k) for k in range(8)):
            milestones.setdefault("full_kit_min", round(minutes, 1))
            break
    earned = sum(totals.values())
    shares = {k: round(v / earned * 100, 1) for k, v in totals.items()} if earned else {}
    average = sum(incomes[-10:]) / max(1, len(incomes[-10:]))
    return {"profile": name, "assumptions": profile, "runs": run, "minutes": round(minutes, 1), "milestones": milestones,
            "income_share_percent": shares, "avg_run_income_last10": round(average),
            "consumable_share_percent": {c["id"]: round(c["price_gold"] / average * 100, 1) for c in B["consumables"]},
            "levels_at_end": state["levels"]}


def farm_rate(profile):
    """Gold per minute: repeating the first act (to 400 m) vs a full summit, same kit."""
    state = {"levels": [3, 3, 2, 3, 3, 3, 3, 2], "gold": 0, "acts": 3, "summit": True, "contracts": 2, "zones": 6, "tokens": 0}
    short = run_income(profile, dict(state), 0, 1 / 3, False, True)
    short_min = profile["minutes"] / 3 + MENU_MINUTES
    full = run_income(profile, dict(state), 0, 1.0, True)
    full_min = profile["minutes"] + MENU_MINUTES
    return {"early_400m_per_min": round(sum(short.values()) / short_min, 1), "full_summit_per_min": round(sum(full.values()) / full_min, 1),
            "summit_coin_share_percent": round(full["coins"] / sum(full.values()) * 100, 1)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=str(ROOT / "docs/validation/chat4-economy.json"))
    args = parser.parse_args()
    result = {"balance_version": B.get("balance_version"), "profiles": [], "farm": {}}
    for name, profile in PROFILES.items():
        result["profiles"].append(simulate(name, profile))
        result["farm"][name] = farm_rate(profile)
    Path(args.output).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    for row in result["profiles"]:
        print(row["profile"], json.dumps(row["milestones"]), json.dumps(row["income_share_percent"]), "avg", row["avg_run_income_last10"], json.dumps(row["consumable_share_percent"]))
    print("farm", json.dumps(result["farm"]))


if __name__ == "__main__":
    main()
