## Grass island palette (Phase 1 Task 2c, style B). Vivid primaries on a sky-blue world; every 3D
## prop and the 2D panels take their colours from here. sRGB hex, as written in the style guide
## (apps/lab3d/docs/art-direction.md). ArtMeshBuilder converts to linear for the vertex colours.
class_name ArtPalette
extends RefCounted

# World
const SKY := Color("62c0ff")          # background (clear colour of the 3D view)
const GRASS := Color("4fbf3b")        # island top, sides
const GRASS_TOP := Color("5fd04a")    # island top face
const SOIL := Color("b8743f")         # island underside
const SOIL_DEEP := Color("9a5c2e")    # island tip
const TRUNK := Color("8a5129")
const LEAF := Color("1fae4b")
const LEAF_LIGHT := Color("29c457")
const STEM := Color("2a9a3e")
const ROCK := Color("aab3c4")
const CLOUD := Color("ffffff")
const FLOWERS := [Color("ffd400"), Color("ff4fa3"), Color("ffffff"), Color("ff7a1a")]

# Apparatus primaries (one colour per part; the lighter variant is its top face)
const YELLOW := Color("ffc61a")
const YELLOW_TOP := Color("ffd84a")
const RED := Color("ff3b3b")
const RED_TOP := Color("ff5a4f")
const BLUE := Color("2d7cf6")
const BLUE_DARK := Color("1f62d6")
const WHITE := Color("ffffff")

# Lighting (art_lit.gdshader) and contact
const LIGHT := Color("ffffff")        # lit side multiplier
const SHADE := Color("7d8ed8")        # shaded side multiplier (cool blue, never grey)
const SHADOW := Color("14234d")       # blob shadow colour
const SHADOW_ALPHA := 0.32
const DUST := Color("e9f5d8")

# 2D (UiTheme)
const INK := Color("1b2a4a")
const INK_SOFT := Color("4a5873")
const MUTED := Color("66758f")
const LINE := Color("d3e2f0")
const PAPER := Color("eaf6ff")        # app clear colour: a very light sky
const GREEN_TEXT := Color("23753a")
const GREEN_SOFT := Color("e6f7e1")
const YELLOW_DARK := Color("e0a400")
const BLUE_SOFT := Color("e4efff")
