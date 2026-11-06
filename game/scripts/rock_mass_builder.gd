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
	var wood := bool(palette.get("wood",false))
	var shade_cache := {}
	# Summer boulders: the top of each boulder in the light, its foot in shade
	# (palette "rise", 0 = off), and faces turned up lighter still.
	var rise := float(palette.get("rise",0.0))
	var low := mass.bounds.position.y
	var tall := maxf(mass.bounds.size.y,.01)
	# Summer moss (palette "moss" = density 0..1): green caps on the upward
	# faces near the top of a boulder, dark moss in the joints where another
	# boulder shades it, and a band under a boulder that hangs over open air
	# ("hang_moss"). Part of the stone's own colour, not a decal.
	var moss := float(palette.get("moss",0.0))
	var moss_top: Color = palette.get("moss_top",Color.WHITE)
	var moss_dark: Color = palette.get("moss_dark",Color.WHITE)
	var hang_moss := bool(palette.get("hang_moss",false))
	for index in range(mass.faces.size()):
		var face: Dictionary = mass.faces[index]
		var face_class: String = face["class"]
		if face_class==RockMassSpec.WALL and not walls: continue
		# Every visible face of a boulder is the same stone: the rim ring takes
		# a facet tone too and only leans towards its class, so the light, not
		# a pale frame, shows where the boulder turns away.
		var tone: Color = facets[(index+mass.id)%facets.size()]
		var jitter := (_hash(mass.id,index)-.5)*.13+(mass.tone-.5)*.09
		tone = tone.lightened(jitter) if jitter>0 else tone.darkened(-jitter)
		if wood:
			# Broad grain follows the platform length; it keeps wood readable
			# after the massif shader adds lighting and texture.
			var grain := sin((face["a"].x+face["b"].x+face["c"].x)*3.8+(face["a"].y+face["b"].y+face["c"].y)*.35)
			if grain<-.35: tone = tone.darkened(clampf((-grain-.35)*.16,0,.12))
			elif grain>.72: tone = tone.lightened(clampf((grain-.72)*.18,0,.08))
		match face_class:
			RockMassSpec.TOP: tone = tone.lerp(palette["top"],.25)
			RockMassSpec.UNDERSIDE: tone = tone.lerp(palette["under"],.55)
			RockMassSpec.INNER: tone = palette["inner"]
			RockMassSpec.WALL: tone = palette["under"]
			RockMassSpec.SIDE: tone = tone.lerp(palette["side"],.35)
		var a: Vector3 = face["a"]
		var b: Vector3 = face["b"]
		var c: Vector3 = face["c"]
		var normal := (b-a).cross(c-a).normalized()
		if normal.z<0: normal = -normal
		if rise>0.0 and face_class!=RockMassSpec.WALL:
			var height := clampf(((a.y+b.y+c.y)/3.0-low)/tall,0,1)
			var lift := (height-.45)*rise+normal.y*rise*.45
			tone = tone.lightened(lift) if lift>0 else tone.darkened(-lift)
		var joint := 0.0
		if moss>0.0 and face_class!=RockMassSpec.WALL and face_class!=RockMassSpec.INNER:
			var height := clampf(((a.y+b.y+c.y)/3.0-low)/tall,0,1)
			var patch := _hash(mass.id*7+3,index)
			var cap := 0.0
			if face_class==RockMassSpec.UNDERSIDE:
				if hang_moss: cap = smoothstep(.45,.85,patch)*.7
			else:
				var up := smoothstep(.12,.5,normal.y)
				cap = up*smoothstep(.62,.9,height+(patch-.5)*.25)
				if face_class==RockMassSpec.TOP: cap = maxf(cap,smoothstep(.2,.5,normal.y)*.85)
				# Patches, not a painted band: some faces stay bare stone.
				cap *= smoothstep(.2,.5,patch+moss*.3)
			cap = clampf(cap*moss,0,.78)
			if cap>0.0: tone = tone.lerp(moss_dark if face_class==RockMassSpec.UNDERSIDE else moss_top.lerp(moss_dark,clampf(.6-height,0,.6)),cap)
			joint = moss*smoothstep(-.2,.6,normal.y)
		for point in [a,c,b]:
			var key: Vector3 = point
			if not shade_cache.has(key): shade_cache[key] = cavity.call(mass,key)
			var shade := float(shade_cache[key])
			var color := tone
			# Joints: moss grows in the damp shade between boulders.
			if joint>0.0 and shade>.08: color = color.lerp(moss_dark,clampf((shade-.08)*2.6,0,.75)*joint)
			surface.set_color(color.darkened(shade))
			surface.set_normal(normal)
			surface.add_vertex(point)
			emitted += 1
	return emitted

# A tuft of grass standing on a boulder's top edge: a fan of thin blades in
# the plane of the face, base at `base`, part of the rock mesh (no decal, no
# sprite), so it is drawn on every preset.
static func emit_tuft(surface: SurfaceTool, base: Vector3, height: float, width: float, light: Color, dark: Color, seed_value: int) -> int:
	var blades := 4+seed_value%3
	var emitted := 0
	for blade in range(blades):
		var t := (blade+.5)/blades-.5
		var lean := t*1.3+(_hash(seed_value,blade)-.5)*.5
		var tall := height*(.65+_hash(seed_value,blade+11)*.45)*(1.0-absf(t)*.5)
		var foot := base+Vector3(t*width,-.03,blade*.004)
		var tip := foot+Vector3(lean*height*.45,tall,.02)
		var half := width/blades*.55
		var color := dark.lerp(light,.35+_hash(seed_value,blade+23)*.4)
		for point in [foot+Vector3(-half,0,0),tip,foot+Vector3(half,0,0)]:
			surface.set_color(dark if point!=tip else color.lightened(.12))
			surface.set_normal(Vector3.BACK)
			surface.add_vertex(point)
			emitted += 1
	return emitted

static func _hash(i: int, j: int) -> float:
	return fposmod(sin(i*127.1+j*311.7)*43758.5453,1.0)
