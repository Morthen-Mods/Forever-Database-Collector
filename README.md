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
| `quests` | Quest window and quest log | `quests`, `quest_texts`, `quest_rewards`, `quest_objectives` |
| `quest_npcs`, `quest_objects`, `quest_items` | Who starts or ends the quest | `quest_npcs`, `quest_objects`, `items.start_quest_id` |
| `quest_accepts` | Race/class/faction when accepting | `quests.required_races`, `required_classes`, `side` |
| `quest_objective_kills` | Dead target on quest progress | `quest_objectives.target_id` |
| `npcs`, `objects` | Target, mouseover, interaction | `npcs`, `npc_texts`, `objects`, `object_texts` |
| `npc_spawns`, `object_spawns` | Player position within interaction range | `npc_spawns`, `object_spawns` |
| `npc_loot`, `object_loot` | Opened loot, once per GUID | `npc_loot`, `object_loot` |
| `npc_vendor_items` | Vendor window | `npc_vendor_items` |
| `items` | `C_Item.GetItemInfo`, `C_Item.GetItemStats`, item tooltip | `items`, `item_texts`, `item_stats`, `item_damage`, `item_spells`, `item_spell_texts` |

Texts are in the client's language (`meta.locale`).

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
