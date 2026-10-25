class_name LootIcon
extends RefCounted

# Icons of the finds for the backpack, the flying pickup and the lists: the
# same pictures the climb shows (TreasureModels) - the coin's turntable of
# its 3D model, the painted treasure itself - so the icon in the bag is the
# object the player just picked up. Each icon is laid out in a 48 x 48 box
# around the origin and drawn at `origin`, `size` / 48 scale.

const RARITY := ItemCatalog.VISUAL_RARITY_COLORS
const MATERIAL_COLORS := ItemCatalog.VISUAL_MATERIAL_COLORS
const TreasureModels := preload("res://scripts/treasure_models.gd")
# The coin's portrait cell in icon units: the model fills two thirds of it.
const COIN_CELL := 52.0
# A painted treasure fills this box, keeping its proportions.
const SPRITE_BOX := 38.0

static func rarity_color(item: Dictionary) -> Color:
	return ItemCatalog.visual_color(item)

static func draw(ci: CanvasItem, item: Dictionary, origin: Vector2, size: float, time: float = 0.0, rotation: float = 0.0) -> void:
	ci.draw_set_transform(origin,rotation,Vector2.ONE*size/48.0)
	_shadow(ci)
	var texture := TreasureModels.icon_texture(item)
	var region := TreasureModels.icon_region(item,time)
	if TreasureModels.kind_for(item)=="coin":
		ci.draw_texture_rect_region(texture,Rect2(-COIN_CELL*.5,-COIN_CELL*.5-1.0,COIN_CELL,COIN_CELL),region)
	else:
		# The painted treasure bobs gently over its shadow.
		var fit := SPRITE_BOX/maxf(region.size.x,region.size.y)
		var drawn := region.size*fit
		var bob := sin(time*TAU/TreasureModels.CYCLE)*1.2
		ci.draw_texture_rect_region(texture,Rect2(Vector2(-drawn.x*.5,15.0-drawn.y+bob),drawn),region)
	ci.draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

static func _shadow(ci: CanvasItem) -> void:
	var points := PackedVector2Array()
	for index in range(20):
		var angle := TAU*index/20
		points.append(Vector2(cos(angle)*14,17+sin(angle)*3.2))
	ci.draw_colored_polygon(points,Color("0b1218",.32))
