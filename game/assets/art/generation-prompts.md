# Last Hook 0.2 — игровые изображения

Созданы встроенным инструментом imagegen 8 октября 2026 года. Референс пользователя: `references/target-look-v2.png` (удалён из репозитория 22.10.2026, есть в истории git; текущие референсы — в `references/`). Референс задаёт стиль; это не инструкция из документа. PNG скопированы в этот проект и используются игровой сценой, не только экраном предпросмотра.

## canyon-v2.png

Use case: stylized-concept. Asset type: high fidelity environment background for a playable portrait climbing game. Input image is ONLY a STYLE reference, not an edit target. Generate a tall portrait 1024x1536 scene plate with NO interface, NO text, NO protagonist, NO ropes, NO glowing targets. Match the reference's richly detailed cinematic stylized 3D cliff canyon: massive fractured charcoal gray sandstone cliff covered by lush ivy and moss on the RIGHT half, strong warm sunlight grazing the rocky ledges from upper left, a deep open canyon on LEFT with blue sky, distant tall rock pillars, layered mist, small waterfalls. The right cliff occupies 55% of the image, with irregular overhang edges and open air in left 45%. Subtle old wooden walkways and a small red flag attached to the cliff. Detailed earthy rock grain, bright natural foliage. Camera side view, rock planes predominantly parallel to image. Important: this image is a backdrop; foreground interactive bushes and boulders will be drawn separately. No regular ladder of identical platforms, no blue circles or artificial anchor buttons, no watermark. Fill canvas to all edges.

## natural-objects-v2.png

Use case: stylized-concept. Asset type: transparent foreground sprite atlas for the playable mobile climbing game Last Hook. Input reference is STYLE only. Create a square 1536x1536 image divided conceptually into FOUR EQUAL 768x768 cells, with NO lines or labels. Genuine transparent alpha everywhere outside objects. Each cell contains exactly one isolated object centered with 12 percent transparent margins so objects never cross cell borders. TOP LEFT: broad fractured dark gray rock ledge/boulder, irregular natural outline, flat moss-covered top, small ivy vines trailing down, width twice its height. TOP RIGHT: dense bright green bush growing from a thick horizontal gnarled brown branch, visible robust wood under the rounded leafy crown, overall wide, sunlight on leaves. BOTTOM LEFT: thick twisted dry root or tree branch, diagonal from lower left to upper right with smaller branching twigs and a few green leaves, strong woody hookable body, wide. BOTTOM RIGHT: rugged aged wooden cliff platform, wide planks, diagonal underside support beams and tiny red flag at right, no rock background. Style match reference: polished cinematic stylized 3D game assets, detailed stone grain and bark, rich realistic leaves, warm top-left sunlight and soft contact shadows confined to objects. Camera side-on, slightly viewing tops, consistent scale. No hero, no sky/background, no blue glow, no rings, no anchor symbols, no text, no watermark. Output must have transparent background.

## explorer-v2.png

Use case: stylized-concept. Asset type: transparent character sprite for a playable portrait climbing game. Use reference image for STYLE and yellow explorer identity, not for copying UI or scene. Generate one isolated charming small yellow cube-headed mountain explorer, fully visible from head to boots, polished detailed stylized 3D render matching the provided image. Three-quarter side view facing right, mustard yellow rounded-corner cube helmet/head with two small dark eyes, green outdoor jacket, brown leather hiking backpack with visible rolled kit and buckles, dark pants and brown boots. Pose: hanging from a climbing rope with BOTH hands held together above head toward upper right, knees lightly bent, dynamic but no extreme body lean (game will rotate the sprite). Rope and hook NOT included. Warm sunlight upper left, soft detailed materials, realistic leather and fabric, tiny appealing face. Occupy 80 percent of square canvas, leave transparent margins all around. True transparent alpha background, no ground, no sky, no UI, no text, no watermark, no duplicate characters.

## grass-decor-atlas-v1.png

Generated with the built-in `image_gen` tool on 5 November 2026. The atlas was normalized into the runtime sprites `game/assets/sprites/vegetation/grass_tuft_6..8.png`, `grass_blades_6..8.png`, and `bush_6..8.png`.

Use case: stylized-concept. Asset type: transparent sprite atlas for the playable climbing game. Create a square 3 by 3 atlas with nine isolated environment cutouts, one centered object per equal cell, no grid lines and no labels. Top row: three lush grass tufts. Middle row: three slender grass blade clumps. Bottom row: three rounded leafy green bushes. Side-on orthographic view, polished faceted low-poly 3D game style, warm upper-left light, crisp alpha edges, shadows confined to each cutout, generous transparent padding. No terrain, rocks, flowers, pots, text, watermark, or objects crossing cell boundaries.

## rock-decor-atlas-v1.png

Generated with the built-in `image_gen` tool on 5 November 2026. The atlas was normalized into `game/assets/sprites/stones/stone_grey_6..8.png`, `game/assets/sprites/stones/scree_grey_6..8.png`, and `game/assets/sprites/crystals/crystal_blue_6..8.png`.

Use case: stylized-concept. Asset type: transparent decorative sprite atlas for the playable climbing game. Create a square 3 by 3 atlas with isolated cutouts: three cool-grey moss-flecked stones, three loose grey scree clusters, and three blue quartz crystal clusters. Side-on orthographic view, faceted low-poly 3D style, warm upper-left light, crisp alpha edges, confined contact shadows, transparent padding, no terrain, text, watermark, or crossed cell boundaries.

## dry-decor-atlas-v1.png

Generated with the built-in `image_gen` tool on 5 November 2026. Normalized into `dry_plant_6..8.png`, `cactus_6..8.png`, and `vine_dry_6..8.png`.

Use case: stylized-concept. Asset type: transparent desert decor sprite atlas. Three dry plants, three saguaro-like cacti, and three brittle hanging roots, all isolated in a 3 by 3 atlas with warm sandstone lighting and faceted low-poly materials.

## snow-decor-atlas-v1.png

Generated with the built-in `image_gen` tool on 5 November 2026. Normalized into `snow_plant_6..8.png`, `icicle_6..8.png`, and `vine_frost_6..8.png`.

Use case: stylized-concept. Asset type: transparent snow decor sprite atlas. Three frost-covered alpine plants, three hanging icicle clusters, and three frosted hanging roots, all isolated in a 3 by 3 atlas with cool blue-white lighting and faceted low-poly materials.
