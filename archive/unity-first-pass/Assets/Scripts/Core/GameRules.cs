using System;
using System.Collections.Generic;
using UnityEngine;

namespace LastHook
{
    public enum Upgrade { Rope, Impulse, Grip, Backpack, Magnet, Recovery }
    public enum RunMode { Summit, Endless }
    public enum MaterialKind { Stone, Root, Spring, Ice, Crystal }

    public static class GameRules
    {
        public const float MetersPerUnit = 10f;
        public const float ZoneUnits = 20f;
        public const float SummitUnits = ZoneUnits * 6;
        public const float FallLimitUnits = 10f;
        public const float Gravity = 14f;
        public const int MaxLevel = 6;
        public static readonly string[] ZoneNames = { "Лес", "Скалы", "Руины", "Лёд", "Вулкан", "Небеса" };
        public static readonly string[] UpgradeNames = { "Длина каната", "Импульс", "Захват", "Рюкзак", "Магнит", "Сохранение добычи" };
        public static readonly int[] BasePrices = { 120, 360, 900, 2100, 4200 };
        public static readonly float[] PriceWeights = { 1f, 1f, .9f, 1.1f, .8f, .9f };
        public static readonly float[] RopeLengths = { 5.5f, 6.3f, 7.4f, 8.7f, 10.2f, 12f };
        public static readonly float[] ImpulseFactors = { 1f, 1.08f, 1.16f, 1.25f, 1.35f, 1.46f };
        public static readonly float[] GripRadii = { .32f, .38f, .45f, .50f, .56f, .63f };
        public static readonly int[] RecoveryPercents = { 30, 43, 56, 69, 82, 95 };
        public static readonly float[] MagnetRadii = { 0f, .35f, .65f, 1f, 1.4f, 1.8f };
        public static readonly int[] LootPrices = { 40, 75, 130, 220, 360, 560 };
        public static readonly string[] LootNames = { "Медная находка", "Янтарь", "Древняя реликвия", "Ледяной кристалл", "Обсидиан", "Небесный осколок" };

        public static int ZoneAt(float units) { return Mathf.Clamp(Mathf.FloorToInt(units / ZoneUnits), 0, 5); }
        public static int UnlockLevel(float bestMeters) { return Mathf.Clamp(1 + Mathf.FloorToInt(bestMeters / (ZoneUnits * MetersPerUnit)), 1, MaxLevel); }
        public static int Cost(Upgrade kind, int currentLevel)
        {
            if (currentLevel < 1 || currentLevel >= MaxLevel) return 0;
            return Mathf.RoundToInt(BasePrices[currentLevel - 1] * PriceWeights[(int)kind]);
        }
        public static int HeightGold(float heightMeters)
        {
            // Each 10 m band is counted once using the highest height in this run.
            int bands = Mathf.Max(0, Mathf.FloorToInt(heightMeters / 10f));
            int result = 0;
            for (int band = 1; band <= bands; band++) result += 2 + Mathf.Min((band - 1) / 20, 7);
            return result;
        }
        public static bool CanGrip(MaterialKind material, int level)
        {
            return (material != MaterialKind.Ice || level >= 3) && (material != MaterialKind.Crystal || level >= 5);
        }
        public static string UpgradeValue(Upgrade kind, int level)
        {
            int i = Mathf.Clamp(level - 1, 0, 5);
            switch (kind)
            {
                case Upgrade.Rope: return (RopeLengths[i] * MetersPerUnit).ToString("0") + " м";
                case Upgrade.Impulse: return "+" + Mathf.RoundToInt((ImpulseFactors[i] - 1) * 100) + "% к отпусканию";
                case Upgrade.Grip: return level >= 5 ? "камень · лёд · кристалл" : level >= 3 ? "камень · дерево · лёд" : "камень · дерево";
                case Upgrade.Backpack: return level + (level == 1 ? " предмет" : level < 5 ? " предмета" : " предметов");
                case Upgrade.Magnet: return MagnetRadii[i] == 0 ? "сбор при касании" : (MagnetRadii[i] * MetersPerUnit).ToString("0") + " м притяжения";
                default: return RecoveryPercents[i] + "% при поражении";
            }
        }
    }

    [Serializable]
    public class LootItem
    {
        public int id;
        public int tier;
        public int value;
        public LootItem(int id, int tier, int value) { this.id = id; this.tier = tier; this.value = value; }
    }

    [Serializable]
    public class RunSnapshot
    {
        public string id;
        public int seed;
        public RunMode mode;
        public int location;
        public float x, y, vx, vy;
        public int anchorId = -1;
        public float ropeLength;
        public float anchorTime;
        public float flightPeak;
        public float highest;
        public bool launched;
        public bool reviveUsed;
        public bool awaitingRevive;
        public int safeAnchorId = -1;
        public float safeX, safeY;
        public bool boltActive;
        public float boltX, boltY, boltOriginX, boltOriginY, boltDirX, boltDirY, boltTravel;
        public List<LootItem> bag = new List<LootItem>();
        public List<int> picked = new List<int>();
        public List<int> broken = new List<int>();
    }

    [Serializable]
    public class PlayerProfile
    {
        public int version = 1;
        public int gold;
        public int diamonds;
        public int[] levels = { 1, 1, 1, 1, 1, 1 };
        public float bestMeters;
        public float endlessBestMeters;
        public int reachedZones = 1;
        public bool summitCleared;
        public bool secondLocationOwned;
        public bool thirdLocationOwned;
        public int runs;
        public int summitWins;
        public string lastSettledRun;
        public RunSnapshot active;

        public int Level(Upgrade kind) { return levels[(int)kind]; }
        public void Normalize()
        {
            gold = Mathf.Max(0, gold); diamonds = Mathf.Max(0, diamonds);
            bestMeters = Mathf.Max(0, bestMeters); endlessBestMeters = Mathf.Max(0, endlessBestMeters);
            if (levels == null || levels.Length != 6) levels = new[] { 1, 1, 1, 1, 1, 1 };
            for (int i = 0; i < levels.Length; i++) levels[i] = Mathf.Clamp(levels[i], 1, 6);
            reachedZones = Mathf.Clamp(reachedZones, 1, 6);
            if (active != null)
            {
                if (active.bag == null) active.bag = new List<LootItem>();
                if (active.picked == null) active.picked = new List<int>();
                if (active.broken == null) active.broken = new List<int>();
                if (active.id == lastSettledRun) active = null;
            }
        }

        public bool Purchase(Upgrade kind, out string message)
        {
            int level = Level(kind);
            if (level == 6) { message = "Уже максимальный уровень"; return false; }
            if (level + 1 > reachedZones) { message = "Достигни зоны «" + GameRules.ZoneNames[level] + "»"; return false; }
            int price = GameRules.Cost(kind, level);
            if (gold < price) { message = "Не хватает " + (price - gold) + " золота"; return false; }
            gold -= price; levels[(int)kind]++;
            message = "Улучшено: " + GameRules.UpgradeNames[(int)kind]; return true;
        }

        public int Reach(float units)
        {
            bestMeters = Mathf.Max(bestMeters, units * GameRules.MetersPerUnit);
            int zone = GameRules.UnlockLevel(bestMeters);
            int bonus = 0;
            while (reachedZones < zone) { reachedZones++; bonus += 100 * reachedZones; diamonds += 3; }
            gold += bonus;
            return bonus;
        }
    }

    public sealed class RunEconomy
    {
        public readonly List<LootItem> Bag = new List<LootItem>();
        public readonly HashSet<int> Picked = new HashSet<int>();
        public int TotalValue { get { int value = 0; foreach (var item in Bag) value += item.value; return value; } }
        public bool TryPick(LootItem item, int capacity, int backpackLevel)
        {
            // No replacement, even if the incoming item is much more expensive.
            if (item == null || Picked.Contains(item.id) || Bag.Count >= capacity || item.tier >= backpackLevel) return false;
            Bag.Add(item); Picked.Add(item.id); return true;
        }
        public void Discard(int index) { if (index >= 0 && index < Bag.Count) Bag.RemoveAt(index); }
        public int RetainedValue(int recoveryLevel, bool summitSuccess)
        {
            return summitSuccess ? TotalValue : TotalValue * GameRules.RecoveryPercents[Mathf.Clamp(recoveryLevel - 1, 0, 5)] / 100;
        }
        public Settlement Settle(PlayerProfile profile, string runId, RunMode mode, float highestUnits, bool success)
        {
            if (string.IsNullOrEmpty(runId) || profile.lastSettledRun == runId) return new Settlement { duplicate = true };
            bool summitSuccess = success && mode == RunMode.Summit;
            int height = GameRules.HeightGold(highestUnits * GameRules.MetersPerUnit);
            int loot = RetainedValue(profile.Level(Upgrade.Recovery), summitSuccess);
            int finish = summitSuccess ? 300 : 0;
            bool first = summitSuccess && !profile.summitCleared;
            if (first) { finish += 1000; profile.diamonds += 20; }
            profile.gold += height + loot + finish;
            profile.runs++;
            if (summitSuccess) { profile.summitCleared = true; profile.summitWins++; }
            if (mode == RunMode.Endless) profile.endlessBestMeters = Mathf.Max(profile.endlessBestMeters, highestUnits * GameRules.MetersPerUnit);
            profile.lastSettledRun = runId; profile.active = null;
            return new Settlement { height = height, loot = loot, carried = TotalValue, finish = finish, firstSummit = first, success = summitSuccess };
        }
    }

    public struct Settlement
    {
        public int height, loot, carried, finish;
        public bool duplicate, success, firstSummit;
        public int Total { get { return height + loot + finish; } }
    }
}
