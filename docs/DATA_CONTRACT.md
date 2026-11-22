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
containing two assignments:

- `ScryDB`: **the contract**, described here.
- `ScryDevDB`: debugging data for the development tooling. Not part of the
  contract; may change at any time. Ignore it.

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
  "characters": {
    "Player-1234-0ABCDEF1": {  // the character's GUID (WoW: Forever has no realms)
      "character": {           // one section per addon module
        "name": "Thrall",
        "class": "SHAMAN",     // locale-independent token
        "race": "Orc",         // locale-independent token
        "faction": "Horde",    // Alliance | Horde | Neutral
        "level": 70,
        "guid": "Player-1234-0ABCDEF1",
        "updatedAt": 1700003600
      }
    }
  }
}
```

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
