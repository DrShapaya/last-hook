# Аудит Last Hook — 24 октября 2026

## Объём и методика

Проверены Godot 4.7.2, `project.godot`, экспорт Windows/Android, 47 GDScript-скриптов, 3 сцены, генераторы маршрутов, физика, HUD, сохранения, реклама, шейдеры, ассеты, документация и 19 headless-наборов тестов. Запущены:

- `check_godot_project.py`: 181 файл, 0 ошибок, 0 предупреждений;
- Windows export без тестов: успешно;
- 19 test scripts: 15 проходят, `test_economy` и `test_polish` падают, `test_progression` останавливается на runtime error без `quit()`, `test_integration` проходит за 63,9 с, `test_levels` за 83,6 с;
- Android pipeline: не завершён на сборке Gradle/LastHookAds; причина — daemon/network/cache, см. ниже.

## P0/P1 — исправить до следующей сборки

### 1. Release gate красный: тесты уже не соответствуют текущему поведению

`tools/build.ps1` запускает наборы последовательно, но текущая ветка не проходит полный прогон.

- `game/tests/test_economy.gd:255-265`: 2 провала. Код в `main.gd:1452-1489` после последнего коммита автоматически заменяет самый дешёвый предмет более дорогой находкой. Тест и UI-контракт всё ещё ожидают окно сравнения и ручное подтверждение. Сейчас фактическое поведение и тесты противоречат друг другу.
- `game/tests/test_progression.gd:104`: `game.explorer` равен `null`, потому что `_ready()` создаёт preview-мир с `menu_preview=true`, а `main.gd:484-489` намеренно не создаёт `ExplorerView`. Runtime error прерывает `run_tests`, а процесс не вызывает `quit()` и зависает. Это блокирует `build.ps1` на неопределённое время.
- `game/tests/test_polish.gd:341,369`: 2 провала — после свайпа не устанавливается ожидаемый focus на вкладку, и проверка locked route не совпадает с текущей логикой карточки/кнопки.

Исправление: выбрать один контракт полного рюкзака (ручное сравнение либо автоматическая замена), синхронно обновить код/HUD/тесты; либо создать preview-персонажа, либо переписать progression-тест на проверку нового preview-контракта. Для каждого test process добавить timeout и принудительный `quit(1)` при runtime error.

### 2. Восстановление после sand bridge оставляет выход скрытым

`MountainWorld._collapse_bridge()` снимает `hidden` с раскрытой опоры (`mountain_world.gd:783-790`), но `restore_hazards()` (`mountain_world.gd:792-800`) при загрузке восстанавливает только collapsed ledge и визуал hazard. После перезапуска `reveal` остаётся `broken=false, hidden=true`.

Последствия: выход виден и физически доступен, но его не показывают beacon/booster и он исключён из `reachable_exits()` (`main.gd:1528-1535`). Нужно централизовать `restore` состояния hazard и добавить проверку `hidden=false` в `test_levels`.

### 3. Android Back не обработан на экране revive

`main.gd:1841-1854` содержит ветви `play`, `pause`, `result`, `menu`, но не `revive`. Esc на ПК попадает в общий fallback и вызывает `show_menu()`, а Android Back с `quit_on_go_back=false` ничего не делает. Добавить явную ветку `"revive": show_menu()` и тест на Android-путь.

### 4. Android export не является воспроизводимым из чистого окружения

`tools/prepare_android_ads.ps1` пересобирает `LastHookAds.aar`, когда Java-исходник новее бинарника. В текущем checkout это так. Сборка упирается в Gradle daemon/loopback, а в чистом `GRADLE_USER_HOME` wrapper требует скачать Gradle 8.11.1 с `services.gradle.org`; сетевой доступ отсутствует.

Проблема процесса: бинарный AAR лежит в Git, но его актуальность определяется временем файла; чистый CI всё равно требует Gradle/network. Нужны pinned/cached Gradle distribution, офлайн CI cache или заранее собранный reproducible plugin artifact с проверкой версии/sha. Добавить отдельный smoke export Android в CI.

## P2 — серьёзные дефекты и технический долг

### 5. `main.gd` — God object и дублирование состояния

`main.gd` — 2121 строка и около сотни полей: ввод, камера, физика, три представления полёта крюка, slow motion, hazards, inventory, ads, save/resume, HUD и capture tooling. Сбросы состояния вручную дублируются в `start_run`, `resume_run`, `fail_run`, `_return_to_safety`, `finish_run`, `show_menu`.

Это уже стало причиной рассинхронизации в прошлых версиях и упрощает появление новых багов. Выделить `HookController` с единым state machine/reset, `RunState/SaveService`, `CameraController` и `InputController`; оставить `main` координатором.

### 6. Проверка маршрута доказывает геометрию, а не игру человеком

`RouteGraph` проверяет расстояние, направление и препятствия между центрами опор. Интеграционный bot в `test_integration.gd:486-545` знает `main_route`, выбирает точное направление, напрямую меняет длину каната и тикает ровно по 1/120 с. Лог `LEVELS_STUCK` уже показывает восстановление на сложном маршруте, хотя итоговый тест остаётся зелёным.

Нужен второй «честный» bot: только видимые опоры, задержка реакции 250–400 мс, квантование угла и реальные `pointer_down/move/up`; генератор должен проверять базовый комплект через такой же переход.

### 7. Бесконечный режим не ограничивает рост данных

В endless `anchors`, `finds`, `obstacles`, `ledges` и visual metadata растут бесконечно. `main.gd:_collect_finds`, `MountainWorld._update_dynamic_visibility` и обновление цен перебирают полные массивы каждый кадр. При длинной сессии это превращается в линейную работу на 120 Гц и удерживает память.

Индексировать находки/объекты по чанкам, удалять данные ниже камеры после сохранения минимального snapshot, оставить ring buffer для истории и ограничить число активных визуальных чанков.

### 8. Генерация визуала синхронно блокирует старт и создаёт много Node/Mesh

`MountainWorld.generate_to()` вызывает `update_visibility()` без budget; в `update_visibility()` это означает `effective_budget = missing_keys.size()`, поэтому при старте строятся все отсутствующие чанки сразу. При обычном кадре budget=1, но генерация уровня всё равно может дать длинный main-thread spike на Android.

`MassifVisuals`, `MountainVisuals`, `LandmarkVisuals`, `LootVisuals` создают много отдельных `MeshInstance3D`, `SurfaceTool`, материалов и мешей. Нужны профилирование на устройстве, асинхронное/поштучное построение чанков, кэш общих Mesh/Material и MultiMesh для повторяющихся декораций.

### 9. Gameplay loop работает на 120 Гц с лишней аллокацией

`main.gd:_physics_process()` одновременно обновляет input, aim, hazards, rope path, movement, projectile, loot collection, progression и save timers. Внутри часто создаются Dictionary/Array и выполняются `nearby_*()` с новыми массивами. 120 Гц оправдано для rope physics, но UI, цены, beacon, dynamic visibility и часть hazards можно обновлять на 30–60 Гц.

Разделить fixed physics и presentation tick; кэшировать nearby ranges; обновлять HUD/цены по dirty flags.

### 10. Предсказание выстрела и запись сохранения остаются дорогими

`predict_shot()` (`main.gd:948-1010`) делает до 240 шагов с collision checks на каждый крюк. Частота уже снижена, но на слабом Android это всё ещё значимая доля кадра. `save_snapshot()` выполняет синхронный JSON flush и два rename; снимки идут каждые 3 секунды и при отдельных событиях. Все вызовы `model.save()` игнорируют `bool` результата.

Нужны budget/p95 профилирование на реальном Android, dirty-save coalescing, очередь записи вне gameplay frame и UI-ошибка при `save_error`.

### 11. Аудио генерируется в GDScript на каждый звук и обрывается одним player

В проекте нет audio assets. `main.gd:2058-2121` создаёт `AudioStreamWAV` и массив сэмплов на каждое событие; почти все эффекты идут через один `AudioStreamPlayer`, поэтому новый звук обрывает предыдущий. Кэшировать streams при старте, использовать пул players и AudioBus для SFX/music/ducking.

### 12. Сохранения недостаточно защищены от будущей версии и повреждённых типов

`GameModel.load_profile()` принимает только версии 1–6; более новый профиль молча заменяется свежим и при следующем `save()` может быть перезаписан старой сборкой. В `active` поля `picked/broken/active_reserves/bag` предполагаются правильных типов; повреждённый JSON может вызвать runtime error до восстановления `.bak`.

При future version нужно блокировать запись и показывать миграционное сообщение; для active snapshot — строгая schema validation и отказ от частично некорректного файла.

## P3 — UX, визуал, документация и процесс

### 13. Тост управления перекрывает revive

`start_run()` показывает controls toast на 4 секунды (`main.gd:552-553`), а `fail_run()`/`show_revive()` его не отменяют. При раннем падении подсказка управления накладывается на экран возрождения. Очищать контекст `controls` при переходе в revive/result.

### 14. Полный рюкзак и UI-логика расходятся

`GameHud.show_swap()` теперь compatibility stub (`game_hud.gd:804-810`), `bag_full_chip` всегда скрыт (`game_hud.gd:1037`), а старые поля `swap_offer/swap_panel` продолжают жить в `main`. Нужно удалить мёртвую ветку либо вернуть полноценный ручной swap; сейчас UX не объясняет, почему предмет исчезает/заменяется.

### 15. Focus navigation после свайпа сломана

`GameHud.button()` создаёт кнопки с `FOCUS_NONE` (`game_hud.gd:428-435`), а `LobbyView.animate_entry()` включает focus только для отложенной цели. Тест polish фиксирует, что после свайпа ожидаемая вкладка не получает focus. Исправить единый focus policy для клавиатуры/gamepad/touch и проверять его после rebuild меню.

### 16. Legacy и новый pipeline сосуществуют слишком долго

`MountainWorld` выбирает `ExpeditionLayout/MassifVisuals` для новых попыток, но сохраняет `LegacyMountainLayout`, `MountainLayout`, `MountainVisuals`, `LegacyMountainVisuals` и многочисленные ветви совместимости. Это удваивает визуальные контракты и повышает стоимость каждого изменения. Оставить legacy только в отдельном versioned adapter для старых save; новые уровни перевести на один typed API.

### 17. Единицы и баланс требуют плейтеста

`balance.json` сам помечен `human_calibration_required`. Модель использует `meters_per_unit=10`, поэтому рядом с героем длина каната 55–88 м и скорость крюка 160–310 м/с выглядят несогласованно. Нужны реальные сессии, telemetry по долям монет/предметов/стоимости rescue и отдельная шкала UI.

### 18. Визуальные проблемы из предыдущего аудита остаются актуальны

- зацепы читаются как плоские широкие плиты, а не как объёмные глыбы;
- тени героя и каната слабо читаются на стене;
- полки под находками и плотные дуги монет конкурируют с основными зацепами;
- фасетный rock shader местами пересвечивает верхние грани;
- дальний фон остаётся плоским, герой мал относительно кадра.

Это не тестируется headless; нужен acceptance-лист кадров на Windows и реальном Android в трёх quality presets.

### 19. Версии и документация снова расходятся

Код/проект/export уже `0.15.3`, но `00_README.md` и `07_prototype_status.md` всё ещё называют `0.15.1`. README описывает изменения 0.14 и старые v13/v14. `AUDIT_LAST_HOOK.md` содержит ссылки и выводы от 22 октября, которые уже не совпадают с текущим кодом (например, старые номера версий и статус `economy_probe.py`). В `game/assets/art/generation-prompts.md` и `references/location-layouts-v2/README.md` остаются ссылки на удалённый `references/target-look-v2.png`.

Сделать `project.godot` единственным источником версии, обновлять README/release notes скриптом и добавить consistency check в build.

### 20. Release script меняет файлы до успешной сборки

`tools/release.ps1:56-69` записывает версию и Android `version/code`, затем запускает build. При провале теста/Gradle рабочее дерево остаётся изменённым, а повторный запуск может создать пропуск version code. Сначала собирать во временной копии/проверять тесты, затем коммитить version bump; добавить rollback в `finally`.

### 21. Нет CI и реального Android smoke test

В репозитории нет `.github/workflows`/другого CI. Headless tests запускаются только вручную PowerShell-скриптом; нет таймаутов, artifact upload, Android install/launch, проверки APK ABI/подписи и теста поведения Back/ads/touch на устройстве. Минимум: Windows headless, Android export, test report, timeout на каждый test и nightly device smoke.

### 22. Practice оставляет отдельные профили

`start_practice()` создаёт `profile-practice.json`; очистки после выхода нет. После серии тренировок папка сохранений накапливает мусор. Practice должен быть in-memory или иметь явный cleanup.

## Рекомендуемый порядок работ

1. Исправить release gate: economy contract, progression null/hang, polish focus/locked route, timeout в `build.ps1`.
2. Исправить save/resume: hidden reveal, Android Back revive, future/corrupt profile validation, проверку `save()`.
3. Разделить `main.gd` и унифицировать hook/run state.
4. Ввести честный bot и route audit на реальном input.
5. Профилировать Android: startup chunk build, aim preview, 120 Hz loop, save stalls, memory in endless.
6. Починить Gradle/Android reproducibility и добавить CI/smoke.
7. Обновить версии/документацию, затем делать визуальный и экономический acceptance на устройстве.
