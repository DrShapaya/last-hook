# Карта визуального слоя горы (V0, чат 1)

Снято с commit `6b49cc2` (0.14.0). Визуал ничего не меняет в gameplay: коллизия героя, крюка и каната живёт в `MountainWorld` (`move_player`, `cast_hook`, `rope_contact`) и читает только `layout.anchors / obstacles / ledges` и `SolidGeometry`.

## Кто строит что

| Объект | Визуальный класс → метод | Коллизия | Источник материала |
|---|---|---|---|
| Поверхность горы, location 0 (v11+) | `MassifVisuals._build_skin` (фасеточная решётка поверх поля валунов `front_band`) | нет (только рисуется) | `zone_color` (палитра известняка по высоте) + `massif_rock.gdshader` |
| Боковые грани массива, location 0 | `MassifVisuals._build_flanks` | нет | `zone_color` + `rock_palette.cool` профиля, `flank_material` |
| Дальний фон, location 0 | `MassifVisuals.build_far_band` (+ параллакс в `MountainWorld._update_far_layers`) | нет | `zone_color`, unshaded far shader |
| Поверхность горы, location 1 и 2 (v4) | `LegacyMountainVisuals.build_chunk`: два плоских quad-обрыва по краям на z=-2 и коробки «пласт»/«дальний хребет» | нет | `rock_palette` профиля, `StandardMaterial3D` |
| Поверхность, старые генераторы location 0 (v<11) | `MountainVisuals.build_chunk` (сетка по `rock_field`) | нет | `zone_color`, vertex colour |
| Зацеп | `MountainVisuals.build_anchor` (+ таймер `MountainWorld._add_timer_dial`) | `anchor["polygon"]` / `dimensions` + grip tolerance в `MountainWorld.hit_object`; точка контакта прижимается к `anchor["surface"]` (рисованный контур) | `GripBiomeProfile.surface_material[kind]`, `stone_material` или глянцевый vertex-материал |
| Опасный блок (obstacle) | `MountainVisuals.build_obstacle` | `SolidGeometry.polygon(obstacle)` | `zone_color` + красно-бурые тона, `obstacle_material` |
| Площадка отдыха (ledge) | `MountainVisuals.build_ledge` | горизонталь `ledge.top` между `left..right` (+0.24) в `move_player` | `zone_color` + `rock_palette.warm` |
| Находка | `MountainWorld._build_find` → `LootVisuals.build`. На скальном массиве (`finds_without_pedestal()`) — без полки и постамента, только мягкая контактная тень; `_pedestal` остался для старых стилей | нет (подбор по расстоянию в `main.gd`) | собственные материалы лута |
| Трава / кристаллы / осыпь | `MassifVisuals._build_decor` → `_build_grass / _build_crystal / _build_pebbles`; в v<11 `MountainVisuals.build_chunk` | нет | `vegetation_set`, `crystal_set` профиля |
| Крупные landmark | `MassifVisuals._build_landmarks` → `LandmarkVisuals` | нет | собственные цвета по зоне |
| Флаг вершины | `MountainWorld.update_visibility` | нет | `mat("flag")` |
| Небо | `MountainWorld._build_sky` → `ProceduralSkyBackdrop` (**только location 0**) | нет | плоский градиент |

## Где хранятся параметры

- Глубина стены: `MountainVisuals.wall_depth()` — `MassifVisuals` берёт её из плоскостей фасет (`_depth`, диапазон `WALL_BACK..WALL_FRONT` = -2.2..1.95), `LegacyMountainVisuals` — константа `MOUNT_Z = 1.7`, базовый класс — синусоида.
- Нормаль, открытость неба, кривизна, точка опоры: `MountainVisuals.mount_at()` → `SurfaceMount`.
- Отступы от стены: `GRIP_STANDOFF / LEDGE_STANDOFF / OBSTACLE_STANDOFF` (0.30–0.32).
- Контуры, «юбки», гнёзда: `_contour`, `_skirt`, `_socket` в `MountainVisuals`.
- Кэш материалов: `MountainWorld.mat()` (по ключу) и `MountainWorld.shader()`; материалы живут вместе с миром.
- Тени: солнце и пресеты — `main.gd::_apply_shadow_preset` (battery без теней, energy ×3.2). Поверхность массива тени не отбрасывает; контактная тень в location 0 запечена в цвет кожи (`_occlusion`, `baked_contact()`), в остальных — decal `_contact_shade`.
- Качество: `MountainVisuals.quality` — бюджет декора (36/22/8), кристаллов (5/3/1), дальних слоёв (2/2/1), мелкие детали.

## Стриминг чанков

`MountainWorld.update_visibility` держит чанки 24 м в окне камеры ±32 м. Новый чанк: `visuals.build_chunk` (кожа, грани, декор, landmark), затем зацепы, опасные блоки, площадки, находки. `_release_chunk` обнуляет ссылки `visual` и делает `queue_free` узла: всё (меши, декали, ресурсы-меши) — дети узла чанка. Материалы кэшируются в `MountainWorld.materials` и переживают чанк (ограниченный набор ключей). Дальние полосы стримятся отдельно (`far_bands`). Смена качества пересоздаёт все чанки.

## Источник истины и дублирование

- Позиция объекта: только layout (`pos`, `polygon`, `dimensions`, `left/right/top`). Визуал не пишет в них ничего, кроме `visual`, `mount`, `surface` (рисованный контур, внутри полигона — проверяется тестом).
- Глубина поверхности: `wall_depth()` текущего визуального класса; зацеп, декор, находка и площадка берут её через `mount_at`, кроме находки (`_build_find` зовёт `wall_depth` напрямую и клампит z к 1.7..2.4) и разлёта осколков в `consume_anchor` (жёстко z=2.5).
- Дублирование: две реализации «поверхности» (`MassifVisuals` и `LegacyMountainVisuals`) с разным контрактом; в legacy поверхности на `MOUNT_Z` нет вообще — зацепы висят в небе между двумя обрывами. Контактная тень делается двумя способами (запечённая в location 0, decal в остальных).

## Скальные выступы-зацепы и лут без полок (0.15.x)

Камера ортографическая и смотрит строго по -Z (`main.gd::_position_camera`): глубина сама по себе не видна, читаются только силуэт и грани, повёрнутые к камере. Поэтому выступ строится так:

- `GripVisualSpec`: силуэт ~1.15–1.2 ширины хитбокса, верх на верхней кромке хитбокса, тело уходит вниз на 0.22–1.0 м (`_room_below` не пускает его на лут, соседние зацепы и площадки под ним). Верхняя кромка из 3–4 кусков, бока со ступенью, низ широкий и кривой. `front` — кольцо лицевой грани: радиальное сжатие к центру с разной силой по точкам + аффинная подгонка между верхней гранью (`top_band_height`) и подбрюшьем (`under_height`); `crosses()` гарантирует простые многоугольники.
- `MountainVisuals._block_mesh`: кольца «в скале → на стене → силуэт → кромка фронта» (`_zipper`), силуэт у верха и низа почти вровень со стеной, бока выдвинуты. Верхняя грань наклонена к камере (на ней краска), подбрюшье уходит в стену. Лицевая грань — Делоне по кромке, внутренним точкам и бороздам трещин; каждый камень между трещинами (`spec.cracks`) получает свою плоскость (вынос, поворот, наклон), поэтому камни по-разному ловят свет.
- `_block_frame`: наклон выступа по нормали хоста ограничен (вбок ≤0.3, вниз ≤0.18, вверх ≤0.06), иначе на склоне массы верх пропадал, а подбрюшье разворачивалось к камере.
- `_outcrop_lift` / `_stone_front`: если камень вокруг выступа стоит дальше вперёд, чем точка крепления, блок выносится на эту разницу (задняя часть удлиняется), фронт ≤ ~2.95 при герое на z 3.2. `MassifVisuals._seat` для зацепа покрывает и тело под хитбоксом.
- Краска (`_paint_band`) — сетка точек на реальной поверхности верхней грани (`_face_z` только по треугольникам под полосой); трещины и детали — `_face_strip` с предфильтром `_triangles_over`.
- Шов (`_contact_seam`) — тёмная щель только у низа и нижних боков; осколки подножия (`_grip_footing`) входят в тот же меш «Каменное гнездо», мох — в «Мох и снег в шве» (без лишних draw call). Battery: без осколков, мягкая `Контактная тень`.
- Лут: `MassifVisuals.front_band` больше не строит `find_shelf`; находка висит на лицевой грани с мягкой тенью (`LootVisuals._pedestal` → `finds_without_pedestal()`).
- Кадры: реальная игра `--capture=… --screen=play --seed=… --grip=… --size=720x1112 --quality=…`; фикстуры `tools/visual_fixture.gd --gameplay` и `tools/grip_closeup.gd [--near=x,y]` (фронт, ракурс, ракурс без зацепа).

## Найденные gap'ы (baseline)

1. Location 1 и 2: нет каменной поверхности за зацепами, нет неба (тёмный фон), обрывы — плоские quad без толщины.
2. Location 0: толщина массива почти не видна — камера ортографическая и смотрит строго по -Z, поэтому вертикальные боковые грани (`_build_flanks`, вынос 0.22 м) проецируются в линию. Нижних граней и нависаний как таковых нет.
3. Зацепы читаются как светлые плоские плиты; полоса статуса — отдельный прямоугольник над контуром.
4. Платформа: тонкий контур без видимой нижней грани и тени.
5. `consume_anchor`: осколки на фиксированной z=2.5, не связаны с глубиной гнезда.
