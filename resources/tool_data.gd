class_name ToolData
extends RefCounted
## Static data of the talisman / tool system, copied from the Unity ScriptableObjects (RedTool / BlueTool /
## YellowTool `.asset`) and the talisman prefabs (TalismanWanderer / TalismanSentinel). Unity is read-only,
## so the values live here. Kept free of autoload references (GameState uses it).

## RedTool.asset / BlueTool.asset / YellowTool.asset: displayName, description, sprite. Arrays are indexed by
## the Unity ToolName enum values (InventoryIds.RedToolName / BlueToolName / YellowToolName), the same order
## as GameMaster.redToolData / blueToolData / yellowToolData.
const RED_TOOLS: Array[Dictionary] = [
	{"name": "Throw Blade", "desc": "A thick and short blade for throwing. Made from hard steel.",
			"icon": "res://assets/ui/tools/ThrowBlade.png", "max_charge": 10.0, "fix_cost_per_charge": 1},
	{"name": "Triple Knife", "desc": "Throw 3 small knifes in a fan shape. Although it has low damage, they can be used to deflect enemy projectiles.",
			"icon": "res://assets/ui/tools/TripleKnife.png", "max_charge": 5.0, "fix_cost_per_charge": 1},
	{"name": "Lifeblood Needle", "desc": "Gain 2 lifeblood masks. Can't be used if already have lifeblood masks.",
			"icon": "res://assets/ui/tools/LifebloodNeedle.png", "max_charge": 2.0, "fix_cost_per_charge": 0},
]
## Blue and yellow tools have no gameplay in Unity either ("Not yet implemented" in their descriptions):
## they can be found and equipped, nothing else.
const BLUE_TOOLS: Array[Dictionary] = [
	{"name": "Acid Orb", "desc": "Allow user to walk and swim in acid, acid puddle, acid pool and acid lake. Not yet implemented.",
			"icon": "res://assets/ui/tools/AcidOrb.png"},
	{"name": "Weaver Mask", "desc": "Mask of a weaver. It will summon a permanent tiny spider to follow and help you. Not yet implemented.",
			"icon": "res://assets/ui/tools/WeaverMask.png"},
]
const YELLOW_TOOLS: Array[Dictionary] = [
	{"name": "Crab Orb", "desc": "Orb with a crab. The dev don't know what it do either. Not yet implemented.",
			"icon": "res://assets/ui/tools/CrabOrb.png"},
]

const EMPTY_TOOL_ICON := "res://assets/ui/talisman/EmptyTool.png"
const RED_SLOT_ICON := "res://assets/ui/talisman/RedSlot.png"
const BLUE_SLOT_ICON := "res://assets/ui/talisman/BlueSlot.png"
const YELLOW_SLOT_ICON := "res://assets/ui/talisman/YellowSlot.png"

## Talisman prefabs (GameMaster.talismanData holds exactly these two; the Toolmaster enum value has no
## prefab). `crest`: sprite, `name_text`: TalismanName TMP text; red / blue / yellow: slot centres in Unity
## canvas units relative to the talisman centre (y up), in slot order (index = position in equipped_*_tools).
const TALISMANS: Dictionary = {
	InventoryIds.TalismanName.WANDERER: {
		"name_text": "WANDERER", "crest": "res://assets/ui/talisman/TalismanWanderer.png",
		"red": [Vector2(0.0, 152.0)],
		"blue": [Vector2(-146.0, -85.0)],
		"yellow": [Vector2(146.0, -85.0)],
	},
	InventoryIds.TalismanName.SENTINEL: {
		"name_text": "SENTINEL", "crest": "res://assets/ui/talisman/TalismanSentinel.png",
		"red": [Vector2(0.0, 36.0), Vector2(0.0, 204.0)],
		"blue": [Vector2(-157.0, -78.0), Vector2(157.0, -78.0)],
		"yellow": [],
	},
}
const NO_TALISMAN_LAYOUT: Dictionary = {"name_text": "", "crest": "", "red": [], "blue": [], "yellow": []}

## Talismans that have a prefab (what the Unity debug inventory grants).
static func layout_talismans() -> Array[int]:
	var out: Array[int] = []
	for t: int in TALISMANS:
		out.append(t)
	return out

## Slot layout of a talisman; talismans without a prefab (Toolmaster) have no slots.
static func layout(talisman: int) -> Dictionary:
	return TALISMANS.get(talisman, NO_TALISMAN_LAYOUT) as Dictionary

static func tool_def(kind: int, tool_id: int) -> Dictionary:
	var list: Array[Dictionary] = tool_list(kind)
	if tool_id < 0 or tool_id >= list.size():
		return {}
	return list[tool_id]

## kind: ToolKind.
enum ToolKind { RED, BLUE, YELLOW }

static func tool_list(kind: int) -> Array[Dictionary]:
	match kind:
		ToolKind.BLUE:
			return BLUE_TOOLS
		ToolKind.YELLOW:
			return YELLOW_TOOLS
	return RED_TOOLS

static func red_max_charge(tool_id: int) -> float:
	if tool_id < 0 or tool_id >= RED_TOOLS.size():
		return 1.0
	return RED_TOOLS[tool_id]["max_charge"] as float
