extends RefCounted
## BGModel — Big Globe-inspired world model for the voxel platform.
##
## A faithful-in-spirit GDScript port of the Big Globe overworld column stack
## (vendored configs: voxel-platform-handoff/vendor/big-globe/mod-unpacked/...):
##
##   river/macro ......... low-frequency fBm whose ZERO-CROSSINGS become rivers
##   mountainness ........ ((m^2) + (m^2)^2) / 2  → mountains where |macro| high
##   elevation ........... mid-frequency fBm, flattened near rivers
##   heightmap ........... elevation + mountainness * amplitude, river channels
##   temperature/humidity  climate fields → grass / sand / snow / moss surfaces
##   rock layers ......... deepslate depth blend, granite/diorite/andesite/tuff/
##                         calcite pockets, terracotta mesa stripes on mountains
##   caves ............... two zero-surface tunnel noises (BG "worm" curve idea)
##                         + cheese caverns, widening with depth, sealed near
##                         water bodies and The Core
##   features ............ deterministic trees (wood + leaf blobs) and boulders
##
## Output is *smooth SDF* (Space Engineers look) + Mixel4 material indices —
## never Minecraft cubes. No ores, no mechanics blocks, no skylands (user call).
##
## Pure math + FastNoiseLite: parses on stock Godot. Voxel buffers are passed
## in as Variant and written via duck typing, so this file never references
## godot_voxel classes. Used by BOTH the offline baker (tools/worldgen/
## bake_world.gd) and the dev-only live generator adapter (bg_generator.gd).

const R := preload("res://scripts/voxel/block_registry.gd")

# Voxel channel ids (godot_voxel VoxelBuffer constants, hardcoded for stock parse)
const CH_SDF := 1
const CH_INDICES := 3
const CH_WEIGHTS := 4
const WEIGHTS_SINGLE_PACKED := 0x000F   # w0=15 → 100% first index

const BLOCK_SIZE := 16
const LATTICE_N := 5                    # 3D noise lattice points per axis (stride 4)
const NO_WATER := -1.0e9

# --- World parameters (configure() overrides) ---------------------------------
var world_seed: int = 1337
var size_x: int = 2048
var size_z: int = 2048
var y_min: int = -512
var y_max: int = 256
var sea_level: float = 0.0
var core_top_y: float = -430.0
var mountain_amp: float = 340.0
var elev_amp: float = 190.0

# --- Noise fields --------------------------------------------------------------
var _n_macro: FastNoiseLite
var _n_elev: FastNoiseLite
var _n_temp: FastNoiseLite
var _n_humid: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_cave1: FastNoiseLite
var _n_cave2: FastNoiseLite
var _n_cheese: FastNoiseLite
var _n_pocket: FastNoiseLite
var _n_pocket2: FastNoiseLite
var _n_strata: FastNoiseLite


func _init() -> void:
	configure({})


func configure(cfg: Dictionary) -> void:
	world_seed = int(cfg.get("seed", world_seed))
	size_x = int(cfg.get("size_x", size_x))
	size_z = int(cfg.get("size_z", size_z))
	y_min = int(cfg.get("y_min", y_min))
	y_max = int(cfg.get("y_max", y_max))
	sea_level = float(cfg.get("sea_level", sea_level))
	core_top_y = float(cfg.get("core_top_y", core_top_y))
	mountain_amp = float(cfg.get("mountain_amp", mountain_amp))
	elev_amp = float(cfg.get("elev_amp", elev_amp))

	_n_macro = _fbm(1, 4, 3072.0, 0.4)      # BG river/macro: scales 3072..384, persistence 0.4
	_n_elev = _fbm(2, 5, 4096.0, 0.4)       # BG raw/elevation: 4096..256, persistence 0.4
	_n_temp = _fbm(3, 3, 4096.0, 0.5)
	_n_humid = _fbm(4, 3, 4096.0, 0.5)
	_n_detail = _fbm(5, 3, 48.0, 0.5)
	_n_cave1 = _fbm(6, 1, 140.0, 0.5)
	_n_cave2 = _fbm(7, 1, 97.0, 0.5)
	_n_cheese = _fbm(8, 2, 230.0, 0.5)
	_n_pocket = _fbm(9, 1, 85.0, 0.5)
	_n_pocket2 = _fbm(10, 1, 60.0, 0.5)
	_n_strata = _fbm(11, 1, 34.0, 0.5)


func bounds_aabb() -> AABB:
	return AABB(
		Vector3(-size_x / 2.0, float(y_min), -size_z / 2.0),
		Vector3(float(size_x), float(y_max - y_min), float(size_z)))


func _fbm(salt: int, octaves: int, scale: float, gain: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed * 31 + salt
	n.frequency = 1.0 / scale
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = gain
	return n


## --- Column stack (Big Globe port) --------------------------------------------

## Cheap column: height + hydrology. cache keys are Vector2i world coords.
func column(wx: int, wz: int, cache: Dictionary) -> Dictionary:
	var key := Vector2i(wx, wz)
	var hit: Variant = cache.get(key)
	if hit != null:
		return hit

	var m := _n_macro.get_noise_2d(wx, wz)            # river macro [-1,1]
	var mm := clampf(absf(m) * 1.55, 0.0, 1.0)        # amplified for taller ranges
	var mm2 := mm * mm
	var mount := (mm2 + mm2 * mm2) * 0.5              # BG raw/mountainness curve
	var river_t := 1.0 - smoothstep(0.0, 0.045, absf(m))
	var flatten := smoothstep(0.02, 0.30, absf(m))    # BG flat_river_elevation approx

	var elev := _n_elev.get_noise_2d(wx, wz) * elev_amp
	var detail := _n_detail.get_noise_2d(wx, wz) * (1.5 + 6.0 * mount)
	var h := elev * (0.35 + 0.65 * flatten) + mount * mountain_amp + 6.0 \
			+ detail * (0.3 + 0.7 * flatten)
	if h > 200.0:                                      # soft knee below world ceiling
		h = minf(200.0 + (h - 200.0) * 0.35, float(y_max) - 6.0)

	var water_y := NO_WATER
	if h <= sea_level + 0.5:
		water_y = sea_level                            # ocean
	elif river_t > 0.001:
		var bed := h - 6.5 * pow(river_t, 1.4)         # river channel carve
		if river_t > 0.35 and h - 2.2 > bed:
			water_y = h - 2.2
		h = bed

	var col := {
		"h": h, "mount": mount, "river_t": river_t,
		"water_y": water_y, "surf": {},
	}
	cache[key] = col
	return col


## Climate + surface materials, computed lazily (only for near-surface blocks).
func surface_info(wx: int, wz: int, col: Dictionary, cache: Dictionary) -> Dictionary:
	var surf: Dictionary = col["surf"]
	if not surf.is_empty():
		return surf

	var h: float = col["h"]
	var temp := _n_temp.get_noise_2d(wx, wz) - maxf(h, 0.0) * 0.0022   # colder up high
	var humid := _n_humid.get_noise_2d(wx, wz)
	# hilliness ~ |grad(height)| via cheap finite differences
	var he := _quick_h(wx + 3, wz, cache)
	var hw := _quick_h(wx - 3, wz, cache)
	var hn := _quick_h(wx, wz + 3, cache)
	var hs := _quick_h(wx, wz - 3, cache)
	var grad := Vector2((he - hw) / 6.0, (hn - hs) / 6.0).length()

	var snow_y := 120.0 + temp * 140.0                # colder climate → lower snowline
	var mesa := temp > 0.42 and humid < -0.42
	var desert := temp > 0.42 and humid < -0.12

	var surf_ch := R.GRASS
	var underwater: bool = col["water_y"] != NO_WATER and col["water_y"] > h
	if underwater:
		surf_ch = R.SAND if h > -14.0 else R.GRAVEL
	elif grad > 1.15:
		surf_ch = R.STONE
	elif grad > 0.78:
		surf_ch = R.GRAVEL
	elif h > snow_y or temp < -0.55:
		surf_ch = R.SNOW
	elif mesa:
		surf_ch = R.TERRACOTTA
	elif desert:
		surf_ch = R.SAND
	elif humid > 0.5 and temp > 0.05:
		surf_ch = R.MOSS
	elif h < sea_level + 2.5 and h > sea_level - 0.5 and col["river_t"] < 0.5:
		surf_ch = R.SAND                               # beaches
	var dirt_ch := R.DIRT
	if desert:
		dirt_ch = R.SAND
	elif mesa:
		dirt_ch = R.TERRACOTTA

	surf = {
		"temp": temp, "humid": humid, "grad": grad, "snow_y": snow_y,
		"mesa": mesa, "surf_ch": surf_ch, "dirt_ch": dirt_ch,
		"dirt_depth": 1.4 + clampf(4.0 - grad * 2.0, 0.5, 4.0),
	}
	col["surf"] = surf
	return surf


func _quick_h(wx: int, wz: int, cache: Dictionary) -> float:
	var key := Vector3i(wx, 1, wz)      # distinct keyspace from column cache
	var hit: Variant = cache.get(key)
	if hit != null:
		return hit
	var m := _n_macro.get_noise_2d(wx, wz)
	var mm := clampf(absf(m) * 1.55, 0.0, 1.0)
	var mm2 := mm * mm
	var flatten := smoothstep(0.02, 0.30, absf(m))
	var h: float = _n_elev.get_noise_2d(wx, wz) * elev_amp * (0.35 + 0.65 * flatten) \
			+ (mm2 + mm2 * mm2) * 0.5 * mountain_amp + 6.0
	cache[key] = h
	return h


## --- Per-voxel sampling helpers ------------------------------------------------

## Cave field: > 0 inside a cave (meters-ish of carve).
func _cave_value(y: float, col: Dictionary, c1: float, c2: float, cheese: float) -> float:
	var depth: float = col["h"] - y
	var strength := smoothstep(4.0, 10.0, depth)      # sealed near the open surface
	if strength <= 0.0:
		return -1.0
	var water_y: float = col["water_y"]
	if water_y != NO_WATER and y < water_y + 6.0 and depth < 30.0:
		return -1.0                                    # don't flood oceans/rivers into caves
	if y < core_top_y - 18.0:
		strength *= smoothstep(core_top_y - 40.0, core_top_y - 18.0, y)
	if strength <= 0.0:
		return -1.0
	# BG cave curve idea: tunnels at the zero-surfaces of two 3D noises,
	# width grows with depth (easy→hard cave cells simplified to a depth ramp).
	var w := 0.055 + 0.075 * clampf(depth / 260.0, 0.0, 1.0)
	var tunnel := minf(w - absf(c1), w * 1.1 - absf(c2))
	var cavern := (cheese - (0.60 if depth > 60.0 else 0.66)) * 0.5
	return maxf(tunnel * 60.0, cavern * 90.0) * strength


func _material_at(y: float, col: Dictionary, surf: Dictionary,
		pocket: float, pocket2: float, strata: float) -> int:
	var depth: float = col["h"] - y
	if depth < 1.4 + strata * 0.3:
		if y > float(surf["snow_y"]) and not bool(surf.get("mesa", false)):
			return R.SNOW
		return int(surf["surf_ch"])
	if depth < float(surf["dirt_depth"]):
		return int(surf["dirt_ch"])
	# --- rock zone ---
	if y < core_top_y + 10.0 + strata * 8.0:
		return R.DEEPSLATE                             # dark sheath around The Core
	var stripe_band := sin((y + strata * 26.0) * 0.16)
	if (float(col["mount"]) > 0.30 or bool(surf.get("mesa", false))) and stripe_band > 0.62:
		return R.TERRACOTTA                            # BG rock_stripes / mesa banding
	if pocket > 0.60:
		return R.GRANITE
	if pocket < -0.60:
		return R.DIORITE
	if pocket2 > 0.64:
		return R.ANDESITE
	if pocket2 < -0.64:
		return R.TUFF
	if absf(pocket) < 0.035 and y < -20.0:
		return R.CALCITE
	if y < -64.0 + strata * 14.0:
		return R.DEEPSLATE                             # BG deepslate blend boundary
	return R.STONE


static func pack_single_index(i: int) -> int:
	return (i & 15) | (((i + 1) & 15) << 4) | (((i + 2) & 15) << 8) | (((i + 3) & 15) << 12)


## --- Features (trees / boulders) ------------------------------------------------

const FEATURE_CELL := 16

func _cell_rand(cx: int, cz: int, salt: int) -> float:
	var h := hash(Vector3i(cx, salt, cz) + Vector3i.ONE * (world_seed & 0xFFFF))
	return float(h & 0xFFFFFF) / float(0xFFFFFF)


## Deterministic features whose AABB intersects the given XZ rect (world meters).
func features_in_rect(x0: float, z0: float, x1: float, z1: float, cache: Dictionary) -> Array:
	var out: Array = []
	var c0x := floori((x0 - 8.0) / FEATURE_CELL)
	var c1x := floori((x1 + 8.0) / FEATURE_CELL)
	var c0z := floori((z0 - 8.0) / FEATURE_CELL)
	var c1z := floori((z1 + 8.0) / FEATURE_CELL)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			var f := _cell_feature(cx, cz, cache)
			if not f.is_empty():
				out.append(f)
	return out


func _cell_feature(cx: int, cz: int, cache: Dictionary) -> Dictionary:
	var roll := _cell_rand(cx, cz, 1)
	var is_tree := roll < 0.34
	var is_boulder := roll >= 0.90
	if not is_tree and not is_boulder:
		return {}
	var wx := cx * FEATURE_CELL + 3 + int(_cell_rand(cx, cz, 2) * 10.0)
	var wz := cz * FEATURE_CELL + 3 + int(_cell_rand(cx, cz, 3) * 10.0)
	var col := column(wx, wz, cache)
	var h: float = col["h"]
	if col["water_y"] != NO_WATER or h <= sea_level + 2.0:
		return {}
	var surf := surface_info(wx, wz, col, cache)
	var ch := int(surf["surf_ch"])
	if is_tree:
		if ch != R.GRASS and ch != R.MOSS:
			return {}
		if float(surf["grad"]) > 0.55:
			return {}
		var trunk_h := 6.0 + _cell_rand(cx, cz, 4) * 5.0
		return {
			"type": "tree", "pos": Vector3(wx, h, wz), "trunk_h": trunk_h,
			"trunk_r": 0.55 + _cell_rand(cx, cz, 5) * 0.4,
			"canopy_r": 2.6 + _cell_rand(cx, cz, 6) * 2.0,
			"canopy_ry": 2.0 + _cell_rand(cx, cz, 7) * 1.4,
			"top": h + trunk_h + 1.2 + 2.0 + _cell_rand(cx, cz, 7) * 1.4,
		}
	# boulder
	if ch == R.SNOW or float(surf["grad"]) > 1.4:
		return {}
	var r := 1.4 + _cell_rand(cx, cz, 8) * 1.4
	return {
		"type": "boulder", "pos": Vector3(wx, h - r * 0.35, wz), "r": r,
		"ch": R.GRANITE if _cell_rand(cx, cz, 9) < 0.5 else R.ANDESITE,
		"top": h - r * 0.35 + r,
	}


## SDF + material of a feature at a point. Returns {sdf, ch}; sdf > 900 = far.
func _feature_sample(f: Dictionary, p: Vector3) -> Dictionary:
	var pos: Vector3 = f["pos"]
	if f["type"] == "boulder":
		return {"sdf": p.distance_to(pos) - float(f["r"]), "ch": int(f["ch"])}
	# tree: trunk capsule + canopy ellipsoid
	var trunk_h: float = f["trunk_h"]
	var ty := clampf(p.y, pos.y - 1.0, pos.y + trunk_h)
	var trunk := Vector2(Vector2(p.x - pos.x, p.z - pos.z).length(), p.y - ty).length() \
			- float(f["trunk_r"])
	var cc := pos + Vector3(0, trunk_h + 1.2, 0)
	var cr: float = f["canopy_r"]
	var cry: float = f["canopy_ry"]
	var d := Vector3((p.x - cc.x) / cr, (p.y - cc.y) / cry, (p.z - cc.z) / cr)
	var canopy := (d.length() - 1.0) * minf(cr, cry)
	if trunk < canopy:
		return {"sdf": trunk, "ch": R.WOOD}
	return {"sdf": canopy, "ch": R.LEAVES}


## --- Block filling (shared by baker + live generator) ---------------------------

## Fills a 16³ voxel buffer (duck-typed) at origin (LOD0 voxel coords), lod N.
func fill_block(buffer: Variant, origin: Vector3i, lod: int, cache: Dictionary) -> void:
	var step := 1 << lod
	var block_bottom := float(origin.y)
	var block_top := float(origin.y + BLOCK_SIZE * step)

	# Whole block below the bedrock floor → uniform solid stone, done.
	if block_top <= float(y_min) + 3.0:
		buffer.fill_f(-1.0, CH_SDF)
		buffer.fill(pack_single_index(R.STONE), CH_INDICES)
		buffer.fill(WEIGHTS_SINGLE_PACKED, CH_WEIGHTS)
		return

	# Column pass over the block footprint.
	var cols: Array = []
	cols.resize(BLOCK_SIZE * BLOCK_SIZE)
	var max_h := -1.0e12
	var min_h := 1.0e12
	for k in BLOCK_SIZE:
		var wz := origin.z + k * step
		for i in BLOCK_SIZE:
			var col := column(origin.x + i * step, wz, cache)
			cols[k * BLOCK_SIZE + i] = col
			max_h = maxf(max_h, col["h"])
			min_h = minf(min_h, col["h"])

	# Features only matter at fine LODs and near the surface band.
	var feats: Array = []
	if lod <= 1 and block_top > min_h - 2.0 and block_bottom < max_h + 20.0:
		feats = features_in_rect(origin.x, origin.z,
				origin.x + BLOCK_SIZE * step, origin.z + BLOCK_SIZE * step, cache)
	var top_needed := max_h + 2.0 * step
	for f: Dictionary in feats:
		top_needed = maxf(top_needed, float(f["top"]) + 2.0 * step)

	# Whole block is open air → uniform, done.
	if block_bottom > top_needed:
		buffer.fill_f(1.0, CH_SDF)
		return

	# Mixed block: prefill, then walk columns.
	buffer.fill_f(1.0, CH_SDF)
	buffer.fill(pack_single_index(R.STONE), CH_INDICES)
	buffer.fill(WEIGHTS_SINGLE_PACKED, CH_WEIGHTS)

	# 3D noise lattice (stride 4 cells), trilinearly interpolated per voxel.
	var lat_step := 4 * step
	var l_c1 := PackedFloat32Array(); l_c1.resize(LATTICE_N * LATTICE_N * LATTICE_N)
	var l_c2 := PackedFloat32Array(); l_c2.resize(l_c1.size())
	var l_cheese := PackedFloat32Array(); l_cheese.resize(l_c1.size())
	var l_pocket := PackedFloat32Array(); l_pocket.resize(l_c1.size())
	var l_pocket2 := PackedFloat32Array(); l_pocket2.resize(l_c1.size())
	var l_strata := PackedFloat32Array(); l_strata.resize(l_c1.size())
	var idx := 0
	for lj in LATTICE_N:
		var ly := origin.y + lj * lat_step
		for lk in LATTICE_N:
			var lz := origin.z + lk * lat_step
			for li in LATTICE_N:
				var lx := origin.x + li * lat_step
				l_c1[idx] = _n_cave1.get_noise_3d(lx, ly, lz)
				l_c2[idx] = _n_cave2.get_noise_3d(lx, ly, lz)
				l_cheese[idx] = _n_cheese.get_noise_3d(lx, ly, lz)
				l_pocket[idx] = _n_pocket.get_noise_3d(lx, ly, lz)
				l_pocket2[idx] = _n_pocket2.get_noise_3d(lx, ly, lz)
				l_strata[idx] = _n_strata.get_noise_3d(lx, ly, lz)
				idx += 1

	var inv_sdf_scale := 1.0 / (10.0 * float(step))
	var bedrock_y := float(y_min) + 2.0

	for k in BLOCK_SIZE:
		for i in BLOCK_SIZE:
			var col: Dictionary = cols[k * BLOCK_SIZE + i]
			var h: float = col["h"]
			var wx := origin.x + i * step
			var wz := origin.z + k * step
			var col_top := h + 2.0 * step
			var col_feats: Array = []
			for f: Dictionary in feats:
				var fp: Vector3 = f["pos"]
				var fr := 8.0 if f["type"] == "tree" else 3.5
				if absf(fp.x - wx) <= fr and absf(fp.z - wz) <= fr:
					col_feats.append(f)
					col_top = maxf(col_top, float(f["top"]) + 2.0 * step)
			var j_top := clampi(ceili((col_top - block_bottom) / step), 0, BLOCK_SIZE)
			if j_top <= 0:
				continue
			var surf: Dictionary = {}
			if h >= block_bottom - float(surf_probe_margin(step)):
				surf = surface_info(wx, wz, col, cache)

			for j in j_top:
				var y := block_bottom + j * step
				var fi := float(i) * 0.25
				var fj := float(j) * 0.25
				var fk := float(k) * 0.25
				var sdf_m := y - h
				var mat := -1

				if sdf_m < 2.0 * step:                 # below/near terrain surface
					var c1 := _trilerp(l_c1, fi, fj, fk)
					var c2 := _trilerp(l_c2, fi, fj, fk)
					var cheese := _trilerp(l_cheese, fi, fj, fk)
					var cave := _cave_value(y, col, c1, c2, cheese)
					sdf_m = maxf(sdf_m, cave)
					if sdf_m < 0.5:                     # solid-ish → needs a material
						var pocket := _trilerp(l_pocket, fi, fj, fk)
						var pocket2 := _trilerp(l_pocket2, fi, fj, fk)
						var strata := _trilerp(l_strata, fi, fj, fk)
						if surf.is_empty():
							surf = surface_info(wx, wz, col, cache)
						mat = _material_at(y, col, surf, pocket, pocket2, strata)

				for f: Dictionary in col_feats:
					var fs := _feature_sample(f, Vector3(wx, y, wz))
					if float(fs["sdf"]) < sdf_m:
						sdf_m = float(fs["sdf"])
						if sdf_m < 0.6:
							mat = int(fs["ch"])

				sdf_m = minf(sdf_m, y - bedrock_y)      # unbreakable world floor
				buffer.set_voxel_f(clampf(sdf_m * inv_sdf_scale, -1.0, 1.0), i, j, k, CH_SDF)
				if mat >= 0 and mat != R.STONE:
					buffer.set_voxel(pack_single_index(mat), i, j, k, CH_INDICES)

	buffer.compress_uniform_channels()


static func surf_probe_margin(step: int) -> int:
	return 24 * step


func _trilerp(a: PackedFloat32Array, fi: float, fj: float, fk: float) -> float:
	var i0 := int(fi)
	var j0 := int(fj)
	var k0 := int(fk)
	var i1 := mini(i0 + 1, LATTICE_N - 1)
	var j1 := mini(j0 + 1, LATTICE_N - 1)
	var k1 := mini(k0 + 1, LATTICE_N - 1)
	var ti := fi - i0
	var tj := fj - j0
	var tk := fk - k0
	var n := LATTICE_N
	var nn := n * n
	var c00 := lerpf(a[j0 * nn + k0 * n + i0], a[j0 * nn + k0 * n + i1], ti)
	var c01 := lerpf(a[j0 * nn + k1 * n + i0], a[j0 * nn + k1 * n + i1], ti)
	var c10 := lerpf(a[j1 * nn + k0 * n + i0], a[j1 * nn + k0 * n + i1], ti)
	var c11 := lerpf(a[j1 * nn + k1 * n + i0], a[j1 * nn + k1 * n + i1], ti)
	return lerpf(lerpf(c00, c01, tk), lerpf(c10, c11, tk), tj)


## --- Bake-support queries --------------------------------------------------------

## Finds a pleasant spawn: flat grass, no river/ocean, near origin.
func find_spawn(cache: Dictionary) -> Vector3:
	var best := Vector3(0, 60, 0)
	for ring in range(0, 960, 8):
		for a in range(0, 360, 20):
			var wx := int(ring * cos(deg_to_rad(a)))
			var wz := int(ring * sin(deg_to_rad(a)))
			var col := column(wx, wz, cache)
			if col["water_y"] != NO_WATER:
				continue
			if float(col["h"]) < sea_level + 3.0 or float(col["river_t"]) > 0.25:
				continue
			var surf := surface_info(wx, wz, col, cache)
			if float(surf["grad"]) > 0.45:
				continue
			return Vector3(wx, float(col["h"]) + 1.0, wz)
	return best


## Water tiles for the runtime visual planes: [[x, z, size, y], ...] on a 32m grid.
func water_tiles(cache: Dictionary) -> Array:
	var tiles: Array = []
	const TILE := 32
	var half_x := size_x / 2
	var half_z := size_z / 2
	for wz in range(-half_z, half_z, TILE):
		for wx in range(-half_x, half_x, TILE):
			var col := column(wx + TILE / 2, wz + TILE / 2, cache)
			var wy: float = col["water_y"]
			if wy != NO_WATER:
				tiles.append([wx, wz, TILE, wy + 0.15])
	return tiles
