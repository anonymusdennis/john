class_name TerrainModel
extends RefCounted
## TerrainModel — steered fantasy world model for the voxel platform.
##
## Replaces the old Big Globe / "imitate Minecraft" noise stack with a
## DESIGNED macro layout (Skyrim-like hold): every large-scale decision is
## steered, not emergent:
##
##   hub vale ......... a perfectly flat meadow disc around the origin that
##                      holds the playground/plaza — gameplay-safe by design
##   mountain ring .... ridged, domain-warped ranges that rise with distance
##                      from the vale, like the ranges walling a Skyrim hold
##   passes ........... corridor field whose zero-lines suppress the ranges,
##                      guaranteeing walkable routes between regions
##   benches .......... soft terracing on mountainsides — ledges, shoulders
##                      and shelves (natural "nooks and crannies")
##   glades ........... deterministic flat clearings scattered through the
##                      wilds; intentionally EMPTY — mapper-ready spots, no
##                      fabricated places
##   lake basins ...... bowls pressed into the lowlands; water only where
##                      the land genuinely dips below sea level
##   crags ............ slope-gated 3D displacement that breaks steep faces
##                      into overhangs and crevices — WITHOUT any cave tunnels
##   bedrock floor .... shallow world (no more -512 pit); an unbreakable
##                      deepslate slab a few meters under the deepest basin
##
## No caves. No ores. Trees are NOT carved into the voxels anymore — the
## model only *places* them (surface_features) and scripts/voxel/vegetation.gd
## instances real meshes. Boulders remain part of the terrain SDF (they are
## rock). Output is smooth SDF + Mixel4 material indices.
##
## Pure math + FastNoiseLite: parses on stock Godot. Voxel buffers are passed
## in as Variant and written via duck typing, so this file never references
## godot_voxel classes. Used by the offline baker (tools/worldgen/
## bake_world.gd), the dev live generator (tools/worldgen/terrain_generator.gd)
## and at runtime by VoxelWorld for spawns, vegetation and nav bounds.

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
var y_min: int = -80                    # Shallow world — bedrock right below.
var y_max: int = 320                    # Tall Skyrim-like peaks.
var sea_level: float = -6.0             # Lakes only in genuine basins.
var mountain_amp: float = 235.0         # Ridge height over the wilds.
var hill_amp: float = 24.0              # Rolling valley relief.
var vale_flat_radius: float = 195.0     # Hub meadow: perfectly flat inside.
var vale_blend_radius: float = 290.0    # …blends into the wilds by here.
var vale_height: float = 0.0            # Hub meadow elevation.

# Derived (recomputed by configure()).
var bedrock_top_y: float = -77.0        # Unbreakable slab surface.
var floor_clamp_y: float = -60.0        # Terrain never dips below this.

# --- Noise fields --------------------------------------------------------------
var _n_ridge: FastNoiseLite             # Ridged mountain crests.
var _n_range: FastNoiseLite             # Which areas carry ranges at all.
var _n_pass: FastNoiseLite              # Zero-lines = mountain passes.
var _n_hills: FastNoiseLite             # Valley rolling hills.
var _n_detail: FastNoiseLite            # Small nooks / surface break-up.
var _n_warp_x: FastNoiseLite            # Domain warp (natural, uneven shapes).
var _n_warp_z: FastNoiseLite
var _n_moist: FastNoiseLite             # Moisture — forests, moss, snowline.
var _n_temp: FastNoiseLite              # Temperature — snowline jitter.
var _n_basin: FastNoiseLite             # Lake bowls in the lowlands.
var _n_crag: FastNoiseLite              # 3D: cliff crags / overhangs.
var _n_pocket: FastNoiseLite            # 3D: rock variety pockets.
var _n_strata: FastNoiseLite            # 3D: strata wobble.


func _init() -> void:
	configure({})


func configure(cfg: Dictionary) -> void:
	world_seed = int(cfg.get("seed", world_seed))
	size_x = int(cfg.get("size_x", size_x))
	size_z = int(cfg.get("size_z", size_z))
	y_min = int(cfg.get("y_min", y_min))
	y_max = int(cfg.get("y_max", y_max))
	sea_level = float(cfg.get("sea_level", sea_level))
	mountain_amp = float(cfg.get("mountain_amp", mountain_amp))
	hill_amp = float(cfg.get("hill_amp", hill_amp))
	vale_flat_radius = float(cfg.get("vale_flat_radius", vale_flat_radius))
	vale_blend_radius = float(cfg.get("vale_blend_radius", vale_blend_radius))
	vale_height = float(cfg.get("vale_height", vale_height))

	bedrock_top_y = float(y_min) + 3.0
	floor_clamp_y = bedrock_top_y + 14.0

	_n_ridge = _fbm(1, 4, 830.0, 0.48)
	_n_range = _fbm(2, 2, 1500.0, 0.5)
	_n_pass = _fbm(3, 2, 1100.0, 0.5)
	_n_hills = _fbm(4, 4, 420.0, 0.5)
	_n_detail = _fbm(5, 3, 64.0, 0.55)
	_n_warp_x = _fbm(6, 2, 640.0, 0.5)
	_n_warp_z = _fbm(7, 2, 640.0, 0.5)
	_n_moist = _fbm(8, 3, 1400.0, 0.5)
	_n_temp = _fbm(9, 3, 1700.0, 0.5)
	_n_basin = _fbm(10, 2, 720.0, 0.5)
	_n_crag = _fbm(11, 2, 30.0, 0.5)
	_n_pocket = _fbm(12, 1, 85.0, 0.5)
	_n_strata = _fbm(13, 1, 38.0, 0.5)


## The full model config — baked into world_meta.json so the runtime can
## reconstruct this exact model for vegetation/spawn/nav queries.
func config_dict() -> Dictionary:
	return {
		"seed": world_seed, "size_x": size_x, "size_z": size_z,
		"y_min": y_min, "y_max": y_max, "sea_level": sea_level,
		"mountain_amp": mountain_amp, "hill_amp": hill_amp,
		"vale_flat_radius": vale_flat_radius,
		"vale_blend_radius": vale_blend_radius, "vale_height": vale_height,
	}


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


## --- Height stack (the steered part) -------------------------------------------

## 0 in the hub vale (perfectly flat), 1 in the wilds.
func wildness(wx: float, wz: float) -> float:
	var d := Vector2(wx, wz).length()
	return smoothstep(vale_flat_radius, vale_blend_radius, d)


## Raw wilderness height (before glade flattening / vale blending).
func _wild_height(wx: float, wz: float) -> float:
	var d := Vector2(wx, wz).length()
	# Domain warp keeps ranges organic instead of noise-blobby.
	var wxw := wx + _n_warp_x.get_noise_2d(wx, wz) * 110.0
	var wzw := wz + _n_warp_z.get_noise_2d(wx, wz) * 110.0

	# STEERED range mask: mountains strengthen with distance from the vale
	# (the "hold ringed by ranges" layout) and with the range noise, so some
	# sectors are dominated by peaks and others stay open highland.
	var ring := clampf((d - vale_flat_radius) / 620.0, 0.0, 1.0)
	var range_n := _n_range.get_noise_2d(wxw, wzw) * 0.5 + 0.5
	var range_mask := clampf(ring * 0.62 + range_n * 0.58, 0.0, 1.0)
	range_mask = pow(range_mask, 1.7)

	# STEERED passes: corridors along the zero-lines of the pass field cut
	# through the ranges, guaranteeing walkable routes between regions.
	var pass_t := smoothstep(0.05, 0.28, absf(_n_pass.get_noise_2d(wxw, wzw)))
	range_mask *= 0.22 + 0.78 * pass_t

	# Ridged crests (1-|n|), sharpened — long crest lines, not round bumps.
	var ridge := 1.0 - absf(_n_ridge.get_noise_2d(wxw, wzw))
	ridge = pow(clampf(ridge, 0.0, 1.0), 2.1)
	var mount := ridge * range_mask * mountain_amp

	# Benches: soft terracing on the flanks — shelves and shoulders to stand
	# on (and for mappers to use). Fades out on flats and on knife crests.
	if mount > 8.0:
		var band := 26.0
		var t := mount / band
		var frac := t - floorf(t)
		var soft := frac * frac * (3.0 - 2.0 * frac)
		var bench_mix := smoothstep(8.0, 40.0, mount) * (1.0 - smoothstep(0.75, 0.95, ridge))
		mount = lerpf(mount, (floorf(t) + soft) * band, bench_mix * 0.55)

	# Rolling valley hills, damped where mountains dominate.
	var hills := _n_hills.get_noise_2d(wxw, wzw) * hill_amp * (1.0 - range_mask * 0.72)

	# Lake basins pressed into the lowlands only.
	var basin := smoothstep(0.42, 0.78, _n_basin.get_noise_2d(wxw, wzw)) \
			* (1.0 - smoothstep(0.15, 0.45, range_mask))
	var bowls := -basin * 26.0

	# Small-scale nooks: stronger in the wilds and on relief, silent in flats.
	var detail := _n_detail.get_noise_2d(wx, wz) * (1.2 + 5.2 * range_mask + basin * 2.0)

	var h := 6.0 + hills + mount + bowls + detail
	return clampf(h, floor_clamp_y, float(y_max) - 8.0)


## Height including vale + glade steering. Cached per column.
func height_at(wx: float, wz: float, cache: Dictionary) -> float:
	var key := Vector3i(int(floor(wx)), 7, int(floor(wz)))
	var hit: Variant = cache.get(key)
	if hit != null:
		return hit
	var wild := wildness(wx, wz)
	var h := vale_height
	if wild > 0.0:
		h = lerpf(vale_height, _wild_height(wx, wz), wild)
		# Glades: flatten toward the clearing's center height.
		var g := _glade_at(wx, wz, cache)
		if g["w"] > 0.0:
			h = lerpf(h, float(g["h"]), float(g["w"]))
	cache[key] = h
	return h


## --- Glades (mapper-ready flat clearings; deliberately left empty) -------------

const GLADE_CELL := 96

## Returns {w: blend weight 0..1, h: glade floor height} for this position.
func _glade_at(wx: float, wz: float, cache: Dictionary) -> Dictionary:
	var best_w := 0.0
	var best_h := 0.0
	var gx := floori(wx / GLADE_CELL)
	var gz := floori(wz / GLADE_CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var g := _glade_cell(gx + dx, gz + dz, cache)
			if g.is_empty():
				continue
			var c: Vector2 = g["center"]
			var r: float = g["r"]
			var dist := Vector2(wx - c.x, wz - c.y).length()
			if dist >= r:
				continue
			var w := 1.0 - smoothstep(r * 0.45, r, dist)
			if w > best_w:
				best_w = w
				best_h = g["h"]
	return {"w": best_w, "h": best_h}


func _glade_cell(cx: int, cz: int, cache: Dictionary) -> Dictionary:
	var key := Vector3i(cx, 11, cz)
	var hit: Variant = cache.get(key)
	if hit != null:
		return hit
	var out := {}
	if _cell_rand(cx, cz, 40) < 0.30:
		var px := cx * GLADE_CELL + 18.0 + _cell_rand(cx, cz, 41) * (GLADE_CELL - 36.0)
		var pz := cz * GLADE_CELL + 18.0 + _cell_rand(cx, cz, 42) * (GLADE_CELL - 36.0)
		# Only in the true wilds (never nibbling at the hub's blend ring).
		if wildness(px, pz) >= 0.999:
			var ch := _wild_height(px, pz)
			if ch > sea_level + 2.0:   # Never flatten a clearing into a lake.
				out = {
					"center": Vector2(px, pz),
					"r": 13.0 + _cell_rand(cx, cz, 43) * 9.0,
					"h": ch,
				}
	cache[key] = out
	return out


## --- Column stack ----------------------------------------------------------------

## Cheap column: height + hydrology. cache keys are Vector2i world coords.
func column(wx: int, wz: int, cache: Dictionary) -> Dictionary:
	var key := Vector2i(wx, wz)
	var hit: Variant = cache.get(key)
	if hit != null:
		return hit

	var h := height_at(wx, wz, cache)
	var water_y := NO_WATER
	if h <= sea_level + 0.5:
		water_y = sea_level

	var col := {"h": h, "water_y": water_y, "surf": {}}
	cache[key] = col
	return col


## Climate + surface materials, computed lazily (only for near-surface voxels).
func surface_info(wx: int, wz: int, col: Dictionary, cache: Dictionary) -> Dictionary:
	var surf: Dictionary = col["surf"]
	if not surf.is_empty():
		return surf

	var h: float = col["h"]
	var temp := _n_temp.get_noise_2d(wx, wz) - maxf(h, 0.0) * 0.0036   # colder up high
	var moist := _n_moist.get_noise_2d(wx, wz)
	# hilliness ~ |grad(height)| via cheap finite differences (glade-aware).
	var he := height_at(wx + 3, wz, cache)
	var hw := height_at(wx - 3, wz, cache)
	var hn := height_at(wx, wz + 3, cache)
	var hs := height_at(wx, wz - 3, cache)
	var grad := Vector2((he - hw) / 6.0, (hn - hs) / 6.0).length()

	var snow_y := 132.0 + temp * 90.0 + moist * -18.0   # wetter+colder → lower snowline
	var underwater: bool = col["water_y"] != NO_WATER and col["water_y"] > h

	var surf_ch := R.GRASS
	if underwater:
		surf_ch = R.SAND if h > sea_level - 7.0 else R.GRAVEL
	elif grad > 1.35:
		surf_ch = R.STONE                              # sheer cliff faces
	elif grad > 0.85:
		surf_ch = R.GRAVEL                             # scree / talus slopes
	elif h > snow_y or temp < -0.62:
		surf_ch = R.SNOW
	elif h > snow_y - 26.0 and grad > 0.55:
		surf_ch = R.GRAVEL                             # frost-shattered shoulder
	elif moist > 0.42 and h < 70.0:
		surf_ch = R.MOSS                               # damp lowland forest floor
	elif h < sea_level + 2.2 and h > sea_level - 0.5:
		surf_ch = R.SAND                               # lake shores
	elif moist < -0.52 and h < 40.0:
		surf_ch = R.DIRT                               # parched flats
	var dirt_ch := R.DIRT
	if surf_ch == R.SAND:
		dirt_ch = R.SAND

	surf = {
		"temp": temp, "moist": moist, "grad": grad, "snow_y": snow_y,
		"surf_ch": surf_ch, "dirt_ch": dirt_ch,
		"dirt_depth": 1.4 + clampf(4.0 - grad * 2.0, 0.5, 4.0),
	}
	col["surf"] = surf
	return surf


## One-call surface sample for vegetation / gameplay queries (continuous coords).
## Returns {h, grad, surf_ch, water_y, moist, wild}.
func sample_surface(wxf: float, wzf: float, cache: Dictionary) -> Dictionary:
	var wx := int(floorf(wxf))
	var wz := int(floorf(wzf))
	var col := column(wx, wz, cache)
	var surf := surface_info(wx, wz, col, cache)
	return {
		"h": col["h"], "grad": surf["grad"], "surf_ch": surf["surf_ch"],
		"water_y": col["water_y"], "moist": surf["moist"],
		"wild": wildness(wxf, wzf),
	}


## --- Per-voxel material ----------------------------------------------------------

func _material_at(y: float, col: Dictionary, surf: Dictionary,
		pocket: float, strata: float) -> int:
	if y <= bedrock_top_y + 1.0 + strata * 0.5:
		return R.DEEPSLATE                             # the unbreakable slab
	var depth: float = col["h"] - y
	if depth < 1.4 + strata * 0.3:
		return int(surf["surf_ch"])
	if depth < float(surf["dirt_depth"]):
		return int(surf["dirt_ch"])
	# --- rock zone ---
	var stripe_band := sin((y + strata * 22.0) * 0.14)
	if float(surf["grad"]) > 1.05 and stripe_band > 0.66:
		return R.TERRACOTTA                            # strata bands on cliff faces
	if pocket > 0.62:
		return R.GRANITE
	if pocket < -0.62:
		return R.DIORITE
	if absf(pocket) < 0.05 and depth > 12.0:
		return R.CALCITE                               # pale veins deep in the rock
	if depth > 26.0 and pocket > 0.2:
		return R.ANDESITE
	if depth > 26.0 and pocket < -0.2:
		return R.TUFF
	if y < bedrock_top_y + 14.0 + strata * 6.0:
		return R.DEEPSLATE                             # transition to the slab
	return R.STONE


static func pack_single_index(i: int) -> int:
	return (i & 15) | (((i + 1) & 15) << 4) | (((i + 2) & 15) << 8) | (((i + 3) & 15) << 12)


## --- Surface features (trees for vegetation.gd, boulders for the SDF) -----------

const FEATURE_CELL := 12

func _cell_rand(cx: int, cz: int, salt: int) -> float:
	var h := hash(Vector3i(cx, salt, cz) + Vector3i.ONE * (world_seed & 0xFFFF))
	return float(h & 0xFFFFFF) / float(0xFFFFFF)


## Deterministic features whose footprint intersects the given XZ rect (meters).
## kinds: "boulder" (part of the terrain SDF) and "tree_oak"/"tree_pine"
## (NOT carved — instanced as real meshes by vegetation.gd).
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
	if roll >= 0.5:
		return {}
	var wx := cx * FEATURE_CELL + 2 + int(_cell_rand(cx, cz, 2) * 8.0)
	var wz := cz * FEATURE_CELL + 2 + int(_cell_rand(cx, cz, 3) * 8.0)
	var wild := wildness(wx, wz)
	if wild < 0.55:
		return {}                                      # hub + blend ring stay open
	var col := column(wx, wz, cache)
	var h: float = col["h"]
	if col["water_y"] != NO_WATER or h <= sea_level + 1.5:
		return {}
	var surf := surface_info(wx, wz, col, cache)
	var grad := float(surf["grad"])
	var ch := int(surf["surf_ch"])
	var moist := float(surf["moist"])

	# Boulders: rocky outcrops everywhere but sheer walls.
	if roll >= 0.44:
		if grad > 1.4 or ch == R.SAND:
			return {}
		var r := 1.3 + _cell_rand(cx, cz, 8) * 1.5
		return {
			"type": "boulder", "pos": Vector3(wx, h - r * 0.35, wz), "r": r,
			"top": h - r * 0.35 + r,
		}

	# Broadleaf woods: damp lowland valleys.
	var forest := smoothstep(-0.25, 0.45, moist)
	if (ch == R.GRASS or ch == R.MOSS) and h < 72.0 and grad < 0.55:
		if roll < 0.34 * forest:
			return {
				"type": "tree_oak", "pos": Vector3(wx, h, wz),
				"scale": 0.85 + _cell_rand(cx, cz, 5) * 0.55,
				"variant": mini(int(_cell_rand(cx, cz, 6) * 4.0), 3),
			}
		return {}

	# Pines: highland shoulders and mountainsides below the snowline.
	if h >= 24.0 and h < float(surf["snow_y"]) - 6.0 and grad < 0.95 \
			and ch != R.SNOW and ch != R.SAND and ch != R.STONE:
		if roll < 0.30:
			return {
				"type": "tree_pine", "pos": Vector3(wx, h, wz),
				"scale": 0.8 + _cell_rand(cx, cz, 5) * 0.6,
				"variant": mini(int(_cell_rand(cx, cz, 6) * 4.0), 3),
			}
	return {}


## Tree placements only (for vegetation.gd) inside an XZ rect.
func trees_in_rect(x0: float, z0: float, x1: float, z1: float, cache: Dictionary) -> Array:
	var out: Array = []
	for f: Dictionary in features_in_rect(x0, z0, x1, z1, cache):
		if String(f["type"]).begins_with("tree_"):
			out.append(f)
	return out


## SDF of a boulder at a point.
func _boulder_sdf(f: Dictionary, p: Vector3) -> float:
	return p.distance_to(f["pos"]) - float(f["r"])


## --- Block filling (shared by baker + live generator) ---------------------------

## Fills a 16³ voxel buffer (duck-typed) at origin (LOD0 voxel coords), lod N.
func fill_block(buffer: Variant, origin: Vector3i, lod: int, cache: Dictionary) -> void:
	var step := 1 << lod
	var block_bottom := float(origin.y)
	var block_top := float(origin.y + BLOCK_SIZE * step)

	# Whole block inside the bedrock slab → uniform solid deepslate, done.
	if block_top <= bedrock_top_y:
		buffer.fill_f(-1.0, CH_SDF)
		buffer.fill(pack_single_index(R.DEEPSLATE), CH_INDICES)
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

	# Whole block deep inside solid ground → every SDF sample clamps to -1
	# (|y - h| ≥ 10·step, past crag/boulder reach) so no isosurface can cross
	# it. LOD 1+ blocks are never mined, so a uniform rock fill is exact and
	# skips the whole per-voxel walk. LOD 0 keeps full materials for mining.
	if lod >= 1 and block_top <= min_h - 10.0 * float(step):
		buffer.fill_f(-1.0, CH_SDF)
		buffer.fill(pack_single_index(R.STONE), CH_INDICES)
		buffer.fill(WEIGHTS_SINGLE_PACKED, CH_WEIGHTS)
		return

	# Boulders only matter at fine LODs and near the surface band.
	var feats: Array = []
	if lod <= 1 and block_top > min_h - 2.0 and block_bottom < max_h + 8.0:
		for f: Dictionary in features_in_rect(origin.x, origin.z,
				origin.x + BLOCK_SIZE * step, origin.z + BLOCK_SIZE * step, cache):
			if f["type"] == "boulder":
				feats.append(f)
	# Crag displacement is sub-voxel past LOD 1 — there it only aliases the
	# distant meshes while costing a full 3D-noise lattice, so gate it off.
	var crags_on := lod <= 1
	var crag_amp := 2.6 if crags_on else 0.0
	var top_needed := max_h + crag_amp + 2.0 * step
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
	var l_crag := PackedFloat32Array()
	if crags_on:
		l_crag.resize(LATTICE_N * LATTICE_N * LATTICE_N)
	var l_pocket := PackedFloat32Array(); l_pocket.resize(LATTICE_N * LATTICE_N * LATTICE_N)
	var l_strata := PackedFloat32Array(); l_strata.resize(l_pocket.size())
	var idx := 0
	for lj in LATTICE_N:
		var ly := origin.y + lj * lat_step
		for lk in LATTICE_N:
			var lz := origin.z + lk * lat_step
			for li in LATTICE_N:
				var lx := origin.x + li * lat_step
				if crags_on:
					l_crag[idx] = _n_crag.get_noise_3d(lx, ly, lz)
				l_pocket[idx] = _n_pocket.get_noise_3d(lx, ly, lz)
				l_strata[idx] = _n_strata.get_noise_3d(lx, ly, lz)
				idx += 1

	var inv_sdf_scale := 1.0 / (10.0 * float(step))

	for k in BLOCK_SIZE:
		for i in BLOCK_SIZE:
			var col: Dictionary = cols[k * BLOCK_SIZE + i]
			var h: float = col["h"]
			var wx := origin.x + i * step
			var wz := origin.z + k * step
			var col_top := h + crag_amp + 2.0 * step
			var col_feats: Array = []
			for f: Dictionary in feats:
				var fp: Vector3 = f["pos"]
				if absf(fp.x - wx) <= 3.5 and absf(fp.z - wz) <= 3.5:
					col_feats.append(f)
					col_top = maxf(col_top, float(f["top"]) + 2.0 * step)
			var j_top := clampi(ceili((col_top - block_bottom) / step), 0, BLOCK_SIZE)
			if j_top <= 0:
				continue
			var surf: Dictionary = {}
			if h >= block_bottom - float(surf_probe_margin(step)):
				surf = surface_info(wx, wz, col, cache)
			# Crags only on steep wild faces — flats and the vale stay clean
			# so navigation and building keep working.
			var crag_gate := 0.0
			if crags_on and not surf.is_empty():
				crag_gate = smoothstep(0.7, 1.3, float(surf["grad"])) \
						* wildness(wx, wz) * crag_amp

			for j in j_top:
				var y := block_bottom + j * step
				var fi := float(i) * 0.25
				var fj := float(j) * 0.25
				var fk := float(k) * 0.25
				var sdf_m := y - h
				var mat := -1

				if sdf_m < crag_amp + 2.0 * step:      # below/near terrain surface
					if crag_gate > 0.01 and absf(sdf_m) < 7.0:
						sdf_m += _trilerp(l_crag, fi, fj, fk) * crag_gate
					if sdf_m < 0.5:                     # solid-ish → needs a material
						var pocket := _trilerp(l_pocket, fi, fj, fk)
						var strata := _trilerp(l_strata, fi, fj, fk)
						if surf.is_empty():
							surf = surface_info(wx, wz, col, cache)
						mat = _material_at(y, col, surf, pocket, strata)

				for f: Dictionary in col_feats:
					var bs := _boulder_sdf(f, Vector3(wx, y, wz))
					if bs < sdf_m:
						sdf_m = bs
						if sdf_m < 0.6:
							mat = R.STONE

				sdf_m = minf(sdf_m, y - bedrock_top_y)  # unbreakable world floor
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

## Spawn: the hub vale is flat by construction — spawn matches the scene.
func find_spawn(_cache: Dictionary) -> Vector3:
	return Vector3(0.0, vale_height + 1.0, 10.0)


## Water tiles for the runtime visual planes: [[x, z, size, y], ...] on a 32m grid.
func water_tiles(cache: Dictionary) -> Array:
	var tiles: Array = []
	const TILE := 32
	@warning_ignore("integer_division")
	var half_x := size_x / 2
	@warning_ignore("integer_division")
	var half_z := size_z / 2
	for wz in range(-half_z, half_z, TILE):
		for wx in range(-half_x, half_x, TILE):
			@warning_ignore("integer_division")
			var col := column(wx + TILE / 2, wz + TILE / 2, cache)
			var wy: float = col["water_y"]
			if wy != NO_WATER:
				tiles.append([wx, wz, TILE, wy + 0.15])
	return tiles


## Highest terrain inside an XZ rect (sampled) — used for nav-graph bounds.
func max_height_in_rect(x0: float, z0: float, x1: float, z1: float, step: float, cache: Dictionary) -> float:
	var best := float(y_min)
	var z := z0
	while z <= z1:
		var x := x0
		while x <= x1:
			best = maxf(best, height_at(x, z, cache))
			x += step
		z += step
	return best
