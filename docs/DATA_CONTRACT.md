# Data contract: what Scry exports

Audience: authors of apps that read Scry's data, and agents changing it.
The machine-readable version of this document is
[`schema/ScryDB.schema.json`](../schema/ScryDB.schema.json); a complete real
example is [`tests/golden/Scry.lua`](../tests/golden/Scry.lua). Both are enforced
by `./dev check`, so they cannot drift from what the addon writes.

## Where the data is

```
<WoW>/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/Scry.lua
```

One file per WoW account, covering all characters on it. It is a Lua source file
containing these assignments:

- `ScryDB`: **the contract**, described here.
- `ScryDevDB`: debugging data for the development tooling. Not part of the
  contract; may change at any time. Ignore it.
- `ScrySettings`: the player's addon settings (`/scry`). Not part of the
  contract; ignore it.

## When it changes

The game rewrites the file only when the UI is reloaded (`/reload`), on logout
and on exit. It is never updated while playing, and a client crash loses the
session's changes. Apps should watch the file's modification time. The game
replaces the whole file; read it after the write settles and tolerate a
momentarily missing or partial file.

## Reading it

The file is plain Lua table syntax: string keys as `["key"] = value`, array
items as `value, -- [n]`, strings double-quoted with backslash escapes, numbers,
`true`/`false`, nested tables. Either evaluate it with a sandboxed Lua 5.1
interpreter, or use a SavedVariables parser for your language.

For reference, this repository's own conversion: `./dev sv` prints `ScryDB` as
JSON (`./dev sv --file path/to/Scry.lua` for any copy of the file). The JSON
Schema describes that JSON form.

## Structure (schemaVersion 2)

```jsonc
{
  "schemaVersion": 2,
  "meta": {
    "addonVersion": "0.1.0",
    "gameVersion": "1.60.1",   // client that last wrote the file
    "interface": 16001,
    "updatedAt": 1700003600    // last change to any section
  },
  "names": {                   // ID -> display name, see "Names" below
    "locale": "enUS",
    "items": { "2589": "Linen Cloth" },
    "spells": { "143": "Fireball", "2330": "Elixir of Minor Fortitude" },
    "skills": { "171": "Alchemy" },
    "factions": { "72": "Stormwind" },
    "currencies": { "3485": "Renown" },
    "achievements": { "9001": "Keeper of the Flame" },
    "traitNodes": { "7001": "Improved Fireball" },
    "maps": { "1453": "Stormwind City" },
    "specs": { "63": "Fire" },
    "quests": { "7": "Kobold Camp Cleanup" },
    "skillLineAbilities": { "2330": 15201 }   // recipe spell ID -> Battle.net recipe ID, see "Recipe IDs"
  },
  "characters": {
    "Player-1234-0ABCDEF1": {  // the character's GUID (WoW: Forever has no realms)
      "character": {           // one section per addon module
        "name": "Thrall",
        "class": "SHAMAN",     // locale-independent token
        "race": "Orc",         // locale-independent token
        "faction": "Horde",    // Alliance | Horde | Neutral
        "level": 70,
        "guid": "Player-1234-0ABCDEF1",
        "sex": "male",         // male | female | other
        "xp": 1500, "xpMax": 20000, "restedXp": 300,
        "zone": 1453,          // UI map ID; absent where the client has no map
        "bindLocation": "Stormwind City",   // hearthstone, localized name
        "guild": { "name": "Scryers", "rank": "Officer", "rankIndex": 1 },  // absent without a guild
        "hardcore": false,
        "experiencePreset": "enhanced",     // classic | enhanced
        "updatedAt": 1700003600
      },
      "money": { "copper": 1234567, "updatedAt": 1700003600 },
      "bags": {                // backpack, bags, reagent bag
        "items": { "2589": 24, "6948": 1 },  // item ID -> total count
        "slots": { "total": 22, "free": 18 },
        "vendorValue": 462,    // copper a vendor would pay for everything
        "updatedAt": 1700003600
      },
      "bank": { /* same shape as bags; snapshot of the last bank visit */ },
      "skills": {
        "lines": { "171": { "rank": 150, "maxRank": 225 } },  // skill line ID
        "updatedAt": 1700003600
      },
      "professions": {
        "known": {
          "171": {             // profession (skill line) ID
            "recipes": [2329, 2330],   // known recipe spell IDs, ascending
            "difficulty": { "2329": "trivial", "2330": "easy" },  // optimal | medium | easy | trivial
            "scannedAt": 1700003600    // when this profession's window was read
          }
        },
        "updatedAt": 1700003600
      },
      "spells": {
        "player": { "143": { "passive": false, "rank": 2 }, "11103": { "passive": true } },
        "pet": { "17253": { "passive": false, "rank": 3 } },  // absent if no pet was seen
        "updatedAt": 1700003600
      },
      "legacy": {              // WoW: Forever Legacy system
        "points": { "earned": 7, "max": 50, "unspent": 3, "spent": 4 },
        "trees": { "1187": { "5001": 1 }, "1188": {}, "1189": {} },  // tree ID -> node ID -> rank
        "challenges": {        // completed Legacy Challenges, by achievement ID
          "9001": { "earnedByMe": true, "points": 10, "date": "2026-11-22" }
        },
        "updatedAt": 1700003600
      },
      "equipment": {
        "slots": { "1": { "itemID": 10504, "link": "|cff0070dd|Hitem:10504:...|h[Green Lens]|h|r" } },
        "updatedAt": 1700003600
      },
      "talents": {
        "specID": 63,          // absent when no specialization is chosen
        "nodes": { "7001": 5 },             // talent node ID -> rank
        "loadout": "CAEAAAAA...",           // importable in the talent window
        "updatedAt": 1700003600
      },
      "reputations": { "factions": { "72": { "standing": 5, "value": 4200 } }, "updatedAt": 1700003600 },
      "currencies": { "amounts": { "3485": 12 }, "updatedAt": 1700003600 },
      "quests": { "completed": [7, 54, 783], "updatedAt": 1700003600 },
      "pvp": { "honorableKills": 12, "highestRank": 0, "updatedAt": 1700003600 },
      "played": { "total": 360000, "thisLevel": 1200, "updatedAt": 1700003600 }
    }
  }
}
```

### Section notes

| Section | Updated | Notes |
|---|---|---|
| `character` | login, level up, XP gain, zone change, guild change, logout | |
| `money` | login, whenever money changes | |
| `bags` | login, whenever bag contents change | `vendorValue` counts items whose price the client has not loaded yet as 0; it corrects itself within the session. The game has no market prices: price `items` yourself for auction value. |
| `bank` | **only while the bank window is open** | Character bank tabs. Absent until the first bank visit with the addon. |
| `skills` | login, skill change | Skill levels of professions are here; skill lines under a collapsed header in the game's skill window may be missing. |
| `professions` | **only when that profession's window is opened**, plus each newly learned recipe | A profession is absent until its window was opened once. Check `scannedAt`. `difficulty` is each recipe's colour for the character's skill at `scannedAt` (optimal = orange, medium = yellow, easy = green, trivial = grey); it goes stale as the skill rises until the window is opened again, and is absent for professions last read by an addon version without it. |
| `spells` | login, spellbook change | Known spells only. `rank` is absent for spells without ranks. `pet` keeps the last seen pet's spells. |
| `legacy` | login, tree or point change; `challenges` a few seconds after login and on completion | `points.unspent`/`spent` are absent if the client did not report the point currency. Only nodes with a rank and completed challenges are listed. |
| `equipment` | login, equipment change | Slot IDs: 1 head, 2 neck, 3 shoulder, 4 shirt, 5 chest, 6 waist, 7 legs, 8 feet, 9 wrist, 10 hands, 11-12 rings, 13-14 trinkets, 15 back, 16 main hand, 17 off hand, 18 ranged, 19 tabard. |
| `talents` | login, talent or spec change | |
| `reputations` | login, reputation change | `standing`: 1 Hated, 2 Hostile, 3 Unfriendly, 4 Neutral, 5 Friendly, 6 Honored, 7 Revered, 8 Exalted. Factions under a collapsed header may be missing. |
| `currencies` | login, currency change | |
| `quests` | login, quest turn-in | |
| `pvp` | login, PvP kill | `highestRank` is the game's `PvPRanks` enum (0 none, 5-18 = rank 1-14). |
| `played` | **only when the player types `/played`** | Absent until then. |

Maps keyed by an ID (`items`, `lines`, `known`, `player`, `trees`, `slots`, ...)
are objects with numeric string keys in JSON, also when empty.

### Names

The sections above hold IDs only. `names` is the lookup table that turns them
into text, one map per kind of ID:

| Map | Names the IDs in |
|---|---|
| `items` | `bags.items`, `bank.items`, `equipment.slots[].itemID` |
| `spells` | `spells.player`, `spells.pet`, `professions.known[].recipes` (recipes are spells) |
| `skills` | `skills.lines`, `professions.known` |
| `factions` | `reputations.factions` |
| `currencies` | `currencies.amounts` |
| `achievements` | `legacy.challenges` |
| `traitNodes` | `talents.nodes`, `legacy.trees[]` |
| `maps` | `character.zone` |
| `specs` | `talents.specID` |
| `quests` | `quests.completed` |

- Names are in the game client's language, given by `names.locale`. When the
  player switches language the whole table is dropped and collected again.
- The table is shared by all characters and only grows: a name is added when the
  addon exports an ID and the client knows its name. It is **best effort**: an ID
  can be missing (the client loads item and quest names from the server on
  demand, usually within the same session). Fall back to showing the ID.
- All ranks of a spell share one name; the rank is in `spells`.
- Equipment names are the base item's name; the full name with a random suffix
  ("... of the Hierophant") is inside `equipment.slots[].link`.

### Recipe IDs

A recipe has two IDs. The game, and so `professions.known[].recipes` and
`names.spells`, uses the recipe's **spell ID**. Battle.net's game data API uses
the **skill line ability ID** and does not carry the spell ID: Runed Copper Rod
is spell `7421` in the game and `/data/wow/recipe/4291` in the API.
`names.skillLineAbilities` maps the first to the second, for every recipe the
addon has exported.

- It is static game data, the same for every character and language. Unlike the
  name maps it is kept when `names.locale` changes.
- It is filled while a profession window is open. Recipes saved by an addon
  version without it are missing until that profession's window is opened again.

### General

- Characters are keyed by GUID, which is unique and never changes. WoW: Forever
  has rulesets (Normal, PvP, ...) instead of realms; the ruleset is not exported
  because the client API does not expose it.
- All timestamps are Unix seconds (server time).
- Every section carries its own `updatedAt`; a section is only as fresh as the
  last time that character was logged in with the addon enabled.
- A character entry exists once the character has logged in with the addon;
  sections appear as their module first records data, so treat every section as
  optional.

## Compatibility promise

- `schemaVersion` only changes for breaking changes (removed or renamed fields,
  changed types or meaning). Apps should refuse, or handle explicitly, a
  `schemaVersion` they do not know.
- Within a schema version, changes are additive: new sections, new optional
  fields. Apps should ignore fields they do not know. (The schema itself forbids
  unknown fields; that strictness is for the addon's own checks, to force every
  addition to be declared.)
- The addon migrates data from older schema versions on load, so the file never
  mixes versions.

## Shape rules

Lua tables do not distinguish arrays from maps, and an empty table is both. To
keep every consumer's parser in agreement, the addon follows these rules:

- A table is either a **list** (keys exactly `1..n`) or a **map** (anything
  else), never a mix.
- Maps keyed by numeric IDs (recipe IDs, NPC IDs) are fine and efficient in
  Lua. Consumers must treat them as maps even when the IDs happen to be
  `1..n`; the schema says which is which (`type: object` vs `type: array`),
  and `./dev sv` uses the schema to decide.
- Only strings, finite numbers, booleans and tables are stored.
- IDs and locale-independent tokens are stored rather than localized names.

## Apps writing to the addon

Not implemented. If it is needed later: the game overwrites the whole file on
every reload or logout, so an app can only safely write while the game is not
running, and data for the addon should go into a separate SavedVariable (for
example `ScryInbox`) that the app owns and the addon only reads, never into
`ScryDB`. That variable would get its own schema and section in this document.
