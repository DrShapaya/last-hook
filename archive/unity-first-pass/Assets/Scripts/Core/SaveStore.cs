using System;
using System.IO;
using UnityEngine;

namespace LastHook
{
    public static class SaveStore
    {
        public static string DirectoryPath
        {
            get
            {
                string custom = Environment.GetEnvironmentVariable("LASTHOOK_SAVE_DIR");
                if (!string.IsNullOrEmpty(custom)) return custom;
#if UNITY_ANDROID && !UNITY_EDITOR
                return Application.persistentDataPath;
#else
                return Path.GetFullPath(Path.Combine(Application.dataPath, "../UserData"));
#endif
            }
        }
        public static string FilePath { get { return Path.Combine(DirectoryPath, "profile.json"); } }

        public static PlayerProfile Load()
        {
            foreach (string path in new[] { FilePath, FilePath + ".bak" })
            {
                try
                {
                    if (!File.Exists(path)) continue;
                    string text = File.ReadAllText(path);
                    if (!text.TrimStart().StartsWith("{") || !text.Contains("\"version\"")) continue;
                    var profile = JsonUtility.FromJson<PlayerProfile>(text);
                    if (profile != null) { profile.Normalize(); return profile; }
                }
                catch (Exception e) { Debug.LogWarning("Не удалось прочитать сохранение: " + e.Message); }
            }
            return new PlayerProfile();
        }

        public static bool Save(PlayerProfile profile)
        {
            try
            {
                Directory.CreateDirectory(DirectoryPath);
                string pending = FilePath + ".tmp";
                File.WriteAllText(pending, JsonUtility.ToJson(profile, true));
                if (File.Exists(FilePath)) File.Replace(pending, FilePath, FilePath + ".bak");
                else File.Move(pending, FilePath);
                return true;
            }
            catch (Exception e) { Debug.LogError("Не удалось сохранить прогресс: " + e.Message); return false; }
        }
    }
}
