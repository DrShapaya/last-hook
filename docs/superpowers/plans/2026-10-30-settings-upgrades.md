# Настройки, улучшения и стиль меню: план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Четыре подраздела настроек с рабочими параметрами, пять категорий улучшений с новой экономикой и единый стиль меню без потери прогресса старых сохранений.

**Architecture:** Настройки живут в новом чистом классе `GameSettings` и словаре `profile["settings"]`, применяет их `main.gd`. Улучшения становятся данными в `balance.json` со строковыми ключами. `GameModel` остаётся единственной точкой чтения значений, а миграция замораживает экономику v6 в константах.

**Tech Stack:** Godot 4.7.2, GDScript, headless-тесты `game/tests/test_*.gd`, запечённые уровни `game/levels`.

**Spec:** `docs/superpowers/specs/2026-10-30-settings-upgrades-design.md`. Читать вместе с планом: таблицы значений, пресетов и миграции берутся оттуда без изменений.

## Global Constraints

- Коммитов нет: спецификация разрешает их только по отдельной просьбе. Вместо коммита каждая задача кончается прогоном тестов. Правки идут поверх незакоммиченных файлов, чужие изменения не откатывать.
- Команда теста: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/test_NAME.gd`. Успех: код выхода 0 и нет строк `FAILED`.
- Запуск из корня репозитория.
- Новый тест устроен как `game/tests/test_economy.gd`: `extends SceneTree`, `check(condition, description)`, `_initialize` с `call_deferred`, выход с кодом 1 при непустом `failures`.
- Весь текст интерфейса на русском.
- Код повторяет соседний стиль: компактный GDScript, статическая типизация, комментарии на английском и только там, где причина неочевидна.
- Мировые единицы не меняются, цены и значения только из таблиц спецификации.
- Стандартные `HSlider`, `OptionButton` и темы Godot не применяются.
- Значения скоростей и радиусов читаются только через `GameModel`.

## Review Focus

1. Загрузка старого сохранения с активной попыткой, где длина каната или значение из снимка больше нового максимума: попытка продолжается, значения зажаты. Тест в задаче 11.
2. Испорченный вручную `settings`: строка вместо числа, громкость 999, неизвестная схема, `key_bindings` не словарь. Игра стартует со значениями по умолчанию. Тест в задаче 2.
3. Действие осталось без клавиши после конфликта: игра не падает, на экране «Нет клавиши», сброс возвращает все клавиши. Тест в задаче 5.
4. Смена размера текста или цветов при кэшированных страницах меню: все вкладки перестроены, старый вид не остаётся. Тест в задаче 8.
5. Музыка на 0%, затем снова выше 0: трек возобновляется без перезапуска игры. Тест в задаче 4.

---

## Этап 1. Значения по умолчанию, настройки, стиль

### Task 1: Значения по умолчанию и версия профиля 7

**Files:**
- Modify: `game/scripts/game_model.gd`, `game/scripts/lobby_view.gd`, `game/scripts/main.gd`
- Test: `game/tests/test_rules.gd`

**Interfaces:**
- Produces: `GameModel.build_version() -> String`, `PROFILE_VERSION == 7`, ветка `if source_version<7:` в `load_profile`, которую расширяют задачи 2 и 11.

- [ ] **Step 1: Написать падающие проверки**

```gdscript
var fresh := GameModel.fresh_profile()
check(fresh["graphics_quality"]=="high" and fresh["loot_prices"]=="always","new players get high quality and permanent prices")
check(GameModel.build_version()==str(ProjectSettings.get_setting("application/config/version")),"version comes from the project")
```

Плюс проверка загрузки: файл v6 с `graphics_quality:"balanced"` читается как `high`, с `battery` остаётся `battery`, а `loot_prices:"near"` сохраняется после `save()` и новой загрузки.

- [ ] **Step 2: Запустить `test_rules`, ожидать падение на этих проверках**
- [ ] **Step 3: Реализовать**

Добавить `loot_prices` в `fresh_profile()`, сменить значение по умолчанию на `always` также в `lobby_view.gd` и `main.gd:2347`. Заменить `BUILD_VERSION` в `lobby_view.gd:1474` и `main.gd:2095`. Заменить запасное значение `"balanced"` у `graphics_quality` на `"high"` в `main.gd`.

- [ ] **Step 4: Запустить `test_rules`, `test_visuals`, ожидать успех**

### Task 2: Схема настроек GameSettings

**Files:**
- Create: `game/scripts/game_settings.gd`
- Modify: `game/scripts/game_model.gd`
- Test: `game/tests/test_settings.gd` (новый)

**Interfaces:**
- Produces, `class_name GameSettings extends RefCounted`:
  - `static func defaults() -> Dictionary`
  - `static func sanitize(source: Variant) -> Dictionary`
  - `const PRESETS: Dictionary` с ключами `high`, `balanced`, `battery`
  - `static func apply_preset(settings: Dictionary, preset: String) -> void`
  - `static func detect_preset(settings: Dictionary) -> String`, вернёт `custom`, если совпадения нет
- Ключи и допустимые значения:

| Ключ | Значения | По умолчанию |
|---|---|---|
| `shadows` | `off`, `medium`, `high` | `high` |
| `decor`, `sky` | `battery`, `balanced`, `high` | `high` |
| `particles` | `off`, `reduced`, `full` | `full` |
| `glow` | bool | `true` |
| `render_scale` | `.6`, `.75`, `.85`, `1.0` | `1.0` |
| `fps_limit` | `0`, `60`, `30` | `0` |
| `master_volume`, `music_volume`, `sfx_volume` | 0–100, шаг 5 | 100 |
| `sensitivity` | 50–150, шаг 10 | 100 |
| `hold_seconds` | .15–.5, шаг .05, и .28 | .28 |
| `text_scale` | 100, 115, 130 | 100 |
| `high_contrast`, `reduce_effects`, `persistent_hints` | bool | `false` |
| `color_scheme` | `normal`, `red_green`, `blue_yellow` | `normal` |
| `key_bindings` | словарь, `action` → массив кодов клавиш | `{}` |

Пустой `key_bindings` значит клавиши по умолчанию. `profile["graphics_quality"]` принимает `high`, `balanced`, `battery`, `custom`.

- [ ] **Step 1: Написать `test_settings.gd`**

```gdscript
var dirty := {"master_volume":999,"sfx_volume":"громко","color_scheme":"neon","render_scale":.33,"key_bindings":5,"unknown":1}
var clean := GameSettings.sanitize(dirty)
check(clean["master_volume"]==100 and clean["sfx_volume"]==100,"bad volumes fall back")
check(clean["color_scheme"]=="normal" and clean["render_scale"]==1.0,"bad choices fall back")
check(clean["key_bindings"].is_empty() and not clean.has("unknown"),"unknown data is dropped")
check(GameSettings.sanitize(null)==GameSettings.defaults(),"missing settings become defaults")
var custom := GameSettings.defaults()
GameSettings.apply_preset(custom,"battery")
check(custom["shadows"]=="off" and custom["decor"]=="battery" and custom["sky"]=="battery" and custom["particles"]=="reduced" and not custom["glow"] and custom["render_scale"]==.75,"battery preset values")
check(custom["fps_limit"]==0 and GameSettings.detect_preset(custom)=="battery","preset keeps the fps limit")
custom["glow"] = true
check(GameSettings.detect_preset(custom)=="custom","a manual change is custom")
```

Проверка профиля: v6 с `sound:false`, `music:true` даёт `sfx_volume==0`, `music_volume==100`.

- [ ] **Step 2: Запустить `test_settings`, ожидать ошибку разбора `GameSettings`**
- [ ] **Step 3: Реализовать `game_settings.gd` и подключить**

`settings` в `fresh_profile()`. В `load_profile` всегда вызывать `GameSettings.sanitize`, в ветке `<7` перевести `sound` и `music` в громкости. Ключи `sound`, `music` остаются в профиле, пока их не уберёт задача 4.

- [ ] **Step 4: Запустить `test_settings`, ожидать успех**

### Task 3: Раздельное применение графики

**Files:**
- Modify: `game/scripts/main.gd:440-502`, `main.gd:523`, `main.gd:551`, `main.gd:593`, `game/scripts/mountain_world.gd:131-143`, `game/scripts/loot_visuals.gd`, `game/scripts/explorer_view.gd`, `game/scripts/procedural_sky.gd`
- Test: `game/tests/test_visuals.gd`, `game/tests/test_settings.gd`

**Interfaces:**
- Consumes: `GameSettings`.
- Produces:
  - `main.set_setting(key: String, value: Variant) -> void`: записывает, применяет, просит сохранить, обновляет `graphics_quality` через `detect_preset`
  - `main.set_graphics_preset(preset: String) -> void`
  - `main.apply_all_settings() -> void`
  - `MountainWorld.set_decor_quality(value: String)`, `set_effects_quality(value: String)`, `set_sky_quality(value: String)`
  - `ExplorerView.set_effects_quality(value: String)`

- [ ] **Step 1: Написать падающие проверки**

Частицы отдельно от декора: `LootVisuals.build` с декором `high` и частицами `off` не создаёт блик и ореол; с `reduced` создаёт ореол без блика. `set_setting("glow",false)` выключает `scene_environment.glow_enabled` и даёт `graphics_quality=="custom"`. `set_setting("fps_limit",30)` даёт `Engine.max_fps==30`, а `0` даёт `0`. `set_setting("render_scale",.75)` меняет `get_viewport().scaling_3d_scale`. `set_setting("sky","battery")` даёт размер неба 0,34.

- [ ] **Step 2: Запустить, ожидать падение**
- [ ] **Step 3: Реализовать**

`_apply_shadow_preset` принимает `off`, `medium`, `high`. `visual_quality` остаётся декором и выбирает запечённую папку. Условие `quality!="battery"` в `loot_visuals.gd` и `explorer_view.gd` заменить на `effects_quality`. Масштаб задать через `get_viewport().scaling_3d_scale`. Ключ подготовленного мира строить от `decor`. Сохранить комментарий о мерцании при лимите FPS и вертикальную синхронизацию.

- [ ] **Step 4: Запустить `test_visuals`, `test_settings`, `test_integration`, ожидать успех**

### Task 4: Шины и громкости

**Files:**
- Modify: `game/scripts/main.gd:193-201`, `main.gd:2397`, `main.gd:2416`, `main.gd:2440`, `game/scripts/music_player.gd`, `game/scripts/game_hud.gd:715-720`, `game/scripts/game_model.gd`
- Test: `game/tests/test_settings.gd`, `game/tests/test_polish.gd`

**Interfaces:**
- Consumes: `main.set_setting`.
- Produces: шины `Music`, `SFX`; `main.apply_audio() -> void`; `MusicPlayer.set_enabled(on: bool)` остаётся, вызывается при переходе громкости через 0.

- [ ] **Step 1: Написать падающие проверки**

```gdscript
game.set_setting("music_volume",0)
check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and not game.music.enabled,"silent music stops")
game.set_setting("music_volume",50)
check(game.music.enabled and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),linear_to_db(.5)),"music returns at half volume")
check(game.audio.bus=="SFX" and game.focus_audio.bus=="SFX" and game.music.players[0].bus=="Music","players use their buses")
```

- [ ] **Step 2: Запустить, ожидать падение**
- [ ] **Step 3: Реализовать**

Шины создавать при старте, отправка в `Master`. 0% глушит шину. Проверки `profile.get("sound")` заменить на `sfx_volume>0`, убрать `toggle_sound`, `toggle_music`, ключи `sound`, `music` из `fresh_profile()`. Строка `main.gd:747` копирует теперь `settings`.

- [ ] **Step 4: Запустить `test_settings`, `test_polish`, `test_menus`, ожидать успех**

### Task 5: Клавиши, чувствительность и удержание

**Files:**
- Create: `game/scripts/key_bindings.gd`
- Modify: `game/scripts/main.gd:929-938`, `main.gd:1363-1364`, `main.gd:996`, `game/scripts/climb_gesture.gd`, `game/scripts/game_hud.gd:1380-1392`
- Test: `game/tests/test_settings.gd`, `game/tests/test_controls.gd`

**Interfaces:**
- Produces, `class_name KeyBindings extends RefCounted`:
  - `const ACTIONS := ["swing_left","swing_right","rope_up","rope_down","release","item_1","item_2"]`
  - `const DEFAULTS: Dictionary` с WASD, стрелками, пробелом, 1 и 2
  - `static func apply(bindings: Dictionary) -> void`: создаёт действия `InputMap` с физическими клавишами
  - `static func rebind(bindings: Dictionary, action: String, keycode: int) -> Dictionary`: возвращает новый словарь
  - `static func key_text(bindings: Dictionary, action: String) -> String`: пустое значение даёт `Нет клавиши`
- `ClimbGesture`: поля `hold_seconds := VERTICAL_HOLD_SECONDS`, `sensitivity := 1.0`, статический `axis` не меняется; стик и смотка используют `STICK_RADIUS/sensitivity`, `REEL_EXTENT/sensitivity`.

- [ ] **Step 1: Написать падающие проверки**

```gdscript
var moved := KeyBindings.rebind({},"release",KEY_W)
check(moved["release"]==[KEY_W],"rebinding replaces the action keys")
check(KEY_W not in moved["rope_up"] and KEY_UP in moved["rope_up"],"a taken key leaves the other action")
var empty := KeyBindings.rebind({"release":[KEY_Q]},"swing_left",KEY_Q)
check(KeyBindings.key_text(empty,"release")=="Нет клавиши","an empty action says so")
check(KeyBindings.rebind(empty,"release",KEY_ESCAPE)==empty,"Esc stays reserved")
var gesture := ClimbGesture.new()
gesture.hold_seconds = .5
gesture.begin(Vector2.ZERO,0,1)
gesture.move(Vector2(0,-80),0,1)
check(float(gesture.sample(.4)["reel"])==0.0 and float(gesture.sample(.51)["reel"])>0.0,"hold delay follows the setting")
```

Плюс проверка: `sensitivity = 1.5` даёт `pump` в полтора раза больше на том же смещении, а действие без клавиши не мешает `_physics_process`.

- [ ] **Step 2: Запустить, ожидать падение**
- [ ] **Step 3: Реализовать**

`KeyBindings.apply` вызвать в `apply_all_settings`. `Input.is_physical_key_pressed` заменить на `Input.get_axis` по действиям, `event.keycode` пробела и цифр заменить на `event.is_action_pressed`. Текст подсказок в `game_hud.gd` брать из `KeyBindings.key_text`. Создание `ClimbGesture` получает значения из настроек.

- [ ] **Step 4: Запустить `test_settings`, `test_controls`, `test_gameplay_foundation`, ожидать успех**

### Task 6: Ползунок, строка настроек и прокрутка

**Files:**
- Modify: `game/scripts/menu_surface.gd`, `game/scripts/lobby_view.gd`
- Test: `game/tests/test_menus.gd`

**Interfaces:**
- Produces:
  - `class RopeSlider extends Control` в `menu_surface.gd`: поля `value`, `minimum`, `maximum`, `step`, сигнал `changed(value: float)`, `committed(value: float)`
  - `MenuSurface.slider(parent, at: Vector2, width: float, value: float, minimum: float, maximum: float, step: float, format: Callable, callback: Callable) -> RopeSlider`
  - `MenuSurface.settings_row(parent, y: float, width: float, title_text: String, hint: String) -> Control`: строка с подписью слева, возвращает контейнер для элемента справа
  - `LobbyView.scroll_page(height: float) -> Control`: прокручиваемое содержимое страницы

- [ ] **Step 1: Написать падающие проверки**

Ползунок: нажатие в середине дорожки 0–100 шаг 5 даёт 50 и один `changed`; перетаскивание за правый край даёт 100; касательная полоса не ниже 44. Прокрутка: вертикальное смещение на 40 пикселей двигает содержимое, а ползунок не меняет; горизонтальное от ползунка меняет значение и страницу не листает; горизонтальное вне элементов меняет вкладку меню.

- [ ] **Step 2: Запустить `test_menus`, ожидать падение**
- [ ] **Step 3: Реализовать**

Рисунок ползунка: углублённая канавка как в `RouteLine`, смотанный канат с диагональными прядями до значения, крюк-бегунок из цветов `HOLD` и `INK`. Направление жеста фиксировать по первым 12 пикселям. `ScrollContainer` со скрытой полосой и `follow_focus`.

- [ ] **Step 4: Запустить `test_menus`, `test_responsive`, ожидать успех**

### Task 7: Страницы «Графика» и «Звук и управление»

**Files:**
- Create: `game/scripts/settings_page.gd`, класс-помощник с построением страниц, чтобы `lobby_view.gd` не рос
- Modify: `game/scripts/lobby_view.gd:1382-1475`, `game/scripts/game_hud.gd`, `game/scripts/main.gd:314-325`
- Test: `game/tests/test_menus.gd`, `game/tests/test_responsive.gd`

**Interfaces:**
- Consumes: `slider`, `settings_row`, `scroll_page`, `main.set_setting`, `main.set_graphics_preset`, `KeyBindings`.
- Produces: `hud.settings_section: String` со значениями `graphics`, `controls`, `accessibility`, `about`; `SettingsPage.build(lobby: LobbyView) -> void`; экранный аргумент `--screen=settings_graphics`, `settings_controls`, `settings_accessibility`, `settings_about` для снимков.

- [ ] **Step 1: Написать падающие проверки**

Четыре сегмента «Графика», «Звук», «Доступность», «О нас». Смена пресета обновляет элементы на странице. Изменение пункта показывает выделенный сегмент «Своя». На сенсорных устройствах строки «Клавиши» нет. Подпись у «60» содержит предупреждение. Инструкция внизу показывает текущие клавиши. Вся страница помещается в ширину экрана в портрете и ландшафте.

- [ ] **Step 2: Запустить, ожидать падение**
- [ ] **Step 3: Реализовать**

Порядок пунктов строго по таблицам спецификации. Масштаб камеры перенести на страницу управления. Экран клавиш: строка на действие, нажатие ждёт клавишу, Esc отменяет, кнопка «Сбросить». В ландшафте две колонки. `settings_switch` и `segmented` использовать как есть. Подписи сегментов: «Графика», «Звук», «Доступность», «О нас». Полное название «Звук и управление» стоит заголовком страницы.

- [ ] **Step 4: Запустить `test_menus`, `test_responsive`, ожидать успех**

### Task 8: Доступность

**Files:**
- Modify: `game/scripts/menu_surface.gd:13-30`, `game/scripts/game_hud.gd:86-87`, `game_hud.gd:129-160`, `game_hud.gd:1206-1215`, `game_hud.gd:1239`, `game_hud.gd:1380-1392`, `game_hud.gd:613`, `game/scripts/loot_visuals.gd`, `game/scripts/lobby_view.gd:1357-1377`, `game/scripts/settings_page.gd`
- Test: `game/tests/test_settings.gd`, `game/tests/test_responsive.gd`, `game/tests/test_menus.gd`

**Interfaces:**
- Produces:
  - `static func MenuSurface.apply_palette(scheme: String, high_contrast: bool) -> void`
  - `MenuSurface.INK`, `INK_SOFT`, `INK_FAINT`, `COIN`, `DANGER`, `MOSS`, `HOLD`, `LOOT_COLORS` как `static var`
  - `hud.text_scale: float`
  - `hud.effects_reduced() -> bool`
  - `hud.rebuild_all_pages() -> void`: очищает `page_cache` и строит меню заново

- [ ] **Step 1: Написать падающие проверки**

```gdscript
MenuSurface.apply_palette("red_green",false)
check(MenuSurface.LOOT_COLORS[0]!=Color("e4b35e"),"the scheme changes rarity colours")
check(contrast(MenuSurface.DANGER,MenuSurface.STONE)>=3.0,"danger stays readable")
MenuSurface.apply_palette("normal",true)
check(contrast(MenuSurface.INK_SOFT,MenuSurface.STONE)>=7.0,"high contrast darkens soft text")
MenuSurface.apply_palette("normal",false)
check(MenuSurface.INK_SOFT==Color("55636d"),"the default palette returns")
```

`contrast` считает относительную яркость WCAG. Плюс проверки: `text_scale` 130% на всех страницах и в обеих ориентациях не выводит элементы за экран; после смены текста на вкладке улучшений кэшированная страница имеет новый размер шрифта; `reduce_effects` оставляет `slowmo_vignette.flash==0`, а покупка не создаёт `glow`; `persistent_hints` даёт непустую подсказку при всех `learned_controls`.

- [ ] **Step 2: Запустить, ожидать падение**
- [ ] **Step 3: Реализовать**

Палитры подобрать так, чтобы редкости различались при красно-зелёной и сине-жёлтой слепоте, красный заменить оранжевым, зелёный синим. Предупреждения об опасности на уровне не отключать. Страница «Доступность» применяет выбор и вызывает `rebuild_all_pages`. `game_hud.gd` константы `INK` и `GOLD` заменить чтением из `MenuSurface` и проверить, что нигде нет `const`, собранных из них.

- [ ] **Step 4: Запустить `test_settings`, `test_menus`, `test_responsive`, `test_polish`, ожидать успех**

### Task 9: Раздел «О нас»

**Files:**
- Create: `tools/build_changelog.py`, `game/data/changelog.json`, `game/data/about.json`
- Modify: `game/scripts/settings_page.gd`
- Test: `game/tests/test_menus.gd`

**Interfaces:**
- Produces:
  - `changelog.json`: `[{"version":"0.16.0","notes":["..."]}]`, свежая версия первой. Заметки берутся из `### Что нового` в `docs/releases/v*.md`
  - `about.json`: `{"socials":[],"privacy_url":"","contact_email":""}`

- [ ] **Step 1: Написать падающие проверки**

Страница показывает иконку, название, версию из `build_version()`, кнопку «Что нового» и список версий. Кнопка открывает окно заметок свежей версии. При пустом `about.json` кнопок ссылок нет. При подменённом пути с отсутствующим файлом блок скрыт и нет ошибки. `socials:[{"name":"VK","url":"https://vk.com/x"}]` даёт одну кнопку.

- [ ] **Step 2: Запустить, ожидать падение**
- [ ] **Step 3: Реализовать**

Запустить `python tools/build_changelog.py`. Загрузчик принимает путь аргументом для теста. Ссылки открываются `OS.shell_open`, контакт через `mailto:` с версией в теме. В `Release.cmd` ничего не менять: файл обновляется скриптом вручную, это записывается в задаче 14.

- [ ] **Step 4: Запустить `test_menus`, ожидать успех, затем весь набор тестов этапа: `test_settings`, `test_controls`, `test_polish`, `test_responsive`, `test_integration`**

## Этап 2. Улучшения

### Task 10: Данные и модель улучшений

**Files:**
- Modify: `game/data/balance.json`, `game/scripts/game_model.gd`, `game/scripts/rope_sim.gd`, `game/scripts/main.gd:1063-1075`, `main.gd:778`, `main.gd:1662-1663`, `main.gd:1325-1338`, `game/scripts/game_hud.gd:940`, `game/scripts/mountain_layout.gd:385`, `game/scripts/lobby_view.gd:1248-1294` и все вызовы в `game/scripts`, `game/tools`, `game/tests`
- Test: `game/tests/test_rules.gd`, `test_economy.gd`, `test_progression.gd`, `test_polish.gd`, `test_hook.gd`

**Interfaces:**
- Produces в `GameModel`:
  - константы-строки `THROW`, `SWING`, `IMPULSE`, `ROPE`, `REEL_IN`, `REEL_OUT`, `ACCURACY`, `RADIUS`, `DOUBLE`, `BAG`, `MAGNET`, `RECOVERY`, `SLOWMO`, `SLOWMO_REST`
  - `const CATEGORIES := {"movement":[THROW,SWING,IMPULSE],"rope":[ROPE,REEL_IN,REEL_OUT],"hook":[ACCURACY,RADIUS,DOUBLE],"gather":[BAG,MAGNET],"survival":[RECOVERY,SLOWMO,SLOWMO_REST]}`
  - `level(key: String) -> int`, `set_level(key: String, value: int)`, `set_levels(values: Dictionary)`, `max_level(key) -> int`
  - `value(key: String) -> float`, `value_at(key: String, at_level: int) -> float`
  - `cost(key) -> int`, `price_at_level(key, level) -> int`, `upgrade_available(key) -> bool`, `lock_reason(key) -> String`, `purchase(key) -> String`, `upgrade_use(key, at_level) -> String`
  - `swing_force() -> float`, `reel_in_speed() -> float`, `reel_out_speed() -> float`, `hook_spread() -> float`, `hook_radius() -> float`
  - `hook_tips() -> int`: 3 с уровня 3 радиуса, иначе 1
  - `hook_count() -> int`: 2, если куплен двойной и выбран `upgrade_choices.hook==2`
- `RopeSim`: `swing_force`, `reel_in_speed`, `reel_out_speed` вместо `SWING_FORCE`, `adjust_speed`.

- [ ] **Step 1: Обновить тесты под новый API и добавить проверки значений**

```gdscript
var model := GameModel.new("user://test_upgrades.json")
check(model.value(GameModel.THROW)==12.0 and model.value_at(GameModel.THROW,5)==25.0,"throw range")
check(model.value_at(GameModel.REEL_OUT,5)==3.5 and model.value_at(GameModel.SLOWMO,1)==0.0,"rope and slow motion ranges")
check(model.price_at_level(GameModel.THROW,1)==100 and model.price_at_level(GameModel.BAG,4)==1760,"prices are ladder times weight")
var total := 0
for category in GameModel.CATEGORIES.values():
	for key in category:
		for step in range(1,model.max_level(key)): total += model.price_at_level(key,step)
check(total>=33000 and total<=35000,"a full build costs about 34000: %d" % total)
check(not model.upgrade_available(GameModel.ACCURACY) and not model.upgrade_available(GameModel.SLOWMO_REST),"dependent cards start closed")
model.set_level(GameModel.DOUBLE,2)
model.set_level(GameModel.SLOWMO,2)
check(model.upgrade_available(GameModel.ACCURACY) and model.upgrade_available(GameModel.SLOWMO_REST),"dependencies open them")
check(model.hook_count()==2 and model.hook_spread()==8.0 and model.hook_tips()==1,"double hook starts single-tipped")
model.set_level(GameModel.RADIUS,3)
check(model.hook_tips()==3 and model.hook_radius()==.54,"radius brings the three-tip hook")
```

Отдельно в `test_hook`: при `reel_in_speed=2.4`, `reel_out_speed=1.0` смотка на 1 единицу занимает примерно 0,42 с, размотка примерно 1 с. В `test_polish`: замедление 0 не запускает фокус и скрывает индикатор. Приоритет магнита выбирается с уровня 4 и отказывает на уровне 3.

- [ ] **Step 2: Запустить `test_rules`, ожидать падение**
- [ ] **Step 3: Перенести данные в `balance.json`**

Блок `upgrades` строго по таблице спецификации, `upgrade_prices` по лестнице, `uses` перенести и написать для новых ключей: по одной короткой строке на уровень. `specializations` сократить до `magnet` с `unlock_level: 4`. Удалить `rope_adjust_speed_units`, старые массивы, `PREP_PROFILES` и все связанные функции, блоки «Стиль восхождения» и «Цель сбора» в `build_supplies`.

- [ ] **Step 4: Реализовать модель и механику по блоку Interfaces**

`profile["upgrade_levels"]` становится словарём. Миграцию старых форматов пока упростить до значений по умолчанию, настоящий перенос делает задача 11. Двойной крюк сразу выбирается при покупке, `set_choice("hook", "1" или "2")` работает вне попытки. `base_kit()` читает `upgrades.rope.values[0]`, `upgrades.throw.values[0]`. Запечённые уровни не трогать: они обновятся в задаче 13.

- [ ] **Step 5: Запустить `test_rules`, `test_economy`, `test_progression`, `test_polish`, `test_hook`, `test_controls`, ожидать успех**

Падения `test_routes` и `test_levels` из-за базового снаряжения допустимы до задачи 13: зафиксировать их список в отчёте задачи.

### Task 11: Миграция сохранений v1–v6 в v7

**Files:**
- Modify: `game/scripts/game_model.gd:32-41`, `game_model.gd:113-114`, `game_model.gd:146-205`, `game_model.gd:221-234`
- Test: `game/tests/test_progression.gd`

**Interfaces:**
- Consumes: ключи из задачи 10.
- Produces: константы `V6_PRICES`, `V6_WEIGHTS`, `V6_HOOK_PRICES`, `V6_VALUES` со старыми таблицами; `_migrate_v6_levels(levels: Array) -> void`.

- [ ] **Step 1: Написать падающие проверки**

Заморозить из текущего `balance.json`: цены `[120,350,900,1900]`, веса `[1.0,1.05,1.0,1.1,0.9,0.95,1.0,1.0]`, крюки `[500,1200,2200]`.

```gdscript
var moved := load_fixture({"version":6,"gold":0,"upgrade_levels":[1,1,1,1,1,1,1,1]})
check(moved.level(GameModel.THROW)==2 and moved.level(GameModel.SLOWMO)==3 and moved.level(GameModel.REEL_OUT)==3 and moved.level(GameModel.SLOWMO_REST)==3,"free steps match the old feel")
check(moved.level(GameModel.ROPE)==1 and moved.level(GameModel.SWING)==1 and int(moved.profile["gold"])==0,"a fresh save owes and gets nothing")
var hooks := load_fixture({"version":6,"gold":0,"upgrade_levels":[1,1,4,1,1,1,1,1]})
check(hooks.level(GameModel.RADIUS)==5 and hooks.level(GameModel.DOUBLE)==2 and hooks.hook_count()==2,"two triple hooks stay")
var top := load_fixture({"version":6,"gold":0,"upgrade_levels":[5,5,4,5,5,5,5,4]})
check(top.level(GameModel.MAGNET)==5 and top.level(GameModel.RECOVERY)==5,"maximum stays maximum")
```

Отдельные проверки возврата: трек каната уровня 3 в v6 оплачен 470, новые цены 400, возврат 70. Второй `load_profile` уже мигрированного файла не меняет золото. Сохранения v1, v3, v4, v5 проходят всю цепочку без ошибок. Активная попытка с `length` больше нового максимума загружается, а `sim.length` не больше `rope_length()`.

- [ ] **Step 2: Запустить `test_progression`, ожидать падение**
- [ ] **Step 3: Реализовать**

`_migrate_levels` перевести на `V6_*`, чтобы v1–5 становились массивом v6. `_migrate_v6_levels` выбирает наибольший новый уровень, значение которого не лучше старого, и применяет таблицу миграции из спецификации. Возврат считать по старому треку. Новые треки денег не возвращают. Старый `upgrade_levels` массивом распознавать по типу.

- [ ] **Step 4: Запустить `test_progression`, `test_rules`, `test_integration`, ожидать успех**

### Task 12: Экран категорий

**Files:**
- Modify: `game/scripts/lobby_view.gd:1142-1244`, `game/scripts/ui_symbol.gd`, `game/scripts/game_hud.gd:1422-1430`
- Test: `game/tests/test_menus.gd`, `game/tests/test_responsive.gd`

**Interfaces:**
- Consumes: `GameModel.CATEGORIES`, `lock_reason`, `value_at`.
- Produces: `hud.equipment_category: String`, по умолчанию `movement`; `LobbyView.effect_text(key: String, at_level: int) -> String`; `hud.upgrade_flash: String`.

- [ ] **Step 1: Написать падающие проверки**

Пять сегментов «Движение», «Канат», «Крюк», «Сбор», «Выживание». В каждой категории три строки. Карточка броска показывает `12` и `→ 15`. Карточка точности без двойного крюка показывает причину вместо цены. У двойного крюка после покупки есть переключатель. У магнита ниже 4-го уровня приоритет закрыт с подписью. Выбранная категория сохраняется после покупки и перестройки страницы. Всё помещается в ширину и высоту 540×960 и 1080×660.

- [ ] **Step 2: Запустить, ожидать падение**
- [ ] **Step 3: Реализовать**

`build_upgrade(key, ...)` переиспользовать, расширив строками двойного крюка и приоритета. Новым ключам назначить символы `UiSymbol`: при нехватке добавить `swing`, `reel_in`, `reel_out`, `accuracy`. `recommended_upgrade` обходит `CATEGORIES`. Переключатель «Сборы» с плашкой «Скоро» оставить рядом с категориями.

- [ ] **Step 4: Запустить `test_menus`, `test_responsive`, ожидать успех**

## Этап 3. Уровни и проверка

### Task 13: Пересборка маршрутов

**Files:**
- Modify: `game/levels/**`
- Test: `game/tests/test_routes.gd`, `test_levels.gd`, `test_generation.gd`, `test_authored.gd`

- [ ] **Step 1: Прочитать заголовки `game/tools/bake_levels.gd` и `game/tools/design_levels.gd`, выяснить, хранит ли `layout.res` расчёт `exit_seconds`**
- [ ] **Step 2: Запечь уровни**

Run: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tools/bake_levels.gd` в фоне, потому что это дольше двух минут.
Expected: код выхода 0 для всех маршрутов.

- [ ] **Step 3: Запустить `test_routes`, `test_levels`, `test_authored`, `test_generation`**

Expected: успех. Если маршрут не проходит, запустить `design_levels.gd` для него. Если не помогает и это, остановиться и показать автору маршрут и причину: значения улучшений без согласия не менять.

- [ ] **Step 4: Снять скриншот каждого пересобранного уровня через `game/tools/level_shot.gd` и сравнить форму с прежними**

### Task 14: Документы и итоговая проверка

**Files:**
- Modify: `docs/DESIGN.md`, `README.md`, `tools/generate_rustore_cards.py` только если он читает старые ключи баланса

- [ ] **Step 1: Обновить `docs/DESIGN.md`: таблица улучшений, настройки. В `README.md` описать запуск `build_changelog.py` перед выпуском**
- [ ] **Step 2: Проверить остальные экраны на единый стиль**

Найти в `game/scripts` кнопки без `skin_button`, панели без `slab`, стандартные `HSlider`, `CheckBox`, `OptionButton`. Экраны паузы, результата, полного рюкзака и воскрешения перевести на `slab`, `action`, `segmented`. Expected: поиск по этим классам ничего не находит, `test_menus` и `test_responsive` проходят.

- [ ] **Step 3: Запустить все `game/tests/test_*.gd` по очереди**

Expected: каждый завершается с кодом 0.

- [ ] **Step 4: Снять скриншоты**

Run: запуск игры с `--capture=<путь>` и экранами `workshop`, `settings_graphics`, `settings_controls`, `settings_accessibility`, `settings_about` в портрете и ландшафте.
Expected: на всех снимках нет обрезанного текста и выхода за экран. Посмотреть каждый снимок.

- [ ] **Step 5: Запустить игру и вручную проверить ползунок, смену пресета, переназначение клавиши и покупку улучшения**

- [ ] **Step 6: Запустить `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tools/perf_bench.gd`, сравнить высокий пресет с прошлым прогоном**

Падение FPS на высоком пресете по умолчанию описать автору в итоговом отчёте.
