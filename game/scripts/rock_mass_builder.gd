class_name RockMassBuilder
extends RefCounted

# Turns rock masses into one mesh per chunk. Each face group gets its own
# tone from the material profile: lit tops lean to the top tint, undersides
# and arch walls to the cool underside tint, the front facets vary within the
# facet palette. Cavity shade is evaluated per vertex from the masses in
# front, so creases and contacts darken softly instead of carrying decals.

# palette: base, top, side, under, inner, facets (Array of Color).
# cavity: Callable(mass: RockMassSpec, point: Vector3) -> float 0..1.
static func emit(surface: SurfaceTool, mass: RockMassSpec, palette: Dictionary, cavity: Callable, walls: bool) -> int:
	var emitted := 0
	var facets: Array = palette["facets"]
	var shade_cache := {}
	for index in range(mass.faces.size()):
		var face: Dictionary = mass.faces[index]
		var face_class: String = face["class"]
		if face_class==RockMassSpec.WALL and not walls: continue
		var tone: Color
		match face_class:
			RockMassSpec.FACE:
				tone = (facets[(index+mass.id)%facets.size()] as Color)
				var jitter := (_hash(mass.id,index)-.5)*.13+(mass.tone-.5)*.09
				tone = tone.lightened(jitter) if jitter>0 else tone.darkened(-jitter)
			RockMassSpec.TOP: tone = palette["top"]
			RockMassSpec.UNDERSIDE: tone = palette["under"]
			RockMassSpec.INNER: tone = palette["inner"]
			RockMassSpec.WALL: tone = palette["under"]
			_: tone = palette["side"]
		if face_class!=RockMassSpec.FACE:
			var jitter := (_hash(mass.id,index>>1)-.5)*.05
			tone = tone.lightened(jitter) if jitter>0 else tone.darkened(-jitter)
		var a: Vector3 = face["a"]
		var b: Vector3 = face["b"]
		var c: Vector3 = face["c"]
		var normal := (b-a).cross(c-a).normalized()
		if normal.z<0: normal = -normal
		for point in [a,c,b]:
			var key: Vector3 = point
			if not shade_cache.has(key): shade_cache[key] = cavity.call(mass,key)
			surface.set_color(tone.darkened(float(shade_cache[key])))
			surface.set_normal(normal)
			surface.add_vertex(point)
			emitted += 1
	return emitted

static func _hash(i: int, j: int) -> float:
	return fposmod(sin(i*127.1+j*311.7)*43758.5453,1.0)
