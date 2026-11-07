# Промпты для среза героя (этап 2)

Сейчас риг рисуется на заглушках из `game/assets/hero/placeholder/` (`tools/hero_placeholders.py`). Они проверяют технику: сгиб, стыки, тени и слои. По ним не оценивают красоту. Настоящие детали кладутся в `game/assets/hero/pioneer/` под теми же именами и в тех же размерах холста. Риг возьмёт их сам, код менять не нужно.

Порядок работы:
1. Сначала эталон героя (п. 1). Это общий референс стиля, масштаба и света для всех деталей.
2. Затем детали по одной, каждая с эталоном как входным референсом **стиля** (не как картинкой для правки).
3. Генерировать квадрат 1024×1024 или крупнее. Деталь занимает центр, вокруг прозрачные поля. Затем деталь подгоняется под свой холст так, чтобы точки суставов попали в пиксели из таблицы. Это делает следующий шаг конвейера (этап 8) или вручную.

Общие правила (повторяются в каждом промпте): тот же стиль, что у нынешнего героя `explorer-whole-v3.png` (мягкий детальный стилизованный 3D-рендер, ткань и кожа с фактурой); свет мягкий сверху-слева; **нет теней от соседних деталей** (их рисует риг); контур одной толщины; прозрачный фон; без текста и подписей.

## 1. Эталон героя

Use case: character reference sheet. Asset type: neutral reference pose for a cut-out bone rig. Use the attached image ONLY as identity and style reference (yellow cube-headed explorer, green jacket, brown leather backpack, dark pants, brown boots). Generate ONE character, full body, strict side view looking right, standing straight, arms hanging slightly forward and away from the body so they do not cover the torso, legs straight and slightly apart so they do not overlap. Head is a big rounded mustard-yellow cube with two small dark vertical eyes, about one third of body height. Polished stylized 3D render, soft top-left light, no cast shadows on the body from other parts, true transparent background, no ground, no rope, no hook, no text.

## 2. Голова — `head.png`, холст 532×481

Ось шеи — точка (261, 420). Нижний край куба на ~60 px выше низа холста; шея ниже рисуется не здесь, а в торсе.

Prompt: Isolated head part for a cut-out rig: big rounded mustard-yellow cube head of the reference explorer, side view looking right, slightly turned toward the viewer so the right face shows, NO eyes and NO face (eyes are a separate layer), side strap buckle on the left face as in the reference. Soft top-left light, no shadow from other parts, transparent background, centered with margins.

## 3. Глаза — `eyes.png`, 160×110

Prompt: Two small dark vertical rounded eyes with a tiny white highlight, as on the reference cube head, isolated on transparent background, nothing else.

## 4. Торс — `torso.png`, холст 328×369

Суставы: `spine` (159, 266), `chest` (169, 164). Торс гнётся по двум костям, поэтому рисуется ровно, без изгиба.

Prompt: Isolated torso part for a cut-out rig: the reference explorer's green outdoor jacket body WITHOUT arms and WITHOUT backpack, side view looking right. Paint it whole: rounded shoulders where the sleeves will attach (no holes), the yellow neck rising above the collar (it goes under the head), the jacket hem long enough to cover the top of the pants, backpack straps and belt as in the reference. Soft top-left light, no shadows from arms or head, transparent background.

## 5. Рукав — `sleeve.png`, холст 179×350

Рисуется **прямым, свисающим вниз**: плечо сверху, манжета снизу. Суставы: плечо (90, 51), локоть (90, 175), запястье (90, 299). В локте рукав гнётся сеткой, поэтому ткань там ровная, без нарисованного сгиба.

Prompt: Isolated sleeve part for a cut-out rig: one whole green jacket sleeve of the reference explorer, perfectly straight and vertical, shoulder at the top, cuff at the bottom, no hand. Paint the full round shoulder cap at the top (it goes under the torso edge), a leather shoulder patch, light fabric folds near the middle (elbow) and a darker cuff band at the bottom. Soft top-left light, no shadows from other parts, transparent background, centered.

## 6. Перчатка — `glove.png`, холст 184×184

Свисает вниз, запястье сверху: точка (92, 55). Запястье с запасом уходит в манжету.

Prompt: Isolated glove part for a cut-out rig: the reference explorer's dark brown leather glove, hand closed in a loose fist holding nothing, hanging down with the wrist at the top and a short brown leather cuff strap, side view. Soft top-left light, transparent background, centered.

## 1б. Варианты эталона для выбора

Все варианты используют `game/assets/art/explorer-whole-v3.png` только как референс идентичности и стиля. Результат — один герой во весь рост на настоящем прозрачном фоне; выбрать один вариант и сохранить его как `game/assets/hero/pioneer/reference.png` после визуальной приёмки.

### Вариант A — классический профиль

```text
Use case: character reference sheet
Asset type: neutral reference pose for a cut-out bone rig
Input image: explorer-whole-v3.png is ONLY an identity and style reference; do not copy its dynamic pose or background.
Generate exactly ONE full-body Pioneer/explorer, strict orthographic side view facing right, standing perfectly upright. Both arms hang slightly forward and away from the torso, with the hands separated from the body. Both legs are straight, planted, and slightly apart so neither leg overlaps the other. Keep the entire silhouette inside the canvas with generous transparent margins.
Use the same yellow rounded cube-headed explorer identity: large mustard-yellow rounded cube head with two small dark vertical eyes visible in side profile, green outdoor jacket, brown leather backpack, dark charcoal pants, brown rugged hiking boots, practical straps and seams. Paint every part as a complete form with hidden continuation for later cut-out rigging.
Polished stylized 3D game render, soft detailed fabric and leather texture, consistent single-weight contour, cohesive proportions and detail density matching the reference. Soft top-left studio light, gentle form shading, no cast shadows from neighboring parts.
True transparent background with alpha. No floor, ground shadow, rope, hook, props, extra character, cropped limbs, foreshortening, perspective distortion, overlapping arms or legs, text, labels, or watermark.
```

### Вариант B — более компактный силуэт

```text
Use case: character reference sheet
Asset type: neutral reference sheet for a 2D cut-out bone rig
Use explorer-whole-v3.png only for the explorer's identity, materials, palette, and stylized 3D rendering language.
Create exactly ONE full-body character in a clean, strict right-facing side profile. Stand straight in a neutral anatomical pose. Place both arms slightly forward with a clear gap from the torso; place both straight legs with a small, readable gap between boots. The full mustard-yellow rounded cube head, green jacket, brown leather backpack, charcoal pants, and brown hiking boots must be visible as separate, complete forms with no hidden holes.
Centered orthographic composition with generous empty transparent margins, no perspective and no foreshortening. Preserve the friendly compact proportions of the reference while making the silhouette easy to split into head, torso, sleeves, gloves, legs, and boots.
Polished stylized 3D game render with tactile cloth, leather, and painted metal details, one consistent contour weight, soft top-left light, and restrained contact shading only where parts meet.
True transparent alpha background. No ground, cast shadow, rope, hook, equipment in hand, extra figures, overlapping limbs, cropped parts, text, labels, or watermark.
```

### Вариант C — чуть более высокий рабочий профиль

```text
Use case: character reference sheet
Asset type: full-body neutral style and scale reference for a bone-driven cut-out hero
Reference image: explorer-whole-v3.png supplies identity and visual style only; redraw the character in the requested pose.
Render exactly one yellow cube-headed wilderness explorer, full body, strict side view looking right, standing upright with a calm neutral posture. The head is a large rounded mustard-yellow cube with two small dark vertical eyes in profile. The green outdoor jacket, brown leather backpack, dark pants, and brown hiking boots are fully readable. Arms rest slightly forward and away from the chest, with both gloves visible; legs are straight and separated enough that the far leg and boot never merge with the near leg.
Use a centered orthographic profile and generous transparent padding. Make all clothing and gear continuous behind attachment areas so the image can be split into complete parts for a skinned 2D rig. Keep the slightly taller, practical explorer proportions balanced and believable.
Polished stylized 3D game render, soft fabric and leather texture, clean single-weight outline, matching detail scale throughout, soft top-left key light, gentle volume shading, no neighboring-part cast shadows.
True transparent background with alpha. No floor, ground shadow, rope, hook, held prop, extra character, cropped limbs, overlap, foreshortening, perspective, text, labels, or watermark.
```

## Проверка после замены

```bash
python tools/character_template.py
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/test_hero_rig.gd
```

```bash
tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --script res://tools/hero_prototype_preview.gd -- --mode=sheet --out=docs/character/prototype
```

Тест проверяет сгиб, стыки и слои на новых картинках так же, как на заглушках.

## 1б. Сгенерированные варианты эталона

Дата генерации: 2026-11-05

- `game/assets/hero/pioneer/reference-v1.png`
- `game/assets/hero/pioneer/reference-v2.png`
- `game/assets/hero/pioneer/reference-v3.png`

### Точный prompt для `reference-v1.png`

```text
Use case: stylized-concept. Asset type: game character cut-out reference. Input image: the provided explorer-whole-v3.png is a style and identity reference only; copy its polished stylized 3D rendering, materials, color language, and character identity, not its pose. Generate exactly ONE full-body character on a truly transparent alpha background, centered with generous padding so nothing touches or is cropped by the canvas. Strict left-to-right side profile, looking RIGHT, standing upright and completely still, weight on both feet. Variant v1 proportions: big rounded mustard-yellow cube head about one third of total height, short sturdy body. Head has two small dark vertical eyes with tiny highlights on the right-facing face, plus the side strap and buckle treatment seen in the reference. Green outdoor jacket, dark pants with knee patches, brown leather hiking backpack mounted on the back, brown hiking boots. Arms hang straight down and slightly FORWARD, clearly separated from the jacket body by a visible gap; hands are relaxed loose fists in dark brown gloves. Legs straight and slightly separated front-to-back so near and far leg do not overlap fully. Polished high-quality stylized 3D render with visible fabric and leather texture, soft light from upper left, no cast shadows from one body part onto another, no ground shadow. No ground, rope, hook, text, watermark, extra objects, extra characters, cropped limbs, front view, three-quarter view, motion, or duplicate body parts. Preserve clean transparent edges and true alpha.
```

### Точный prompt для `reference-v2.png`

```text
Use case: stylized-concept. Asset type: game character cut-out reference. Input image: the provided explorer-whole-v3.png is a style and identity reference only; copy its polished stylized 3D rendering, materials, color language, and character identity, not its pose. Generate exactly ONE full-body character on a truly transparent alpha background, centered with generous padding so nothing touches or is cropped by the canvas. Strict left-to-right side profile, looking RIGHT, standing upright and completely still, weight on both feet. Variant v2 proportions: slightly taller body and longer straight legs than the reference, more athletic; the big rounded mustard-yellow cube head is about 30 percent of total height. Head has two small dark vertical eyes with tiny highlights on the right-facing face, plus the side strap and buckle treatment seen in the reference. Green outdoor jacket, dark pants with knee patches, brown leather hiking backpack mounted on the back, brown hiking boots. Arms hang straight down and slightly FORWARD, clearly separated from the jacket body by a visible gap; hands are relaxed loose fists in dark brown gloves. Legs straight and slightly separated front-to-back so near and far leg do not overlap fully. Polished high-quality stylized 3D render with visible fabric and leather texture, soft light from upper left, no cast shadows from one body part onto another, no ground shadow. No ground, rope, hook, text, watermark, extra objects, extra characters, cropped limbs, front view, three-quarter view, motion, or duplicate body parts. Preserve clean transparent edges and true alpha.
```

### Точный prompt для `reference-v3.png`

```text
Use case: stylized-concept. Asset type: game character cut-out reference. Input image: the provided explorer-whole-v3.png is a style and identity reference only; copy its polished stylized 3D rendering, materials, color language, and character identity, not its pose. Generate exactly ONE full-body character on a genuinely empty transparent alpha background: every pixel outside the character silhouette must be fully transparent, with no halo, glow, vignette, backdrop, or ground shadow. Center the figure with generous padding so nothing is cropped. Strict left-to-right side profile, looking RIGHT, standing upright and completely still, weight on both feet. Variant v3 proportions: like the reference proportions, big rounded mustard-yellow cube head about one third of total height, short sturdy body. Head has two small dark vertical eyes with tiny highlights on the right-facing face, plus the side strap and buckle treatment seen in the reference. Green outdoor jacket, dark pants with knee patches, brown hiking boots, and a smaller brown leather backpack sitting higher on the back so the arm silhouette is cleaner. Arms hang straight down and slightly FORWARD, clearly separated from the jacket body by a visible gap; hands are relaxed loose fists in dark brown gloves. Legs straight and slightly separated front-to-back so near and far leg do not overlap fully. Polished high-quality stylized 3D render with visible fabric and leather texture, soft light from upper left, no cast shadows from one body part onto another. No ground, rope, hook, text, watermark, extra objects, extra characters, cropped limbs, front view, three-quarter view, motion, or duplicate body parts. Preserve clean transparent edges and true alpha.
```

## 2б. Сгенерированные детали среза

Дата генерации: 2026-11-06

Файлы:

- `game/assets/hero/pioneer/raw/head.png`
- `game/assets/hero/pioneer/raw/eyes.png`
- `game/assets/hero/pioneer/raw/torso.png`
- `game/assets/hero/pioneer/raw/sleeve.png`
- `game/assets/hero/pioneer/raw/glove.png`

### Точный prompt для `head.png`

```text
Use case: stylized-concept. Asset type: isolated 2D cut-out game character part for a bone rig. Input image: Image 1 is the exact Pioneer character identity, material, proportions, palette, and polished stylized 3D rendering reference; match it precisely. Generate exactly ONE isolated character part: the big rounded mustard-yellow cube head from the reference, strict orthographic side view looking RIGHT. Include the full head volume with the leather side strap and metal buckle on the left/back side exactly as in the reference. The face must be a completely blank yellow surface: NO eyes, no highlights, no facial marks. Paint the head as a whole complete form with hidden continuation under the neck/neighbor for later cut-out rigging, but do not include any neck, collar, torso, or other body parts. Centered with generous transparent margins; nothing cropped. Same soft upper-left light, tactile worn yellow painted surface, subtle scratches and seams, consistent detail density and contour with the reference. True transparent background with real alpha, no halo, no glow, no cast shadow, no ground shadow, no vignette, no backdrop. No extra objects, no text, no watermark, no duplicate part, no perspective, no three-quarter view.
```

### Точный prompt для `eyes.png`

```text
Use case: stylized-concept. Asset type: isolated 2D cut-out game character facial layer for a bone rig. Input image: Image 1 is the exact Pioneer character identity and head reference; match the eye shapes, materials, proportions, and polished stylized 3D rendering precisely. Generate exactly ONE isolated facial part: the two small dark vertical rounded eyes from the reference head, side by side exactly as they appear in the strict right-facing side view, each with a tiny white vertical highlight. Include only the eyes and their subtle dark edge volume; no yellow head, no strap, no buckle, no neck, no other facial features, no extra objects. Keep their relative spacing and vertical alignment exactly like the reference. Centered with generous transparent margins; nothing cropped. Same soft upper-left light and crisp tactile render quality. True transparent background with real alpha, no halo, no glow, no cast shadow, no ground shadow, no vignette, no backdrop. No text, no watermark, no duplicate eyes, no perspective, no three-quarter view.
```

### Точный prompt для `torso.png`

```text
Use case: stylized-concept. Asset type: isolated 2D cut-out game character torso part for a bone rig. Input image: Image 1 is the exact Pioneer character identity, materials, proportions, palette, and polished stylized 3D render reference; match it precisely. Generate exactly ONE isolated torso part in strict orthographic side view looking RIGHT: the green outdoor jacket body only, with no arms or sleeves, no backpack, no head, no pants, no gloves, no boots. Paint the torso as a complete whole form for cut-out rigging: full round smooth shoulder caps at both sleeve attachment ends with fabric continuing underneath, a short yellow neck rising above the collar that will hide under the head, the hood/collar, chest pocket, seams, and the front-crossing backpack shoulder strap with its leather buckles as seen in the reference. Make the jacket hem slightly longer than the reference so it covers the top of the pants. Keep the front silhouette and side profile proportions faithful to the character; shoulder end and hem fully contained inside the canvas. Centered with generous transparent margins, nothing cropped. Same olive-green worn fabric texture, leather strap texture, soft upper-left light, and polished tactile stylized 3D quality as the reference. No cast shadows from other parts, no ground shadow, no halo, no glow, no backdrop, true transparent alpha. No extra objects, no text, no watermark, no perspective, no three-quarter view.
```

### Точный prompt для `sleeve.png`

```text
Use case: stylized-concept. Asset type: isolated 2D cut-out game character sleeve part for a bone rig. Input image: Image 1 is the exact Pioneer character identity, green jacket materials, palette, proportions, and polished stylized 3D render reference; match it precisely. Generate exactly ONE whole green jacket sleeve, strict side view, perfectly STRAIGHT and VERTICAL, shoulder end at the TOP and cuff at the BOTTOM. No hand and no glove. The top must end in a full rounded shoulder cap with complete fabric volume that hides under the torso edge; paint the sleeve whole with hidden continuation at both attachment areas so it can bend without holes. Match the reference arm thickness. Include gentle realistic fabric folds around the middle/elbow and the leather cuff strap with metal buckle near the bottom exactly in the reference style. Centered with generous transparent margins, fully inside canvas, nothing cropped. Same olive-green worn fabric texture, leather and painted metal detail, soft upper-left light, polished tactile stylized 3D quality. True transparent background with real alpha. No torso, head, backpack, glove, other limbs, cast shadows from neighboring parts, ground shadow, halo, glow, vignette, backdrop, text, watermark, perspective, or three-quarter view.
```

### Точный prompt для `glove.png`

```text
Use case: stylized-concept. Asset type: isolated 2D cut-out game character glove part for a bone rig. Input image: Image 1 is the exact Pioneer character identity, glove material, proportions, palette, and polished stylized 3D render reference; match it precisely. Generate exactly ONE isolated dark brown leather glove: a hand closed in a loose relaxed fist holding nothing, hanging DOWN in a strict side view looking RIGHT. The wrist opening is at the TOP with a short wrist section that will hide inside the green sleeve cuff. Keep the glove thickness and compact proportions faithful to the reference; show believable finger and knuckle volumes without opening the hand. Paint the glove as a whole complete form with hidden continuation inside the cuff for later cut-out rigging. Centered with generous transparent margins, fully inside the canvas, nothing cropped. Same worn dark brown leather texture, seam detail, soft upper-left light, polished tactile stylized 3D quality. True transparent background with real alpha, no halo, no glow, no cast shadow, no ground shadow, no vignette, no backdrop. No sleeve, torso, head, backpack, extra objects, text, watermark, duplicate glove, perspective, or three-quarter view.
```

## 2в. Ноги, таз, ботинок, рюкзак

Дата генерации: 2026-11-06

Файлы:

- `game/assets/hero/pioneer/raw/pant_leg.png`
- `game/assets/hero/pioneer/raw/pelvis.png`
- `game/assets/hero/pioneer/raw/boot.png`
- `game/assets/hero/pioneer/raw/backpack.png`

### Точный prompt для `pant_leg.png`

```text
Use case: stylized-concept. Asset type: isolated 2D cut-out game character leg part for a bone rig. Input images: Image 1 is the exact Pioneer identity, proportions, palette, and polished stylized 3D render reference; Image 2 is the accepted torso part style reference; Image 3 is the accepted sleeve part style reference. Match their rendering quality, tactile materials, scale, and soft light from the upper left.

Generate exactly ONE isolated whole leg of the Pioneer dark charcoal-grey cargo pants, strict orthographic side view looking RIGHT, perfectly STRAIGHT and VERTICAL, hip end at the TOP and ankle hem at the BOTTOM. No boot, no foot, no pelvis, no jacket, no other body parts. The top ends in a rounded, fully painted hip cap with hidden continuation that will tuck under the pelvis and jacket hem; the lower end extends slightly inside the future boot opening so bending and rotation never reveal a hole. Match the reference leg thickness and long athletic proportions. On the front/right side, include the tan leather knee patch centered at the middle, with worn leather, stitched edge, and subtle raised volume. Include the leather thigh strap with its metal buckle in the upper third exactly in the reference style. Add gentle natural fabric folds behind the knee and along the leg, with a plain slightly narrower bottom hem. Paint the entire form, including concealed continuation at both attachment ends, for cut-out rigging.

Center the leg with generous transparent margins and keep the whole part inside the canvas; nothing cropped. True transparent background with real alpha: every pixel outside the leg fully transparent. Same worn charcoal fabric, tan leather, painted metal, tactile detail density, and soft upper-left light as the references. No cast shadows from other body parts, no ground shadow, no halo, no glow, no vignette, no backdrop, no text, no watermark, no duplicate limbs, no perspective, no three-quarter view.
```

### Точный prompt для `pelvis.png`

```text
Use case: stylized-concept. Asset type: isolated 2D cut-out game character pelvis part for a bone rig. Input images: Image 1 is the exact Pioneer identity, proportions, palette, and polished stylized 3D render reference; Image 2 is the accepted torso part style reference; Image 3 is the accepted sleeve part style reference. Match their rendering quality, tactile materials, scale, and soft light from the upper left.

Generate exactly ONE isolated pelvis/seat block of the same dark charcoal-grey cargo pants, strict orthographic side view looking RIGHT. The waist with a plain belt band is at the TOP; rounded buttocks/back are on the LEFT; the front/crotch points toward the RIGHT; the crotch is at the BOTTOM. Show only the pelvis and upper-thigh seat block, ending before the mid-thigh: no legs below the upper thigh, no jacket, no torso, no boots, no straps or knee patches. Paint it as a complete rounded whole with generous hidden continuation under the jacket hem and around both leg-cap openings so the leg parts can tuck beneath it without holes during bending. Include natural worn charcoal fabric texture, seams, subtle folds at the seat and crotch, and a plain waistband/belt band at the top. Keep the proportions consistent with the Pioneer reference and pant_leg scale.

Center the pelvis with generous transparent margins and keep the whole part inside the canvas; nothing cropped. True transparent background with real alpha: every pixel outside the pelvis fully transparent. Same tactile stylized 3D quality, soft upper-left light, and detail density as the references. No cast shadows from other body parts, no ground shadow, no halo, no glow, no vignette, no backdrop, no text, no watermark, no duplicate parts, no perspective, no three-quarter view.
```

### Точный prompt для `boot.png`

```text
Use case: stylized-concept. Asset type: isolated 2D cut-out game character boot part for a bone rig. Input images: Image 1 is the exact Pioneer identity, proportions, palette, and polished stylized 3D render reference; Image 2 is the accepted torso part style reference; Image 3 is the accepted sleeve part style reference. Match their rendering quality, tactile materials, scale, and soft light from the upper left.

Generate exactly ONE isolated brown leather hiking boot from the Pioneer reference, strict orthographic side view, toe pointing RIGHT. The boot stands on its flat chunky dark rubber sole. Show the full boot only: rounded toe at the RIGHT, heel at the LEFT, laces and metal eyelets along the upper, stitched panels, padded ankle collar, and a short dark inner section visible inside the top opening where the pant hem will tuck. Paint the boot as a complete whole with hidden continuation under the pant opening; the sole is fully complete and flat. No second boot, no leg, no pants, no foot or body parts beyond this single boot.

Center the boot with generous transparent margins and keep the whole part inside the canvas; nothing cropped. True transparent background with real alpha: every pixel outside the boot fully transparent. Match the Pioneer worn warm-brown leather, dark sole, metal eyelets, stitching, tactile stylized 3D quality, and soft upper-left light. No cast shadows from other body parts, no ground shadow, no halo, no glow, no vignette, no backdrop, no text, no watermark, no duplicate parts, no perspective, no three-quarter view.
```

### Точный prompt для `backpack.png`

```text
Use case: stylized-concept. Asset type: isolated 2D cut-out game character backpack part for a bone rig. Input images: Image 1 is the exact Pioneer identity, proportions, palette, and polished stylized 3D render reference; Image 2 is the accepted torso part style reference; Image 3 is the accepted sleeve part style reference. Match their rendering quality, tactile materials, scale, and soft light from the upper left.

Generate exactly ONE isolated brown leather hiking backpack from the Pioneer reference, strict orthographic side view as worn by a character looking RIGHT: the back of the pack is on the LEFT, and the side touching the hero's back is on the RIGHT. Include the rolled green sleeping mat on top, the front pocket with its leather flaps and buckles, and the green thermos secured in its side holder exactly in the reference style. The right edge touching the hero's back must be a clean straight-ish panel. Paint the backpack as a complete whole with hidden continuation behind the back-facing panel and under the sleeping mat so it can rotate and sway without holes. Include worn brown leather, green canvas, straps, stitching, metal buckles, pocket seams, and tactile rounded volume.

Do not include the shoulder straps that cross the chest; those are painted on the torso. Do not include any head, torso, arms, hands, legs, boots, or other character parts. Center the pack with generous transparent margins and keep the whole part inside the canvas; nothing cropped. True transparent background with real alpha: every pixel outside the backpack fully transparent. Same polished stylized 3D quality and soft upper-left light as the references. No cast shadows from other body parts, no ground shadow, no halo, no glow, no vignette, no backdrop, no text, no watermark, no duplicate objects, no perspective, no three-quarter view.
```
