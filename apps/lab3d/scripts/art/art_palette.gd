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
const FLOWERS := [Color("ffd400"), PINK, WHITE, ORANGE]

# Apparatus primaries (one colour per part; the lighter variant is its top face)
const YELLOW := Color("ffc61a")
const YELLOW_TOP := Color("ffd84a")
const RED := Color("ff3b3b")
const RED_TOP := Color("ff5a4f")
const PINK := Color("ff4fa3")         # second / third hero (free fall, boxes); also a flower
const PINK_TOP := Color("ff6fb5")
const ORANGE := Color("ff7a1a")
const ORANGE_TOP := Color("ff9440")
const BLUE := Color("2d7cf6")
const BLUE_DARK := Color("1f62d6")
const WHITE := Color("ffffff")
const VIOLET := Color("4b2a9a")       # third hero of several balls / boxes (free fall: 1 kg ball)
const VIOLET_TOP := Color("6440c0")
const PURPLE := Color("7a5cf0")       # velocity arrow (the web's purple arrow: projectile)
const PURPLE_TOP := Color("9479ff")
const WATER := Color("39a6f0")        # water of the buoyancy tank (walls and floor below the waterline)
const WATER_TOP := Color("8fd3ff")    # the water surface (waterline strips, the ring around a floating body)
const SPACE := Color("27357a")        # the orbit lab's space stage (deep blue, never black)
const SPACE_TOP := Color("2f3f8f")
const TAPE := Color("8f5a32")         # parcel boxes' packing tape (Task 4g)
const CRATE := Color("d08a45")        # the bread cat's wooden bread crates (Task 4g), planks
const CRATE_TOP := Color("e3a35e")    # their top edges

# Lighting (art_lit.gdshader) and contact
const LIGHT := Color("ffffff")        # lit side multiplier
const SHADE := Color("7d8ed8")        # shaded side multiplier (cool blue, never grey)
const OUTLINE := Color("6e4630")      # characters' storybook outline (Task 4g2, ArtKit.outline_material)
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
