class_name InventoryIds
extends RefCounted
## Unity enum values of the inventory / talisman / tool / enemy-lore data. The int values are what the save
## files and the arrays in GameState store, so never reorder them. Kept free of autoload references so
## constants elsewhere (GameMenuData) can use them.

## InventoryItem.ItemName
enum ItemName { VERDANT_MANTLE, SILK_SPOOL, MASK, NEEDLE, COOL_KEY, NOTEBOOK_QUILL, CARAPACE_BACKPACK, SILKBIND_SANDAL }
## Talisman.TalismanName
enum TalismanName { WANDERER, SENTINEL, TOOLMASTER }
## RedTool.ToolName
enum RedToolName { THROW_BLADE, TRIPLE_KNIFE, LIFEBLOOD_NEEDLE }
## BlueTool.ToolName
enum BlueToolName { ACID_ORB, WEAVER_MASK }
## YellowTool.ToolName
enum YellowToolName { CRAB_ORB }
## EnemyLore.EnemyType: the int keys of WorldData.enemy_kill_count. Enemy.enemy_type uses the same values
## (Crawling 0, Dipsa 1, Crabber 3 in the ported prefabs, identical to the Unity prefabs).
enum EnemyType { CRAWLING, DIPSA, TWISTED_DIPSA, CRABBER, LAPIS_LAZER, BOSS_BATTER, BATTER_RING, GREAT_CRAWLER }

## RedTool.asset maxCharge per RedToolName (ThrowBlade 10, TripleKnife 5, LifebloodNeedle 2).
const RED_TOOL_MAX_CHARGE: Array[float] = [10.0, 5.0, 2.0]
## Items a new game starts with (GameMaster.InitNewGameData); everything else is 0.
const NEW_GAME_ITEMS: Array[int] = [
	ItemName.VERDANT_MANTLE, ItemName.SILK_SPOOL, ItemName.MASK, ItemName.NEEDLE,
	ItemName.CARAPACE_BACKPACK, ItemName.NOTEBOOK_QUILL,
]
