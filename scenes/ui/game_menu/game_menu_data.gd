class_name GameMenuData
extends RefCounted
## Static data of the game menu, copied from the Unity ScriptableObjects / InventoryMenu.prefab (read-only
## source). Coordinates marked "unity" are canvas units of the 1920x1080 reference canvas, relative to the
## screen centre, y up; `to_px` converts them to Godot px (1 unity unit = 1/5 px on the 384x216 viewport).

const CANVAS_TO_PX: float = 0.2
const SCREEN_CENTER := Vector2(192.0, 108.0)

## unity canvas units -> px offset from the screen centre (y flipped).
static func to_px(unity: Vector2) -> Vector2:
	return Vector2(unity.x, -unity.y) * CANVAS_TO_PX

## Rect (screen px, top-left origin) of a Unity element centred at `center` (unity, relative to the screen
## centre) with size `size`.
static func rect_px(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(SCREEN_CENTER + to_px(center) - size * (CANVAS_TO_PX * 0.5), size * CANVAS_TO_PX)

## Text area of a TextMeshPro element: TMP `m_margin` is (left, top, right, bottom) INSET from the rect
## (negative = grows the area outwards, the prefab uses that a lot).
static func text_rect_px(center: Vector2, size: Vector2, margin: Vector4) -> Rect2:
	var left: float = center.x - size.x * 0.5 + margin.x
	var right: float = center.x + size.x * 0.5 - margin.z
	var top: float = center.y + size.y * 0.5 - margin.y
	var bottom: float = center.y - size.y * 0.5 + margin.w
	return Rect2(SCREEN_CENTER + to_px(Vector2(left, top)), Vector2(right - left, top - bottom) * CANVAS_TO_PX)

## TMP font size (canvas units) -> px font size.
static func font_px(unity_size: int) -> int:
	return roundi(unity_size * CANVAS_TO_PX)

# --- Tabs (InventoryMenu.inventoryMenuTabs order, MenuTab labels) ---
enum Tab { INVENTORY, TALISMAN, MAP, JOURNAL }
const TAB_NAMES: Array[String] = ["Inventory", "Tools", "Map", "Journal"]
## MenuTab children: 300x60 boxes at x = 0, 380, 760, 1140 from the left edge of the 1440 wide bar.
const TAB_BAR_LEFT: float = -720.0
const TAB_BOX_SIZE := Vector2(300.0, 60.0)
const TAB_STEP: float = 380.0
## Top edge of the bar: anchor (0.5, 1) of the 100x100 group + 450 = 500 above the screen centre.
const TAB_BAR_TOP: float = 500.0
const TAB_FONT_CURRENT: int = 50
const TAB_FONT_OTHER: int = 40

# --- Inventory items (InventoryItem.asset: displayName / description / sprite) ---
const ITEMS: Array[Dictionary] = [
	{"name": "Verdant Mantle", "icon": "res://assets/ui/items/VerdantMantle.png",
			"desc": "Mantle made from abyssal moss weaved with translucent silk. Extremely durable yet very soft and flexible."},
	{"name": "Silk Spool", "icon": "res://assets/ui/items/SilkSpool.png",
			"desc": "Contains silk extracted from enemies to reuse them later."},
	{"name": "Mask", "icon": "res://assets/ui/items/InventoryMask.png",
			"desc": "More masks equals more health. Go collect more masks for a healthier life."},
	{"name": "Needle", "icon": "res://assets/ui/items/Needle.png",
			"desc": "Tenroh's basic weapon. Its power grows with proficiency."},
	{"name": "Cool Key", "icon": "res://assets/ui/items/CoolKey.png",
			"desc": "A key that is very cool. Used to unlock cool door."},
	{"name": "Notebook and Quill", "icon": "res://assets/ui/items/NotebookAndQuill.png",
			"desc": "Draw your surrounding environment and record defeated enemies' information.\n\nThe notebook made from leatherbug's mantle, and the quill is created from mossy silk."},
	{"name": "Carapace Backpack", "icon": "res://assets/ui/items/CarapaceBackpack.png",
			"desc": "Backpack made from fossillized  hard shell, very durable and spacious. Contain Tenroh's equipment and currency."},
	{"name": "Silkbind Sandal", "icon": "res://assets/ui/items/SilkbindSandal.png", "icon_region": Rect2(0, 0, 64, 64),
			"desc": "The incredible lightweight of the Silkbind Sandal allow its user to make an additional jump midair.\n\nUse these sandal to step above adversaries and explore new paths."},
]

## The three items that are static children of InventoryGroup (always shown, even with amount 0):
## item id -> [center (unity), size (unity), frame rotation (deg)]. Mask / SilkSpool frames are SelectFrame
## sized like the item, the Needle frame is the LongSelectFrame rotated by 90 degrees.
const STATIC_SLOTS: Dictionary = {
	InventoryIds.ItemName.MASK: {"center": Vector2(-573, 288), "size": Vector2(300, 300)},
	InventoryIds.ItemName.SILK_SPOOL: {"center": Vector2(-573, -17), "size": Vector2(300, 300)},
	InventoryIds.ItemName.NEEDLE: {"center": Vector2(-828, -36), "size": Vector2(300, 1200), "long_frame": Vector2(892.46, 227.497)},
}
## InventoryPage.AddSlotPrefabToGrid: grid appearance order (only items with amount > 0).
const GRID_ORDER: Array[int] = [
	InventoryIds.ItemName.VERDANT_MANTLE, InventoryIds.ItemName.NOTEBOOK_QUILL, InventoryIds.ItemName.CARAPACE_BACKPACK,
	InventoryIds.ItemName.SILKBIND_SANDAL, InventoryIds.ItemName.COOL_KEY,
]
## InventoryGrid: centre (unity), cell 100, spacing 40, 5 columns, no padding, upper-left start.
const GRID_CENTER := Vector2(-16.0, -47.685)
const GRID_SIZE := Vector2(660.0, 804.63)
const GRID_CELL: float = 100.0
const GRID_SPACING: float = 40.0
const GRID_COLUMNS: int = 5
## InventoryGroup bars and InfoBox.
const INVENTORY_BARS: Array[Vector2] = [Vector2(-393.0, -47.685), Vector2(363.0, -47.685)]
const BAR_SIZE := Vector2(12.755, 804.63)
const BAR_COLOR := Color(0.5377358, 0.5377358, 0.5377358)
const INVENTORY_INFO_CENTER := Vector2(676.0, 335.0)
## Name 666.56x67.04 at (0, 0), margin (77.89, -21.44, 86.86, -75.87); Desc 200x50 at (0, -171), margin
## (-157.71, -28.54, -151.23, -238.86).
const INVENTORY_NAME_SIZE := Vector2(666.56, 67.04)
const INVENTORY_NAME_MARGIN := Vector4(77.89436, -21.442757, 86.85527, -75.87462)
const INVENTORY_DESC_OFFSET := Vector2(0.0, -171.0)
const INVENTORY_DESC_SIZE := Vector2(200.0, 50.0)
const INVENTORY_DESC_MARGIN := Vector4(-157.70963, -28.538458, -151.2252, -238.8623)

# --- Journal (EnemyLore.asset, order = EnemyLore.EnemyType) ---
## sprite: texture + region (Godot top-left px) + ppu 64 (every lore sprite); the JournalEnemyImage shows
## it at its native size = region size * 100 / ppu canvas units.
const SPRITE_PPU: float = 64.0
const REFERENCE_PPU: float = 100.0
const LORE: Array[Dictionary] = [
	{"name": "Crawling", "type": InventoryIds.EnemyType.CRAWLING, "desc": "It just walk.",
			"flavour": "Very useless and easy to kill.",
			"texture": "res://assets/enemies/Crawling.png", "region": Rect2(27, 81, 74, 42)},
	{"name": "Dipsa", "type": InventoryIds.EnemyType.DIPSA, "desc": "Shoot orange bullet at you.",
			"flavour": "They are fragile and easy to deal with. But in large number they will spell trouble.",
			"texture": "res://assets/enemies/NormalDipsa.png", "region": Rect2(0, 0, 128, 128)},
	{"name": "Twisted Dipsa", "type": InventoryIds.EnemyType.TWISTED_DIPSA,
			"desc": "Shoot three bullets. Red bullet will slow you, yellow bullet will paralyze you and blue bullet will drain your silks.",
			"flavour": "A dipsa that really good with gambling.",
			"texture": "res://assets/enemies/TwistedDipsa.png", "region": Rect2(0, 0, 128, 128)},
	{"name": "Crabber", "type": InventoryIds.EnemyType.CRABBER,
			"desc": "Big black crab that will attempt to jump on you to attack you.",
			"flavour": "It may caught you by suprise with how far it can jump.",
			"texture": "res://assets/enemies/Crabber.png", "region": Rect2(40, 50, 86, 76)},
	{"name": "Lapis Lazer", "type": InventoryIds.EnemyType.LAPIS_LAZER,
			"desc": "Strange flower that can shoot laser at your position and deal high damage.",
			"flavour": "Why a plant want to kill me?",
			"texture": "res://assets/enemies/LapisLazer.png", "region": Rect2(0, 0, 128, 128)},
	{"name": "Beetle Batter", "type": InventoryIds.EnemyType.BOSS_BATTER,
			"desc": "Bulky beetle wearing a baseball outfit. Can summon its weird ring-like contraption to help in combat.",
			"flavour": "Why is this one is so out of place?",
			"texture": "res://assets/enemies/BatterIdle.png", "region": Rect2(256, 0, 256, 256)},
	{"name": "Batter's Contraption", "type": InventoryIds.EnemyType.BATTER_RING,
			"desc": "Ring-like device that shoot laser beam at its target.",
			"flavour": "I assumed this \"thing\" is a device but Im not really sure. It's may be actually a living entity.",
			"texture": "res://assets/enemies/BatterPet.png", "region": Rect2(0, 0, 128, 128)},
	{"name": "Great Crawler", "type": InventoryIds.EnemyType.GREAT_CRAWLER, "desc": "Big old crawler",
			"flavour": "Very strong",
			"texture": "res://assets/enemies/GreatCrawlerIdle.png", "region": Rect2(0, 0, 256, 256)},
]
## The prefab's EnemyList only has buttons for these types (BossBatter / BatterRing have lore assets but no
## button). The port shows all 8 entries in EnemyType order; set this to false for the prefab's 6.
const SHOW_UNLISTED_LORE: bool = true
const UNLISTED_LORE: Array[int] = [InventoryIds.EnemyType.BOSS_BATTER, InventoryIds.EnemyType.BATTER_RING]

## EnemyList (scroll area, clipped), row buttons 450x100 spaced 120, frame 500x150.
const JOURNAL_LIST_CENTER := Vector2(-677.2325, -47.685017)
const JOURNAL_LIST_SIZE := Vector2(544.684, 804.63)
const JOURNAL_ROW_SIZE := Vector2(450.0, 100.0)
const JOURNAL_ROW_STEP: float = 120.0
const JOURNAL_ROW_FRAME := Vector2(500.0, 150.0)
const JOURNAL_BARS: Array[Vector2] = [Vector2(-387.0, -47.685028), Vector2(261.0, -47.685028)]
const JOURNAL_IMAGE_CENTER := Vector2(-59.00005, -27.0)
const JOURNAL_IMAGE_SIZE := Vector2(600.0, 600.0)
const JOURNAL_INFO_CENTER := Vector2(611.0, 314.0)
const JOURNAL_NAME_SIZE := Vector2(200.0, 50.0)
const JOURNAL_NAME_MARGIN := Vector4(-107.810295, 0.0, -111.217674, -10.681103)
const JOURNAL_DESC_OFFSET := Vector2(19.0, -105.0)
const JOURNAL_DESC_MARGIN := Vector4(-211.42744, 0.0, -145.22255, -234.9849)
const JOURNAL_BAR_OFFSET := Vector2(-9.0, -416.0)
const JOURNAL_BAR_SIZE := Vector2(450.0, 10.0)
const JOURNAL_FLAVOR_OFFSET := Vector2(0.0, -481.0)
const JOURNAL_FLAVOR_MARGIN := Vector4(-185.8, 0.0, -159.0828, -159.21674)
const JOURNAL_KILL_OFFSET := Vector2(0.0, -739.0)
const JOURNAL_KILL_MARGIN := Vector4(-61.339096, 0.0, -61.338852, 0.0)

# --- Map (DirtCaveArea of InventoryMenu.prefab) ---
const MAP_MOVE_SPEED: float = 1000.0 # MapPage.moveSpeed (canvas units / s)
const MAP_ZOOM_SPEED: float = 1.0 # MapPage.zoomSpeed (scale / s)
const MAP_ZOOM_MIN: float = 0.2
const MAP_ZOOM_MAX: float = 3.0
const MAP_ROOM_COLOR := Color(0.4716981, 0.29914048, 0.0)
const MAP_PATH_COLOR := Color(1.0, 1.0, 1.0)
const MAP_MARKER_TEXTURE := "res://assets/ui/MaskIcon.png"
const MAP_MARKER_SIZE := Vector2(50.0, 50.0)
const MAP_ICON_SIZE := Vector2(100.0, 100.0)
## PlayerMarker.Update: scale = 1 + sin(time * 4) / 2.
const MAP_MARKER_PULSE_SPEED: float = 4.0
const MAP_MARKER_PULSE_AMPLITUDE: float = 0.5
## Areas: name, position (unity, relative to MapContent), rooms (scene name, position, size, optional icon
## child [texture, size]) and paths (name, rooms, position, size, rotation z in degrees as Unity).
const REST_CHAIR_ICON := "res://assets/props/RestChair.png"
const DOOR_SWITCH_ICON := "res://assets/props/DoorSwitch.png"
const MAP_AREAS: Array[Dictionary] = [
	{
		"name": "DirtCaveArea",
		"pos": Vector2(-795.0, 64.0),
		"paths": [
			{"room0": "DirtCave0", "room1": "DirtCave1", "pos": Vector2(89, -27), "rot": 0.0},
			{"room0": "DirtCave1", "room1": "DirtCave2", "pos": Vector2(367, -27), "rot": 0.0},
			{"room0": "DirtCave2", "room1": "DirtCave3", "pos": Vector2(350, -136), "rot": 0.0},
			{"room0": "DirtCave2", "room1": "DirtCave4", "pos": Vector2(736, -120), "rot": 0.0},
			{"room0": "DirtCave4", "room1": "DirtCave5", "pos": Vector2(1039, -120), "rot": 0.0},
			{"room0": "DirtCave4", "room1": "DirtCave6", "pos": Vector2(884, -258), "rot": -90.0},
			{"room0": "DirtCave9", "room1": "DirtCave10", "pos": Vector2(1390, -224), "rot": -90.0},
			{"room0": "DirtCave7", "room1": "DirtCave9", "pos": Vector2(1390, 13), "rot": -90.0},
			{"room0": "DirtCave7", "room1": "DirtCave8", "pos": Vector2(1528, 117), "rot": 0.0},
			{"room0": "DirtCave5", "room1": "DirtCave7", "pos": Vector2(1263, 117), "rot": 0.0},
			{"room0": "DirtCave6", "room1": "DirtCave10", "pos": Vector2(993, -352), "rot": 0.0},
			{"room0": "DirtCave6", "room1": "DirtCave11", "pos": Vector2(751, -352), "rot": 0.0},
			{"room0": "DirtCave11", "room1": "DirtCave12", "pos": Vector2(513, -317), "rot": 0.0},
			{"room0": "DirtCave12", "room1": "DirtCave13", "pos": Vector2(333, -392), "rot": -90.0},
			{"room0": "DirtCave2", "room1": "DirtCave14", "pos": Vector2(659, 34), "rot": -90.0},
			{"room0": "DirtCave14", "room1": "DirtCave15", "pos": Vector2(677, 221), "rot": -90.0},
		],
		"rooms": [
			{"name": "DirtCave0", "pos": Vector2(0, 0), "size": Vector2(100, 100)},
			{"name": "DirtCave1", "pos": Vector2(228.91995, 0), "size": Vector2(213.399, 100)},
			{"name": "DirtCave2", "pos": Vector2(538, -66), "size": Vector2(304.33, 174.31)},
			{"name": "DirtCave3", "pos": Vector2(228.92, -144), "size": Vector2(168.959, 100), "icon": REST_CHAIR_ICON},
			{"name": "DirtCave4", "pos": Vector2(884, -141), "size": Vector2(209.612, 144)},
			{"name": "DirtCave5", "pos": Vector2(1151, 9.435), "size": Vector2(139.652, 368.87)},
			{"name": "DirtCave6", "pos": Vector2(878, -369), "size": Vector2(157.975, 183.977), "icon": DOOR_SWITCH_ICON,
					"icon_pos": Vector2(4, 58), "icon_size": Vector2(50, 50)},
			{"name": "DirtCave11", "pos": Vector2(631.70593, -350.47382), "size": Vector2(190.093, 146.918)},
			{"name": "DirtCave12", "pos": Vector2(388, -317.12), "size": Vector2(182.681, 80.21)},
			{"name": "DirtCave13", "pos": Vector2(336, -515.92), "size": Vector2(155.503, 183.977)},
			{"name": "DirtCave7", "pos": Vector2(1395, 116), "size": Vector2(202.218, 116.2)},
			{"name": "DirtCave8", "pos": Vector2(1620, 126.01), "size": Vector2(120.152, 96.184), "icon": REST_CHAIR_ICON},
			{"name": "DirtCave9", "pos": Vector2(1395, -97), "size": Vector2(160.807, 154.653)},
			{"name": "DirtCave10", "pos": Vector2(1269, -330), "size": Vector2(488.454, 99.015)},
			{"name": "DirtCave14", "pos": Vector2(680, 129.81), "size": Vector2(110.969, 143.825)},
			{"name": "DirtCave15", "pos": Vector2(636.47, 282), "size": Vector2(198.02, 79.1)},
		],
	},
]
const MAP_PATH_SIZE := Vector2(130.0, 18.888)
