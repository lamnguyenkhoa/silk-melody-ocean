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

## TMP font size (canvas units) -> px font size.
static func font_px(unity_size: int) -> int:
	return roundi(unity_size * CANVAS_TO_PX)

## Texture of `path`, or the sub-rect `region` (Godot top-left px) of it.
static func load_texture(path: String, region: Rect2 = Rect2()) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex == null or region.size == Vector2.ZERO:
		return tex
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region
	return atlas

# --- Tabs (InventoryMenu.inventoryMenuTabs order; the MenuTab labels are placed in game_menu.tscn) ---
enum Tab { INVENTORY, TALISMAN, MAP, JOURNAL }
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

## InventoryPage.AddSlotPrefabToGrid: grid appearance order (only items with amount > 0).
## Grid slots are instanced at runtime (InventoryGrid in inventory_page.tscn is their parent).
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

# --- Map (the DirtCaveArea rooms / paths are placed in pages/map_page.tscn) ---
const MAP_MOVE_SPEED: float = 1000.0 # MapPage.moveSpeed (canvas units / s)
const MAP_ZOOM_SPEED: float = 1.0 # MapPage.zoomSpeed (scale / s)
const MAP_ZOOM_MIN: float = 0.2
const MAP_ZOOM_MAX: float = 3.0
## PlayerMarker.Update: scale = 1 + sin(time * 4) / 2.
const MAP_MARKER_PULSE_SPEED: float = 4.0
const MAP_MARKER_PULSE_AMPLITUDE: float = 0.5
