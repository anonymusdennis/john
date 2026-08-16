class_name VoxelBlockRegistry
extends RefCounted
## Block registry for the voxel platform.
##
## Loads the environment block catalog (voxel-platform-handoff/04-block-catalog.json)
## and maps every block id onto one of the 16 smooth-terrain material channels
## supported by the Transvoxel mesher (4-blend-over-16 texturing).
##
## Voxels are a logical storage unit — a "block" here is a *material*, not a
## Minecraft cube. Ores are excluded by the catalog itself (see exclude_rules).
##
## This script is stock-Godot safe: it never references godot_voxel classes.

const CATALOG_PATH := "res://voxel-platform-handoff/04-block-catalog.json"

## The 16 terrain material channels. Index == texture index stored in the
## voxel INDICES channel, == index into the terrain shader's material arrays.
## Colors are original, muted "Space Engineers industrial" tones — deliberately
## not Minecraft palette values.
const CHANNELS: Array[Dictionary] = [
	{"name": "Stone", "albedo": Color(0.42, 0.42, 0.44), "roughness": 0.92, "noise_scale": 0.35, "noise_strength": 0.16},
	{"name": "Deepslate", "albedo": Color(0.23, 0.23, 0.26), "roughness": 0.88, "noise_scale": 0.5, "noise_strength": 0.2},
	{"name": "Granite", "albedo": Color(0.48, 0.34, 0.3), "roughness": 0.9, "noise_scale": 0.6, "noise_strength": 0.18},
	{"name": "Diorite", "albedo": Color(0.62, 0.61, 0.6), "roughness": 0.9, "noise_scale": 0.7, "noise_strength": 0.14},
	{"name": "Andesite", "albedo": Color(0.5, 0.51, 0.5), "roughness": 0.91, "noise_scale": 0.5, "noise_strength": 0.13},
	{"name": "Tuff", "albedo": Color(0.44, 0.45, 0.4), "roughness": 0.95, "noise_scale": 0.45, "noise_strength": 0.15},
	{"name": "Calcite", "albedo": Color(0.78, 0.78, 0.75), "roughness": 0.8, "noise_scale": 0.55, "noise_strength": 0.1},
	{"name": "Dirt", "albedo": Color(0.4, 0.3, 0.22), "roughness": 0.98, "noise_scale": 0.8, "noise_strength": 0.2},
	{"name": "Grass", "albedo": Color(0.3, 0.44, 0.22), "roughness": 0.95, "noise_scale": 0.9, "noise_strength": 0.22},
	{"name": "Sand", "albedo": Color(0.72, 0.65, 0.48), "roughness": 0.97, "noise_scale": 1.1, "noise_strength": 0.12},
	{"name": "Terracotta", "albedo": Color(0.62, 0.4, 0.28), "roughness": 0.9, "noise_scale": 0.3, "noise_strength": 0.24},
	{"name": "Gravel", "albedo": Color(0.47, 0.45, 0.43), "roughness": 0.99, "noise_scale": 1.4, "noise_strength": 0.25},
	{"name": "Snow", "albedo": Color(0.88, 0.9, 0.94), "roughness": 0.55, "noise_scale": 0.7, "noise_strength": 0.06},
	{"name": "Moss", "albedo": Color(0.26, 0.4, 0.24), "roughness": 0.96, "noise_scale": 1.0, "noise_strength": 0.2},
	{"name": "Wood", "albedo": Color(0.36, 0.26, 0.16), "roughness": 0.85, "noise_scale": 1.6, "noise_strength": 0.22},
	{"name": "Leaves", "albedo": Color(0.22, 0.38, 0.18), "roughness": 0.9, "noise_scale": 2.2, "noise_strength": 0.3},
]

## Channel indices by name, for readable generator / tool code.
const STONE := 0
const DEEPSLATE := 1
const GRANITE := 2
const DIORITE := 3
const ANDESITE := 4
const TUFF := 5
const CALCITE := 6
const DIRT := 7
const GRASS := 8
const SAND := 9
const TERRACOTTA := 10
const GRAVEL := 11
const SNOW := 12
const MOSS := 13
const WOOD := 14
const LEAVES := 15

## Explicit catalog-id → channel mapping for blocks whose category alone is
## not enough. Everything else falls back through _category_channel().
const ID_CHANNEL_OVERRIDES := {
	"minecraft:stone": STONE,
	"minecraft:granite": GRANITE,
	"minecraft:polished_granite": GRANITE,
	"minecraft:diorite": DIORITE,
	"minecraft:polished_diorite": DIORITE,
	"minecraft:andesite": ANDESITE,
	"minecraft:polished_andesite": ANDESITE,
	"minecraft:deepslate": DEEPSLATE,
	"minecraft:cobbled_deepslate": DEEPSLATE,
	"minecraft:polished_deepslate": DEEPSLATE,
	"minecraft:tuff": TUFF,
	"minecraft:calcite": CALCITE,
	"minecraft:dripstone_block": TERRACOTTA,
	"minecraft:grass_block": GRASS,
	"minecraft:dirt": DIRT,
	"minecraft:coarse_dirt": DIRT,
	"minecraft:podzol": DIRT,
	"minecraft:mycelium": MOSS,
	"minecraft:rooted_dirt": DIRT,
	"minecraft:mud": DIRT,
	"minecraft:muddy_mangrove_roots": DIRT,
	"minecraft:clay": GRAVEL,
	"minecraft:sand": SAND,
	"minecraft:red_sand": TERRACOTTA,
	"minecraft:gravel": GRAVEL,
	"minecraft:sandstone": SAND,
	"minecraft:red_sandstone": TERRACOTTA,
	"minecraft:snow_block": SNOW,
	"minecraft:ice": SNOW,
	"minecraft:packed_ice": SNOW,
	"minecraft:blue_ice": SNOW,
	"minecraft:powder_snow": SNOW,
	"minecraft:moss_block": MOSS,
	"minecraft:sculk": DEEPSLATE,
	"minecraft:obsidian": DEEPSLATE,
	"minecraft:crying_obsidian": DEEPSLATE,
	"bigglobe:overgrown_sand": MOSS,
	"bigglobe:overgrown_podzol": MOSS,
	"bigglobe:crystalline_prismarine": CALCITE,
	"bigglobe:slated_prismarine": CALCITE,
	"bigglobe:clouds": SNOW,
	"bigglobe:rough_quartz": CALCITE,
	"bigglobe:budding_quartz": CALCITE,
	"bigglobe:chorus_nylium": MOSS,
	"bigglobe:overgrown_end_stone": MOSS,
	"bigglobe:ashen_netherrack": TUFF,
	"bigglobe:charred_wood": WOOD,
	"bigglobe:charred_leaves": LEAVES,
}

var blocks: Dictionary = {}          ## id -> {name, category, solid, channel}
var placeable: Array[Dictionary] = []  ## build-palette entries {id, name, channel}
var _loaded := false


static func create() -> VoxelBlockRegistry:
	var reg := VoxelBlockRegistry.new()
	reg.load_catalog()
	return reg


func load_catalog() -> void:
	if _loaded:
		return
	_loaded = true
	blocks.clear()
	placeable.clear()

	var raw := _read_catalog_json()
	var listed: Array = raw.get("blocks", [])
	for entry: Dictionary in listed:
		var id := String(entry.get("id", ""))
		if id.is_empty():
			continue
		var solid := bool(entry.get("solid", false))
		var channel := _channel_for(id, String(entry.get("category", "")), solid)
		blocks[id] = {
			"name": String(entry.get("name", id)),
			"category": String(entry.get("category", "")),
			"solid": solid,
			"channel": channel,
		}

	# Creative build palette v1: one representative block per material channel,
	# so every channel is placeable. Extend later with the full decorative set.
	var seen_channels := {}
	for id: String in blocks:
		var b: Dictionary = blocks[id]
		var ch := int(b["channel"])
		if ch < 0 or seen_channels.has(ch):
			continue
		if not bool(b["solid"]):
			continue
		seen_channels[ch] = true
		placeable.append({"id": id, "name": String(b["name"]), "channel": ch})
	placeable.sort_custom(func(a, b): return int(a["channel"]) < int(b["channel"]))


func channel_of(id: String) -> int:
	var b: Dictionary = blocks.get(id, {})
	return int(b.get("channel", STONE))


func channel_name(channel: int) -> String:
	if channel >= 0 and channel < CHANNELS.size():
		return String(CHANNELS[channel]["name"])
	return "?"


## Shader uniform helpers ------------------------------------------------------

static func channel_albedos() -> PackedColorArray:
	var out := PackedColorArray()
	for c in CHANNELS:
		out.append(c["albedo"])
	return out


static func channel_params() -> PackedVector3Array:
	# x = roughness, y = noise scale, z = noise strength
	var out := PackedVector3Array()
	for c in CHANNELS:
		out.append(Vector3(c["roughness"], c["noise_scale"], c["noise_strength"]))
	return out


## Internals -------------------------------------------------------------------

func _read_catalog_json() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("VoxelBlockRegistry: catalog missing at %s — using channel names only" % CATALOG_PATH)
		return {}
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_warning("VoxelBlockRegistry: catalog JSON malformed")
	return {}


func _channel_for(id: String, category: String, solid: bool) -> int:
	if ID_CHANNEL_OVERRIDES.has(id):
		return int(ID_CHANNEL_OVERRIDES[id])
	if not solid:
		return -1  # fluids / plants / scatter — not a terrain material
	return _category_channel(category)


func _category_channel(category: String) -> int:
	match category:
		"terrain":
			return STONE
		"wood":
			return WOOD
		"leaves":
			return LEAVES
		"plants":
			return -1
		"fluids":
			return -1
		"nether":
			return TUFF
		"end":
			return CALCITE
		"decorative":
			return STONE
		"bigglobe":
			return STONE
	return STONE
