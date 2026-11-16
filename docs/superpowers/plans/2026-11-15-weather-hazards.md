# Погода: план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ветер, песчаная буря и метель становятся полосами погоды во всю ширину горы, с циклами, силой, мглой, холодом, кострами, HUD, звуком и вибрацией. Уровни не перепекаются.

**Architecture:** Новый `WeatherBands` вычисляет полосы из запечённого `ExpeditionLayout` (`spans`, `ledges`, `location`) и отвечает на вопросы «какая погода в точке и в момент времени». `MountainWorld` владеет им (`world.weather`), `main.gd` применяет силу к герою и крюку, `ColdMeter` хранит холод. Полноэкранный 2D-слой `WeatherOverlay` (CanvasLayer под HUD) рисует штрихи, частицы, мглу и иней. Старые `field`-опасности остаются в данных, но выключены.

**Tech Stack:** Godot 4.7.2, GDScript, gl_compatibility, headless-тесты `game/tests/test_*.gd` (SceneTree, `check()` + `failures`), звуки синтезирует `tools/make_sfx.py`.

**Spec:** `docs/superpowers/specs/2026-11-15-weather-hazards-design.md`

## Global Constraints

- Godot: `tools/godot/Godot_v4.7.2-stable_win64_console.exe`, проект `game/`. Тест: `$env:LASTHOOK_SAVE_DIR=<новая временная папка>; <godot> --headless --path game --script res://tests/test_weather.gd`. Каждый набор — со своей свежей папкой.
- Уровни не перепекаются, генератор (`expedition_layout.gd`, `mask_layout.gd`, дизайнеры) не меняется, `game/levels/**` не трогать.
- Полосы: акты с индексом 1 и 2. Акт 1: доли высоты акта 0.30–0.75, акт 2: 0.15–0.92. Мягкий край эффектов — 4 м.
- Вид по локации: 0 → `wind`, 1 → `sand_storm`, 2 → `blizzard`.
- Тюнинг (затишье / предупреждение / действие, с; сила — доля гравитации 14): ветер 6/2/6 ×0.35 и 6/2/9 ×0.5; буря 5/2.5/8 ×0.25 и 5/2.5/11 ×0.35; метель 6/2/8 ×0.3 и 5/2/11 ×0.4 (первое — акт 1, второе — акт 2).
- Порыв: нарастание 0.6 с, «дыхание» 0.8–1.15 от номинала, спад 0.8 с. В затишье и предупреждении силы нет.
- Холод: +1/16 в секунду в действии метели, +1/40 в предупреждении; −1/30 в затишье в полосе; на опоре −1/10 (в затишье −1/6); у костра ≤2.2 м −1/2.5; вне полосы −1/8. Множители: раскачка и подтяжка ×(1−0.35·c), бросок ×(1−0.25·c), ходьба ×(1−0.3·c). Длина каната и сроки жизни зацепов не меняются.
- Буря: прозрачный радиус 6.5 м; выше героя на ≥13 м — 0.9 непрозрачности, ниже героя максимум 0.6. Предупреждение 0→0.4, действие 1.0, спад после бури 3 с, при выходе из полосы 2 с. Метель: мгла максимум 0.45, радиус 7 м; иней = `cold`.
- Частицы на весь кадр: battery 40, balanced 90, high/ultra 160 (`settings["particles"]`: `reduced` → 40; иначе по пресету), × `amount_ratio` по силе.
- `reduce_effects` (`model.profile["settings"]["reduce_effects"]`): механика та же; нет тряски камеры, нет мигания кольца, частиц ×0.5, мгла и иней без пульсаций.
- Без `hint_screen_texture`. Пресет battery: костёр без OmniLight.
- Тексты по-русски (тосты: «Ветер сносит в полёте — прыгай в затишье», «Буря скрывает верх — держись ближних зацепов», «Холод замедляет — грейся у костра»).
- `main.gd` и `hazard_visuals.gd` содержат чужие незакоммиченные правки (освещение `_sun_shafts`, `_apply_graphics`, `_explorer_graphics`, `_front_of_grips`). Эти строки не трогать; новая логика — в новых файлах, в `main.gd` только короткие вызовы.
- Без коммитов: шаги «Commit» в этом плане заменены на «проверить `git diff --stat`, что тронуты только свои файлы» — владелец не просил коммитить.

## Review Focus

- **Возобновлённый забег посреди бури** — после `resume_run` погода и холод те же, что были (фаза от `hazard_clock`, холод из снимка). Тест в Task 4.
- **Бесконечный подъём** (`run_mode=="endless"`, акты идут по циклу) — полосы повторяются в каждом цикле, `band_at` не падает выше первого цикла. Тест в Task 1.
- **Старые сохранения / не-экспедиционные раскладки** (`LegacyMountainLayout`, `PracticeLayout`, пустые `spans`) — погоды нет, ничего не падает. Тест в Task 1.
- **Прицел под ветром** — подсказка `predict_shot` и реальный полёт крюка совпадают, когда ветер меняется во время полёта (ветер берётся в момент броска и держится весь полёт). Тест в Task 3.
- **Холод на временном зацепе** — бот проходит метельную полосу зимы на всех трёх маршрутах, в том числе через лёд и крошащиеся зацепы. Проверка в Task 5.

---

### Task 1: `WeatherBands` — полосы, фазы, сила

**Files:**
- Create: `game/scripts/weather_bands.gd`
- Create: `game/tests/test_weather.gd` (по образцу `tests/test_levels.gd`: `extends SceneTree`, `check()`, итоговая печать `WEATHER %d checks, %d failures`, `quit(1)` при ошибках)

**Interfaces:**
- Produces:
  - `class_name WeatherBands extends RefCounted`
  - `const KIND_BY_LOCATION := ["wind","sand_storm","blizzard"]`
  - `const TUNING := {kind: [act1_dict, act2_dict]}`, словарь: `{"from":float,"to":float,"calm":float,"telegraph":float,"active":float,"force":float}` (числа из Global Constraints)
  - `const EDGE := 4.0`, `const RAMP_IN := .6`, `const RAMP_OUT := .8`, `const GRAVITY := 14.0`
  - `func _init(source: MountainLayout) -> void`
  - `func enabled() -> bool` — false для не-`ExpeditionLayout` или пустых `spans`
  - `func band_at(y: float, margin: float = 0.0) -> Dictionary` — `{"kind","act","cycle","bottom","top","calm","telegraph","active","force","phase_shift","seed"}` или `{}`; для `y` выше первого цикла переносит акт по циклу, как `ExpeditionLayout.span()`
  - `func phase(band: Dictionary, time: float) -> Dictionary` — `{"name":"calm"|"telegraph"|"active","progress":float,"left":float,"gust":int}` (`gust` = номер цикла)
  - `func direction(band: Dictionary, gust: int) -> float` — ±1, детерминированно из `seed` и `gust`
  - `func strength(band: Dictionary, time: float) -> float` — 0..~1.15: огибающая порыва × дыхание, 0 вне действия
  - `func wind_at(point: Vector2, time: float) -> Vector2` — `Vector2(direction*force*GRAVITY*strength, 0)` внутри `[bottom, top]`, иначе ноль
  - `func presence(point: Vector2, time: float) -> Dictionary` — `{"kind":String,"amount":float,"phase":Dictionary,"direction":float,"inside":bool}`; `amount` = видимая сила 0..1 с краем `EDGE` (предупреждение — `progress*0.4`, действие — 1, затишье — 0); `{"kind":""}` вне полос с краем
  - `func calm_for(point: Vector2, time: float, need: float) -> bool` — true, если в точке нет полосы или сейчас затишье и до предупреждения ≥ `need`
  - `func campfires() -> Array[Vector2]` — для `blizzard`: середина верха каждой полки `role=="rest"`, чей `top` внутри `[bottom-2, top+2]` полосы; если в полосе нет ни одной — ближайшая к середине полосы полка любой роли. Для остальных видов пусто.

- [ ] **Step 1: Write the failing tests** в `test_weather.gd`, на запечённых раскладках всех 9 маршрутов (`LevelBake.apply` на `ExpeditionLayout`/`MaskLayout`, созданном как в `MountainWorld.setup` для `location`, `route` — или через `MountainWorld` с `visuals_enabled=false` и `LevelBake.find`):
  - `test_bands_per_location`: у каждого маршрута ровно 2 полосы в первом цикле, у полосы act 1 и act 2 нужные `kind`; для L0 r0 (spans 0-40/40-80/80-120) act 1 = `[52, 70]`, act 2 = `[86, 116.8]` с точностью 0.01.
  - `test_deterministic`: два `WeatherBands.new(layout)` дают равные `band_at`, `direction`, `strength` в 50 случайных (сид 7) точках/моментах.
  - `test_phase_cycle`: для полосы ветра act 2 при `time` с `phase_shift` → `calm` 6 с, `telegraph` 2 с, `active` 9 с; `left` убывает; `gust` растёт на 1 за цикл.
  - `test_wind_shape`: в `calm` и `telegraph` `wind_at` = 0; в середине действия `|wind_at.x|` между `0.8*force*14` и `1.15*force*14`; в первые 0.1 с действия меньше 0.3 номинала; `sign(wind_at.x)==direction(band,gust)`; вне полосы ноль.
  - `test_presence_edges`: в 2 м ниже `bottom` во время действия `amount` между 0 и 1, `inside==false`, `wind_at` ноль.
  - `test_endless_cycle`: `band_at(y + total)` (total = `spans[-1].y_end`) имеет `cycle==1` и ту же длину.
  - `test_no_weather_layouts`: `WeatherBands.new(LegacyMountainLayout.new())` и `PracticeLayout` → `enabled()==false`, `band_at(50)=={}`, `wind_at(...)==Vector2.ZERO`.
  - `test_campfires`: у каждого зимнего маршрута в каждой полосе ≥1 костёр; у лета и пустыни `campfires()` пуст.
- [ ] **Step 2: Run** `test_weather.gd` — Expected: FAIL (класс не найден).
- [ ] **Step 3: Implement `weather_bands.gd`.** Фаза: `t = fposmod(time + phase_shift, calm+telegraph+active)`, `gust = floor((time+phase_shift)/cycle)`. `phase_shift` — из `seed` в `[0, cycle)`. `seed` = `layout.seed_value*7919 + act*104729 + cycle*49979687 + location*86028121`. Дыхание: `0.975 + 0.175*sin(t*2.3 + seed%97)` (в пределах 0.8–1.15).
- [ ] **Step 4: Run** `test_weather.gd` — Expected: PASS.
- [ ] **Step 5:** `git diff --stat` — новые только два файла.

### Task 2: Выключить старые `field`-опасности

**Files:**
- Modify: `game/scripts/act_hazards.gd` (`step`, `calm_for`, `hint`)
- Modify: `game/scripts/hazard_visuals.gd` (`_build` — ветки `wind_pocket`/`sand_storm`/`storm_cycle`/`blizzard_gust`; не трогать `_front_of_grips` и `_build_cactus`)
- Test: `game/tests/test_weather.gd`

**Interfaces:**
- Produces: `ActHazards.step()` возвращает `force==Vector2.ZERO` и `haze==0.0` всегда; `ActHazards.calm_for` больше не смотрит на `field` (возвращает true, если нет других причин); `hint()` не выдаёт подсказок полей. `HazardVisuals` не строит узлы для `field`.

- [ ] **Step 1: Write the failing tests:**
  - `test_fields_inert`: для L1 r0 (есть `storm_cycle` на 98–109) `world.hazards.step(t, Vector2(0,103), false)["force"]==Vector2.ZERO` во всех фазах; `hint(Vector2(0,103), t)` не содержит «Буря».
  - `test_other_hazards_kept`: в L1 r0 `sand_bridge` ещё рушится (как в `tests/test_levels.gd`), в L2 r0 сосулька трескается при удержании её ветки (повторить существующую проверку `falling`), у кактуса есть `knock`.
  - `test_no_field_visuals`: мир L0 r0 с визуалами (`visuals_enabled=true`) после `build_near(60,-1,80)` не имеет узлов с маркерами «flag» от `wind_pocket` (в `hazard_visuals.built` нет id `field`-опасностей).
- [ ] **Step 2: Run** — Expected: FAIL на `test_fields_inert`.
- [ ] **Step 3: Implement:** в `ActHazards.step` пропускать `kind=="field"`; в `calm_for` — `continue` для всех `field`; в `hint` — пропускать `field`. В `HazardVisuals.build_near`/`_build` — не строить `field`. Комментарии в шапках обоих файлов обновить: погода теперь в `WeatherBands`.
- [ ] **Step 4: Run** `test_weather.gd`, `test_levels.gd`, `test_rules.gd`, `test_visuals.gd` — Expected: PASS. Если `test_levels.gd` проверял силу или дымку старых полей, такие проверки переносятся в `test_weather.gd` на полосы.
- [ ] **Step 5:** `git diff --stat`.

### Task 3: Ветер толкает героя и крюк, прицел это знает

**Files:**
- Modify: `game/scripts/hook_flight.gd`, `game/scripts/hook_volley.gd`
- Modify: `game/scripts/mountain_world.gd` (поле `weather`, создание рядом с `hazards = ActHazards.new(...)`, строка ~133)
- Modify: `game/scripts/main.gd` (`_physics_process` около строки 1698, `fire_hook`, `_shot_forecast_hero`/`_advance_forecast`, `_predict_single_shot`, `shot_window_open`, `direction_to_target`)
- Test: `game/tests/test_weather.gd`, `game/tests/test_hook.gd`

**Interfaces:**
- Consumes: `WeatherBands.wind_at(point, time)`.
- Produces:
  - `MountainWorld.weather: WeatherBands`
  - `HookFlight.wind: Vector2`; `func launch(origin, direction, speed, hero_velocity, wind: Vector2 = Vector2.ZERO)`; в `advance` ускорение `GRAVITY + wind`
  - `static func aim_solution(origin, target, speed, hero_velocity, wind: Vector2 = Vector2.ZERO) -> Dictionary` — тот же поиск, с ускорением `GRAVITY + wind`
  - `HookVolley.launch(..., wind: Vector2 = Vector2.ZERO)` передаёт ветер каждому `HookFlight`
  - `main.gd`: `func weather_wind() -> Vector2` = `world.weather.wind_at(sim.pos, hazard_clock)`, если есть `world.weather`, иначе ноль; ветер **берётся в момент броска и держится весь полёт** (и в прогнозе, и в реальном полёте)
  - `_advance_forecast(forecast, dt, wind := Vector2.ZERO)` добавляет `wind*dt` к скорости незаземлённого прогноза
  - в `_physics_process`: `if not sim.grounded: sim.vel += weather_wind()*step` (сразу после `step_hazards`)

- [ ] **Step 1: Write the failing tests:**
  - `test_hook_wind_flight` (`test_hook.gd`): `HookFlight` с `wind=Vector2(7,0)` за 0.4 с уходит по x на `0.5*7*0.16 ±0.01` дальше, чем без ветра.
  - `test_aim_with_wind`: `aim_solution(o, t, speed, v, Vector2(7,0))` + симуляция `advance` по `STEP` попадает в `t` с ошибкой < 0.05.
  - `test_forecast_matches_flight` (`test_weather.gd`): в L0 r0 поставить героя на зацеп в полосе act 2, `hazard_clock` в середине действия; `predict_shot(dir)["contact"]` совпадает с точкой реального зацепа после `fire_hook(dir)` и прогона `_physics_process` (≤0.05 м). Отдельный случай: бросок за 0.2 с до конца действия.
  - `test_hero_pushed_airborne`: герой в воздухе в полосе в действии через 0.5 с смещён по x в сторону `direction` больше, чем тот же прогон с `world.weather=null`; на опоре (`sim.grounded`) смещения нет.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** по Interfaces. Все вызовы `HookFlight.launch`, `hook_volley.launch` и `aim_solution` в `main.gd` получают ветер из `weather_wind()` в момент броска. `RouteBot.stays_in_reach` в Task 5.
- [ ] **Step 4: Run** `test_weather.gd`, `test_hook.gd`, `test_controls.gd`, `test_gameplay_foundation.gd` — Expected: PASS.
- [ ] **Step 5:** `git diff --stat`. Свои строки в `main.gd` не пересекаются с чужими блоками освещения.

### Task 4: Холод и костры (механика)

**Files:**
- Create: `game/scripts/cold_meter.gd`
- Modify: `game/scripts/main.gd` (`_configure_movement`/`_configure_rope` запоминают базовые значения; `_physics_process`; `walk_velocity`; новая `throw_speed()`; `start_run` сбрасывает; снимок `save_snapshot` ~2601 и `resume_run` ~1060)
- Test: `game/tests/test_weather.gd`

**Interfaces:**
- Consumes: `WeatherBands.presence`, `WeatherBands.campfires`.
- Produces:
  - `class_name ColdMeter extends RefCounted`; `var cold := 0.0`
  - `func step(dt: float, presence: Dictionary, grounded: bool, near_fire: bool) -> void` (скорости из Global Constraints; только при `presence.kind=="blizzard"` растёт; clamp 0..1)
  - `func swing_scale() -> float`, `func reel_scale() -> float`, `func throw_scale() -> float`, `func walk_scale() -> float`
  - `main.gd`: `var cold := ColdMeter.new()`; `func throw_speed() -> float` = `model.throw_speed()*cold.throw_scale()` — заменить им все `model.throw_speed()` в `main.gd` и `scripts/route_bot.gd`; в каждом шаге `sim.swing_force = base_swing*cold.swing_scale()`, `sim.reel_in_speed/out = base*cold.reel_scale()`; цель скорости ходьбы ×`walk_scale()`
  - `main.gd`: `func near_campfire() -> bool` — `sim.pos` в 2.2 м от любой точки `world.weather.campfires()`
  - снимок: ключ `"cold"`; `resume_run` восстанавливает `cold.cold = float(snapshot.get("cold",0))`

- [ ] **Step 1: Write the failing tests:**
  - `test_cold_rates`: `ColdMeter` 16 с с presence метели в действии (`inside=true`) → `cold≈1.0` (±0.02); затем 2.5 с с `near_fire=true` → `cold≈0`; с 0.5 на опоре в затишье 3 с → `0.5-3/6`; вне полосы (`kind==""`) 4 с → `0.5-0.5`.
  - `test_cold_only_blizzard`: presence `wind` или `sand_storm` в действии не повышает `cold`.
  - `test_cold_slows`: при `cold=1` `swing_scale()==0.65`, `throw_scale()==0.75`, `walk_scale()==0.7`; `game.sim.maximum_length` не меняется.
  - `test_cold_snapshot`: игра L2 r0, `cold.cold=.6`, `save_snapshot()`, новая игра, `resume_run()` → `cold.cold==.6` и тот же `hazard_clock`, `world.weather.phase(...)` той же фазы.
  - `test_cold_reset`: `start_run` обнуляет холод.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** по Interfaces. Шаг холода в `_physics_process` рядом с вызовом ветра: `cold.step(step, world.weather.presence(sim.pos,hazard_clock), sim.grounded, near_campfire())`.
- [ ] **Step 4: Run** `test_weather.gd`, `test_controls.gd`, `test_progression.gd`, `test_integration.gd` — Expected: PASS.
- [ ] **Step 5:** `git diff --stat`.

### Task 5: Боты проходят все 9 маршрутов

**Files:**
- Modify: `game/scripts/route_bot.gd` (`climb_route`, `stays_in_reach`)
- Modify: `game/tests/test_levels.gd` (`traverse`, строка ~69: `calm_for`)
- Modify (если там свой бот): `game/tools/hero_run_capture.gd`

**Interfaces:**
- Consumes: `WeatherBands.calm_for`, `main.weather_wind()`, `main.throw_speed()`.
- Produces: бот ждёт на постоянном зацепе (`permanent==true`), пока `world.weather.calm_for(hero, clock, 2.0)` и `calm_for(target, clock, 2.0)` ложны; на временном зацепе не ждёт. `stays_in_reach` учитывает ветер: `later += 0.5*wind*t²`. Лимит кадров на зацеп — 1200 + время ожидания (до 20 с = 2400 кадров).

- [ ] **Step 1: Run baseline** для всех 9: `<godot> --headless --path game --script res://tools/climb_level.gd -- L:R` для L 0..2, R 0..2 (в фоне, по одному на процесс). Записать, какие падают после Task 3–4.
- [ ] **Step 2: Implement** ожидание и учёт ветра в `RouteBot` и `test_levels.traverse` (заменить `world.hazards.calm_for` на `world.hazards.calm_for(...) and world.weather.calm_for(...)`).
- [ ] **Step 3: Run** все 9 `climb_level.gd` — Expected: `success=true` у всех 9. Если маршрут падает: `superpowers:systematic-debugging` → сначала снижать числа в `WeatherBands.TUNING` (сила, длина действия) или холод, **не** уровни и не правила зацепов. Итоговые числа записать в спецификацию (таблица тюнинга) и в Global Constraints этого плана.
- [ ] **Step 4: Run** `test_levels.gd`, `test_routes.gd`, `test_authored.gd` — Expected: PASS.
- [ ] **Step 5:** `git diff --stat`.

### Task 6: Полноэкранный слой погоды и костры (визуал)

**Files:**
- Create: `game/scripts/weather_overlay.gd`
- Create: `game/scripts/campfire_visuals.gd`
- Modify: `game/scripts/main.gd` (создать слой в `_ready` рядом с HUD, обновлять в `_process` / после `_move_camera`; тряска камеры)
- Modify: `game/scripts/mountain_world.gd` (костры строятся при построении чанков, как `hazard_visuals.build_near`; освобождаются вместе с ними)
- Test: `game/tests/test_weather.gd`

**Interfaces:**
- Consumes: `WeatherBands.presence`, `WeatherBands.campfires`, `ColdMeter.cold`, `camera.unproject_position`.
- Produces:
  - `class_name WeatherOverlay extends CanvasLayer` (слой ниже HUD; номер взять у HUD минус 1)
  - `func configure(particles: String, preset: String, reduce_effects: bool) -> void`
  - `func update(presence: Dictionary, cold: float, hero_screen: Vector2, metres_per_pixel: float, delta: float) -> void`
  - дочерние узлы: `Штрихи` (ColorRect с canvas_item-шейдером процедурных полос по направлению ветра), `Частицы` (`GPUParticles2D` во весь кадр: листья / песчинки / снежинки, `amount` по Global Constraints, `amount_ratio` = `presence.amount`), `Мгла` (ColorRect: радиус и плотность из Global Constraints, считаются в метрах через `hero_screen` и `metres_per_pixel`; сверху плотнее), `Иней` (ColorRect: виньетка из кристаллов, толщина = `cold`)
  - `func particle_amount() -> int`, `func haze_strength() -> float`, `func shake() -> float` (0 при `reduce_effects`) — для тестов
  - `class_name CampfireVisuals`: `static func build(parent: Node3D, at: Vector2, z: float, with_light: bool) -> Node3D` — поленья, 2–3 карточки огня с анимированным шейдером, искры; `with_light=false` на battery
  - канат (`game/scripts/explorer_view.gd`, отрисовка ~300–330): средние точки каждого прямого отрезка смещаются по направлению ветра на `0.08*длина_отрезка*amount` (только визуально; `main.gd` передаёт вид `presence` в `explorer_view`)
  - растительность: в загруженных чанках у `ShaderMaterial` с параметрами `sway` и `wind` ставить `wind = 1.0 + 3.0*amount` (только при смене больше чем на 0.05); флаги из `act_props.gd`/`landmark_visuals.gd` (узлы «Полотно») хлопают сильнее (амплитуда ×(1+2·amount))
- Мгла/частицы/штрихи для вида: ветер — штрихи + листья, без мглы; буря — песчинки + мгла (тёплая, `Color(.85,.68,.45)`); метель — снежинки + белая мгла + иней.

- [ ] **Step 1: Write the failing tests:**
  - `test_overlay_amounts`: `configure("full","high",false)` → `particle_amount()==160`; `("reduced","battery",false)` → 40; `("full","balanced",true)` → 45.
  - `test_overlay_haze`: буря в действии → `haze_strength()==1.0` (с плавным нарастанием за ≤3 с update по 1/60); ветер → 0; метель → ≤0.45; затишье после бури за 3 с спадает ниже 0.05.
  - `test_overlay_reduce`: при `reduce_effects` `shake()==0` в пике порыва, а без него `>0`.
  - `test_campfire_built`: мир L2 r0 с визуалами после построения вида около первой зимней полосы содержит узел костра в ≤0.5 м от `campfires()[0]`; на battery без `OmniLight3D`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** по Interfaces (`godot-shaders`, `performance-optimization`: один ColorRect на эффект, без чтения экранной текстуры).
- [ ] **Step 4: Run** `test_weather.gd`, `test_visuals.gd`, `test_responsive.gd`, `test_polish.gd` — Expected: PASS.
- [ ] **Step 5: Measure:** `game/tools/flow_profile.gd` на battery, balanced, high в полосе бури и метели; рост времени кадра записать в заметки (цель на battery ≤ +1.5 мс). `git diff --stat`.

### Task 7: HUD — значок погоды, шкала холода, подсказки

**Files:**
- Modify: `game/scripts/play_gauges.gd` (новые классы `WeatherChip`, `ColdGauge`)
- Modify: `game/scripts/game_hud.gd` (создание рядом с `rope_gauge` ~1055, обновление в `update_play` ~1391)
- Modify: `game/scripts/main.gd` (тосты первого входа)
- Test: `game/tests/test_weather.gd`, `game/tests/test_ui_flow.gd`

**Interfaces:**
- Consumes: `WeatherBands.presence`, `WeatherBands.band_at(y, 6.0)`, `ColdMeter.cold`, `GameHud.effects_reduced()`.
- Produces:
  - `PlayGauges.WeatherChip extends Control`: `kind: String`, `direction: float`, `phase_name: String`, `ring: float` (0..1), `blink: bool`; рисует иконку вида, стрелку и кольцо
  - `PlayGauges.ColdGauge extends Control`: `value: float`
  - `GameHud.weather_chip`, `GameHud.cold_gauge`; чип виден, если `band_at(hero.y, 6.0)` не пуст; кольцо: в затишье — показывается за 4 с до предупреждения (`1 - left/4`), в предупреждении — `progress`, в действии — `1 - progress`; `blink = phase=="telegraph" and not effects_reduced()`; шкала видна при `kind=="blizzard"` в полосе или `cold>0.01`
  - `main.gd`: `var weather_seen: Dictionary` (на забег); при первом `presence.inside` для вида — `toast(<текст из Global Constraints>, 3.0, "hazard")`

- [ ] **Step 1: Write the failing tests:**
  - `test_hud_chip`: игра L0 r0, герой в полосе act 2 в затишье за 3 с до предупреждения → `weather_chip.visible`, `ring≈0.25`; в действии `direction` чипа = `direction(band,gust)`; вне полос и далее 6 м → не виден.
  - `test_hud_cold`: L2 r0, `cold.cold=.5` → `cold_gauge.visible` и `value==.5`; L0 → не виден.
  - `test_first_toast`: первый вход в полосу ветра даёт тост «Ветер сносит в полёте — прыгай в затишье», второй вход за тот же забег — нет.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** в стиле существующих датчиков (`RopeGauge`, `MenuSurface` цвета, шрифты HUD), учесть `text_scale` и безопасные зоны, как соседние элементы.
- [ ] **Step 4: Run** `test_weather.gd`, `test_ui_flow.gd`, `test_responsive.gd`, `test_menus.gd` — Expected: PASS.
- [ ] **Step 5:** `git diff --stat`.

### Task 8: Звук, вибрация, тряска

**Files:**
- Modify: `tools/make_sfx.py` (новые: петли `weather_wind_1`, `weather_sand_1`, `weather_blizzard_1`, `campfire_1`; разовый `gust_1`)
- Create (генерацией): `game/assets/sfx/weather_wind_1.wav`, `weather_sand_1.wav`, `weather_blizzard_1.wav`, `campfire_1.wav`, `gust_1.wav`
- Modify: `game/scripts/sound_bank.gd` (`SOUNDS["gust"]`; канал петли погоды и костра)
- Modify: `game/scripts/haptics.gd` (`PATTERNS["weather_warn"] = [[0,25,.3]]`, `PATTERNS["weather_hit"] = [[0,45,.55]]`)
- Modify: `game/scripts/main.gd` (вызовы при смене фазы; рядом с `sounds.set_wind(...)` ~2764)
- Test: `game/tests/test_audio.gd`, `game/tests/test_weather.gd`

**Interfaces:**
- Produces:
  - `SoundBank.set_weather(kind: String, level: float) -> void` — своя петля `weather_<wind|sand|blizzard>_1`, громкость `lerp(-50, -12, sqrt(level))` дБ, высота `1 + 0.15*level`, плавные нарастание/спад как у `set_wind`
  - `SoundBank.set_campfire(level: float) -> void`
  - `main.gd`: при переходе фазы `calm→telegraph` внутри полосы — `_haptic("weather_warn")`; `telegraph→active` — `_sfx("gust")` и `_haptic("weather_hit")`; уровень петли = `presence.amount * (0.35 + 0.65*strength/1.15)`

- [ ] **Step 1: Write the failing tests:**
  - `test_audio.gd`: все новые файлы существуют и грузятся; `SOUNDS` содержит `gust`.
  - `test_weather.gd` `test_phase_feedback`: игра L0 r0, проход через смену фаз в полосе — ровно одно `weather_warn` и одно `weather_hit` (через счётчик `haptics.pulses` или перехват `_haptic`) за цикл; вне полосы — ни одного.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement:** синтез в `make_sfx.py` (ветер — фильтрованный шум с медленной АМ; песок — более высокий шелестящий шум; метель — вой с узкой полосой; костёр — треск-импульсы на тихом шуме; порыв — нарастающий свист 0.8 с). Запустить `python tools/make_sfx.py`; убедиться, что существующие wav не изменились (`git diff --stat game/assets/sfx`); если генератор перезаписывает старые файлы с другими байтами, генерировать только новые.
- [ ] **Step 4: Run** `test_audio.gd`, `test_weather.gd` — Expected: PASS.
- [ ] **Step 5:** `git diff --stat`.

### Task 9: Проверка вживую и все тесты

**Files:** только заметки в `C:\Users\isaev\AppData\Local\Claude-Data\claude_pzs8sxrjxfjjc\side-session-notes\local_3437784b-dcd2-4bbe-9756-69c4aa9f2601\weather.md`; кадры и клипы — в `docs/weather/` (в репозитории, для владельца).

- [ ] **Step 1:** Все наборы `game/tests/test_*.gd` (сейчас 30, плюс новый `test_weather.gd`), каждый со своим свежим `LASTHOOK_SAVE_DIR` — Expected: у каждого 0 failures.
- [ ] **Step 2:** Все 9 `climb_level.gd` — Expected: `success=true`.
- [ ] **Step 3:** Записи настоящих забегов в 1080×2340 через `tools/hero_run_capture.gd` с `set_route_choice`: лето r0 акт 3 (порыв со сносом крюка), пустыня r0 акт 3 (мгла сверху), зима r0 акт 3 (холод растёт, иней, костёр греет). Ленты кадров `docs/weather/wind_strip.png`, `sand_strip.png`, `blizzard_strip.png` плюс кадр с `reduce_effects`.
- [ ] **Step 4:** `flow_profile.gd` на battery/balanced/high — числа в заметку.
- [ ] **Step 5:** Показать владельцу по-русски кадры и цифры. Ничего не коммитить.
