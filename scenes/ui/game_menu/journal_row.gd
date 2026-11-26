class_name JournalRow
extends SelectButton
## One row of the journal's enemy list (journal_row.tscn). `enemy_type` is the EnemyType whose kill count and
## lore the row shows; the page binds the data.

@export var enemy_type: InventoryIds.EnemyType = InventoryIds.EnemyType.CRAWLING
