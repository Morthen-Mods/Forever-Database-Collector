# Forever Database Collector

Sammelt im Spiel Daten für die Forever Database und exportiert sie als Text,
den man auf der Website unter `/import` einfügt.

## Installation (Entwicklung)

Den Ordner per Symlink in den AddOns-Ordner des Forever-Clients legen, dann
reicht nach Änderungen ein `/reload`:

```
ln -s "/home/nico/Projekte/Forever Database Website + AddOn/Forever-Database-Collector" \
  "/run/media/nico/Games/Battle.Net/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/Forever-Database-Collector"
```

## Befehle

| Befehl | Wirkung |
| --- | --- |
| `/fdb` | Zeigt, wie viel bisher gesammelt wurde |
| `/fdb export` | Öffnet den Export-Dialog |
| `/fdb minimap` | Blendet den Minimap-Button aus bzw. ein |
| `/fdb debug` | Zeigt Fehler einzelner Sammler im Chat |

Der Minimap-Button zeigt beim Überfahren dieselben Zahlen wie `/fdb` und öffnet
bei jedem Klick den Export. Mit gedrückter linker Maustaste lässt er sich um die
Minimap verschieben.

Nach dem Kopieren im Dialog auf „Kopiert – Daten löschen“ klicken. So enthält
der nächste Export nur neue Beobachtungen.

## Was gesammelt wird

| Schlüssel im Export | Quelle im Spiel | Tabelle im Schema |
| --- | --- | --- |
| `zones` | `C_Map.GetMapInfo` | `zones` (über `ui_map_id`) |
| `quests` | Questfenster und Questlog | `quests`, `quest_texts`, `quest_rewards`, `quest_objectives` |
| `quest_npcs`, `quest_objects`, `quest_items` | Wer die Quest gibt bzw. annimmt | `quest_npcs`, `quest_objects`, `items.start_quest_id` |
| `quest_accepts` | Rasse/Klasse/Fraktion beim Annehmen | `quests.required_races`, `required_classes`, `side` |
| `quest_objective_kills` | Totes Ziel beim Questfortschritt | `quest_objectives.target_id` |
| `npcs`, `objects` | Ziel, Mouseover, Interaktion | `npcs`, `npc_texts`, `objects`, `object_texts` |
| `npc_spawns`, `object_spawns` | Spielerposition in Interaktionsreichweite | `npc_spawns`, `object_spawns` |
| `npc_loot`, `object_loot` | Geöffnete Beute, einmal pro GUID | `npc_loot`, `object_loot` |
| `npc_vendor_items` | Händlerfenster | `npc_vendor_items` |
| `items` | `C_Item.GetItemInfo` | `items`, `item_texts` |

Texte stehen in der Sprache des Clients (`meta.locale`).

## Exportformat

```
FDB1:<Base64(Gzip(JSON))>
```

```json
{
  "format": 1,
  "meta": { "addon_version": "0.1.0", "build": "70205", "interface": 16001, "locale": "deDE", "realm": "…", "started_at": 0, "exported_at": 0 },
  "data": { "quests": { "123": { … } }, "npc_spawns": [ { … } ], … }
}
```

Maps verwenden die ID als String-Schlüssel. Leere Tabellen können als `[]`
oder `{}` ankommen; die Import-Seite sollte beides akzeptieren.
