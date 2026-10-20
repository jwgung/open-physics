## Shared planet definitions for S1 (texture bake tool and scene use the same table).
class_name PlanetPalette
extends RefCounted

const TEXTURE_SIZE := 2048          # native (Android) set, spec S1
const WEB_TEXTURE_SIZE := 1024      # web set: one step lower, keeps the download reasonable
const TEXTURE_DIR := "res://assets/generated"
const WEB_TEXTURE_DIR := "res://assets/generated/web"

## radius: planet size, orbit: orbit radius (scene units), colors: albedo gradient stops.
const PLANETS := [
	{"radius": 0.35, "orbit": 4.5, "colors": [Color(0.35, 0.33, 0.31), Color(0.62, 0.58, 0.52), Color(0.80, 0.76, 0.70)]},
	{"radius": 0.60, "orbit": 6.5, "colors": [Color(0.75, 0.55, 0.25), Color(0.92, 0.78, 0.50), Color(0.98, 0.90, 0.70)]},
	{"radius": 0.65, "orbit": 9.0, "colors": [Color(0.05, 0.18, 0.45), Color(0.15, 0.45, 0.20), Color(0.92, 0.94, 0.96)]},
	{"radius": 0.45, "orbit": 11.5, "colors": [Color(0.45, 0.16, 0.08), Color(0.75, 0.35, 0.18), Color(0.90, 0.62, 0.42)]},
	{"radius": 1.40, "orbit": 15.0, "colors": [Color(0.55, 0.38, 0.25), Color(0.88, 0.78, 0.62), Color(0.70, 0.45, 0.30)]},
	{"radius": 1.15, "orbit": 19.0, "colors": [Color(0.70, 0.60, 0.40), Color(0.92, 0.85, 0.65), Color(0.80, 0.70, 0.50)], "ring": true},
	{"radius": 0.85, "orbit": 23.0, "colors": [Color(0.40, 0.70, 0.78), Color(0.60, 0.85, 0.90), Color(0.75, 0.92, 0.95)]},
	{"radius": 0.80, "orbit": 26.5, "colors": [Color(0.12, 0.22, 0.65), Color(0.25, 0.40, 0.85), Color(0.50, 0.65, 0.95)]},
]


static func texture_dir(web: bool) -> String:
	return WEB_TEXTURE_DIR if web else TEXTURE_DIR


static func albedo_path(index: int, web := false) -> String:
	return "%s/planet_%d_albedo.png" % [texture_dir(web), index]


static func normal_path(index: int, web := false) -> String:
	return "%s/planet_%d_normal.png" % [texture_dir(web), index]
