# Forever Database Collector

Collects game data for the Forever Database in-game and exports it as text,
which you paste into the website under `/import`.

## Installation (development)

Symlink the folder into the AddOns folder of the Forever client; after changes
a `/reload` is enough:

```
ln -s "/home/nico/Projekte/Forever Database Website + AddOn/Forever-Database-Collector" \
  "/run/media/nico/Games/Battle.Net/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/Forever-Database-Collector"
```

## Commands

| Command | Effect |
| --- | --- |
| `/fdb` | Shows how much has been collected so far |
| `/fdb export` | Opens the export dialog |
| `/fdb minimap` | Hides or shows the minimap button |
| `/fdb debug` | Shows errors of individual collectors in chat |

Hovering the minimap button shows the same numbers as `/fdb`, and every click
opens the export. Holding the left mouse button drags it around the minimap.

After copying, click "Copied – clear data" in the dialog. That way the next
export only contains new observations.

## What is collected

| Key in the export | Source in the game | Table in the schema |
| --- | --- | --- |
| `zones` | `C_Map.GetMapInfo` | `zones` (via `ui_map_id`) |
| `quests` | Quest window and quest log (texts, level, tag, time limit, sharable, rewards incl. spells, objectives) | `quests`, `quest_texts`, `quest_rewards`, `quest_objectives` |
| `quest_npcs`, `quest_objects`, `quest_items` | Who starts or ends the quest | `quest_npcs`, `quest_objects`, `items.start_quest_id` |
| `quest_accepts` | Race/class/faction when accepting | `quests.required_races`, `required_classes`, `side` |
| `quest_objective_kills` | Dead target on quest progress | `quest_objectives.target_id` |
| `quest_objective_objects` | Soft-targeted or just looted object on quest progress | `quest_objectives.target_id` |
| `quest_lines` | `C_QuestLine`, only if the client knows the questline | `quests.next_quest_in_chain`, `quest_prerequisites` |
| `quest_chain_hints` | Quests turned in shortly before accepting (guesswork, see below) | `quests.next_quest_in_chain`, `quest_prerequisites` |
| `npcs`, `objects` | Target, mouseover, interaction, soft target of the interact key | `npcs`, `npc_texts`, `objects`, `object_texts` |
| `npcs[].services` | NPC windows (vendor, repair, trainer, flight master, bank, inn …) | `npcs.npc_flags` |
| `npc_spawns`, `object_spawns` | Player position within interaction range | `npc_spawns`, `object_spawns` |
| `npc_loot`, `object_loot` | Opened loot, once per GUID | `npc_loot`, `object_loot` |
| `npc_vendor_items` | Vendor window | `npc_vendor_items` |
| `items` | `C_Item.GetItemInfo` and the tooltip (stats, damage, effects, requirements …) | `items`, `item_texts` |
| `sets` | Item set block of the tooltip | `item_sets`, `item_set_texts`, `item_set_bonuses` |

Texts are in the client's language (`meta.locale`).

Objects are no units, so their names and positions are only known from loot,
quest windows and the soft target of the interact key. With the client option
for the interact key turned on (CVar `softTargetInteract`), every object the
player walks up to is recorded.

Items and sets have the same fields as in Forever-Item-Scraper (item format 3,
see its README); `ItemTooltip.lua` is a copy of its `Tooltip.lua`, keep both
in sync.

### Questline clues

The client does not reveal prerequisites, so the addon collects clues per quest
pair (`quest_id` after `prev_quest_id`):

- when a quest is accepted, with up to three quests turned in during the
  10 minutes before it (`rank` 1 = the latest)
- when an NPC offers a quest right after a turn-in there, even if it is never
  accepted

| Field | Meaning |
| --- | --- |
| `strong_hint` | `offered` or `listed_after`: the NPC offers the quest right after the turn-in and did not offer it before. Check these by hand first. |
| `offered` | The game showed the quest right after the turn-in, without the NPC being opened again. Strong sign of `next_quest_in_chain`. |
| `listed_after` | The NPC lists the quest when opened within 60 seconds after the turn-in there |
| `accepted` | The quest was accepted (only then are `rank`, `seconds`, `same_giver` and `seen_before` set) |
| `same_giver` | Turn-in and new quest at the same NPC or object |
| `seconds` | Time between turn-in and accept |
| `seen_before` | The quest was already offered before the turn-in, so the turn-in is **not** its prerequisite |

A single clue proves nothing; only many matching observations should become a link.

## Export format

```
FDB1:<Base64(Gzip(JSON))>
```

`meta` contains the realm and character name (`meta.character`). Together with
the uploader ID from the browser cookie, the website uses this to recognize
trusted players.

```json
{
  "format": 1,
  "meta": { "addon_version": "0.1.0", "build": "70205", "interface": 16001, "locale": "deDE", "realm": "…", "character": "…", "started_at": 0, "exported_at": 0 },
  "data": { "quests": { "123": { … } }, "npc_spawns": [ { … } ], … }
}
```

Maps use the ID as a string key. Empty tables may arrive as `[]` or `{}`; the
import page should accept both.
