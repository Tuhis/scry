# Scry: instructions for AI agents

Scry is a World of Warcraft addon for **WoW: Forever** (interface 16001, Lua 5.1) that records character data
(known profession recipes, kill counts, ...) into SavedVariables, where external
apps read it. The SavedVariables file **is the product's API**.

The humans on this project do not read the code. That makes the tooling the only
safety net: every claim you make about the code must be backed by a command you
ran, and the checks, tests, schema and docs must stay truthful as you change things.

## Rules

1. **Run `./dev check` after every change** and before finishing. It must end
   with `CHECK PASSED`. (A Stop hook re-runs it if you forget.) Never weaken a
   check, the mock, or the schema just to get to green.
2. **Never write WoW API from memory.** WoW: Forever is its own client (game
   type `camelot`, interface 16xxx) and is neither Retail nor Classic: what you
   remember from either is not evidence. Look up every function, event, enum and
   widget method with `./dev api <pattern>` first. The API changes every patch
   and your memory of it is unreliable. "Not found" means it does not exist.
3. **The data contract is explicit.** Anything written to `ScryDB` must be
   described in `schema/ScryDB.schema.json` and `docs/DATA_CONTRACT.md`, and show
   up in the golden file. See "Changing what the addon exports".
4. **New behaviour needs a test** in `tests/spec/`, and live-client assumptions
   need a selftest (`ns.SelfTest:Register`).
5. **Be exact about what was verified.** Offline green means: lint, API existence,
   types, logic against stubs. It does not mean "works in game". Only
   `./dev report` / `./dev wait` output from a real game session does. If no
   game is available, say in-game verification is pending.
6. Start a session on an unfamiliar machine with `./dev doctor`.

## WoW: Forever facts (verified in game)

Things about this client that differ from Retail/Classic. Add to this list
whenever a real game session teaches you something; cite the evidence.

- **No realms.** Characters are created on a *ruleset* (Normal, PvP,
  Roleplaying, ..., one mega-server per ruleset and region), not a realm.
  `GetRealmName()` and `GetNormalizedRealmName()` return `""` (seen in game,
  2026-11-22). No API returns the ruleset; `C_GameRules` only has predicates
  such as `IsHardcoreActive()`. Never key data by `Name-Realm`; ScryDB keys
  characters by `UnitGUID("player")`, e.g. `Player-6951-00BF5811`.
- **Names.** Characters have a first and a last name; `UnitName("player")`
  returned only the first name (`Welehu`), so names are not unique keys.

- **Modern UI systems** (seen in game, 2026-11-23, level 36 mage). Forever uses
  the Retail-style systems, not Classic ones: `C_SpellBook`, `C_TradeSkillUI`,
  `C_SkillInfo`, class talents as a trait config (`C_ClassTalents`, `C_Traits`).
  The bank is tab-based in the UI source (`C_Bank`); not yet seen in game.
  Blizzard's Forever-specific UI code is in `Camelot/` folders of the UI
  source (`./dev api --source`).
- **Spells have ranks.** Each rank is its own spell ID and all learned ranks
  are in the spellbook; the rank is the "Rank N" subtext. Non-rank subtexts
  exist too ("Racial", "Comprehension").
- **Profession recipes** are readable only for the open profession window:
  `C_TradeSkillUI.GetAllRecipeIDs()` works there (returned 471 for Tailoring).
  `C_SkillInfo` lists each profession twice (e.g. 185 and 2939, same rank).
- **Legacy system.** Legacy Challenges are achievements (`GetAchievementInfo`
  reports the year as years since 2000); the three Legacy trees are trait
  trees readable at login without opening the Legacy window; IDs are in
  `Constants.LegacyConsts`. Blizzard's code: `Blizzard_LegacySystem`.

## Working with the human

- Iterate fast. Do not run `./dev wait` (blocks up to 9 minutes) unless the
  human agreed to it; after they say they reloaded, run `./dev report` and
  `./dev sv`, which return immediately.
- A newly deployed addon is picked up by a plain `/reload`; no client restart
  is needed.
- Look facts about WoW: Forever up on the web when the API reference and the
  game session do not answer them.

## Commands

Everything goes through `./dev` (`dev.cmd` on native Windows). The host only
needs Python 3 and Docker; tools run in a pinned container.

| Command | What it does | Time |
|---|---|---|
| `./dev check` | Auto-format, lint incl. "does this WoW API exist", event names, tests, data contract, typecheck | ~6s |
| `./dev test [busted args]` | Tests only, e.g. `./dev test tests/spec/core_spec.lua`, `./dev test --filter=level` | ~1s |
| `./dev api <regex>` | Search the WoW API reference: `fn`, `event`, `enum`, `struct`, `method`, `alias` lines with signatures | ~1s |
| `./dev api --source <regex>` | Search Blizzard's own UI source for usage examples | ~1s |
| `./dev sim` | Load the addon into a headless simulation of the real Blizzard UI; report Lua errors | ~25s |
| `./dev golden` | Regenerate `tests/golden/Scry.lua` after an intended contract change | ~1s |
| `./dev deploy [--watch]` | Copy the addon into the WoW install as a uniquely identified dev build | |
| `./dev wait` | Block until the game has saved results of the deployed build, then print the report | |
| `./dev report` | Errors, selftest results, schema validity and log of the last game session | |
| `./dev sv [--all]` | Live SavedVariables as JSON | |
| `./dev screenshot` | Path of the newest in-game screenshot (open it with your image reader) | |
| `./dev doctor` / `./dev config` | Check the environment / set the WoW install path | |
| `./dev api-update` | Bump the pinned API reference after a WoW patch | |

Exit codes of `report` / `wait`: 0 clean, 1 problems (errors, failed selftests,
schema violations), 2 stale (game ran older code than deployed), 3 no data,
4 timed out.

## The feedback loops, fastest first

**1. Offline (`./dev check`), always.** Lint fails on any global or `C_*` /
`Enum.*` member that does not exist in the client. Tests load the real addon
from its TOC into a simulated client (`tests/wow/`) and drive it with events,
timers, slash commands and reloads.

**2. Simulator (`./dev sim`), for changes that touch frames, UI, load order or
Blizzard code.** Real Blizzard Lua/XML, stubbed game data: it proves the addon
loads and runs without Lua errors next to the real UI. Game data is fake there
(name `Unitname`, level 0, ...), so in-game selftests may fail in the simulator;
only Lua errors count. "Errors not involving the addon" are simulator gaps.
The simulator (wowless) is written for Retail; where its Retail assumptions
break on Forever's data, `tools/docker/sim.Dockerfile` patches it (so far:
class talents). If an error comes from the simulator's own `data/impl/*.lua`,
fix it there the same way; try the patch in a throwaway container first
(`docker run` the `scry-sim` image, edit, `HOME=/root cmake --build --preset
default --target wowless_wowf wowf`), because a full image rebuild takes ~10 minutes.

**3. In game, for everything that depends on real game data** (which is most of
what this addon does). Requires a machine with WoW; a human has to press keys:

1. `./dev check`, then `./dev deploy`.
2. Ask the human, in one message, for exactly what you need. Template:
   *"Please `/reload` in game, then <do X: open the profession window / kill a
   mob / ...>, then `/reload` again."* The second reload is required: the game
   only writes SavedVariables on `/reload` or logout, and it writes the state of
   the session that is ending.
3. Run `./dev wait` (blocks up to 9 minutes; rerun if it times out). It skips
   saves from older builds and prints the report for the build you deployed.
4. Read the report: `errors` (with stack traces), `selftest`, `schema`, `log`.
   Use `./dev sv` to inspect the actual exported data, `./dev screenshot` after
   asking for `/scry shot` when you need to see the UI.

Dev builds (made by `deploy`) run all selftests 2 seconds after login and record
debug-level log lines. `ns.Log:Debug(...)` is your printf: it ends up in the report.
Adding a file or changing the TOC may need a full client restart rather than
`/reload` (`deploy` prints a note when that applies).

Do not automate input to the game client (no simulated keystrokes or clicks):
it violates Blizzard's terms and risks the account.

## Layout

```
Scry/                     the addon; exactly what ships and what gets deployed
  Scry.toc                load order, interface version, SavedVariables
  BuildInfo.lua           build id (overwritten in deployed copies)
  Core/Init.lua           ns.safecall, ns:On(event, fn), ns:After, ns:NewModule
  Core/Log.lua            ns.Log -> ScryDevDB (dev log, errors; not part of the contract)
  Core/DB.lua             ns.DB -> ScryDB (the contract), schema version, migrations
  Core/SelfTest.lua       in-game selftests
  Core/Slash.lua          /scry status | selftest | dev on|off | rl | shot
  Core/DB.lua also holds ScryDB.names (ID -> display name): call ns.DB:Name(kind, id, text) for every exported ID
  Core/Items.lua          ns.Items: container scan -> itemID counts + vendor value (bags, bank)
  Core/Traits.lua         ns.TraitNodes: trait tree reader (talents, Legacy trees)
  Modules/Character.lua   reference data module: copy its structure
  Modules/*.lua           one module per ScryDB section (money, bags, bank, skills, professions,
                          spells, legacy, equipment, talents, reputations, currencies, quests, pvp, played)
schema/ScryDB.schema.json the contract, machine readable
docs/DATA_CONTRACT.md     the contract, for humans and external app authors
docs/PROFILE_DESIGN.md    profile sections not built yet / not yet confirmed in game
docs/DEV_ENVIRONMENT.md   machine setup
tests/wow/                simulated client: init.lua (engine), api.lua (API stubs), serialize.lua
tests/spec/*_spec.lua     busted specs; contract_spec.lua produces the golden file
tests/golden/Scry.lua     exact SavedVariables output of the canonical scenario
tools/dev.py             host CLI      tools/tasks.py  in-container tasks
tools/docker/             pinned toolchain + API reference (Dockerfile, gen_api.lua), simulator (sim.Dockerfile)
```

## Addon conventions

- Every file starts with `local addonName, ns = ...`; share through `ns`, never
  through new globals. The only globals are the SavedVariables and slash command
  registrations listed in `.luacheckrc`.
- All entry points go through `ns.safecall` (already true for `ns:On`,
  `ns:After`, slash commands) so errors land in the report.
- Timestamps are `GetServerTime()` (unix seconds).
- Store locale-independent tokens/IDs (class token `MAGE`, spell IDs), not
  localized names, unless the localized text itself is the data.
- New files must be added to `Scry/Scry.toc` (load order matters: Core before Modules).

### Adding a data module

1. Look up the APIs and events: `./dev api ...`. Note flags in the output
   such as `SecretWhen...` / `SecretReturns`: on this client these APIs can
   return opaque "secret values" in restricted situations (e.g. combat) that
   cannot be inspected or saved. Check warcraft.wiki.gg before relying on them
   and collect data outside those situations.
2. Create `Scry/Modules/<Name>.lua` modelled on `Character.lua`:
   `ns:NewModule("<name>")`, write into `ns.DB:Section("<name>")`, call
   `ns.DB:Touch(section)` after each write, register selftests for what the
   real client must return. Add the file to the TOC.
3. Stub the APIs it uses in `tests/wow/api.lua` (rules are in that file's
   header) backed by `wow.state`, and write specs.
4. Extend the contract (next section).
5. `./dev check`, `./dev sim`, then the in-game loop.

### Changing what the addon exports

1. Edit `schema/ScryDB.schema.json` (every object has
   `additionalProperties: false`, so undeclared data fails the check) and
   `docs/DATA_CONTRACT.md`.
2. Extend the scenario in `tests/spec/contract_spec.lua` so the new data appears.
3. `./dev golden`, then read the diff of `tests/golden/Scry.lua`: it must show
   exactly the change you intended.
4. Additive change: keep `schemaVersion`. Removing, renaming or changing the
   meaning/type of existing data: bump `SCHEMA_VERSION` in `Core/DB.lua` and the
   `const` in the schema, add a migration in `Core/DB.lua` plus a spec that loads
   old-format data (`Wow.new({ saved = "ScryDB = {...}" })`), and call the break
   out in your summary - external apps must be updated.
5. Shape rules that keep the Lua-to-JSON mapping unambiguous are in
   `docs/DATA_CONTRACT.md` ("Shape rules").

## Commits and pull requests

- Changes reach `main` through a pull request that is squash-merged. The PR
  title is a Conventional Commit (`feat:`, `fix:`, `ci:`, `docs:`, ...) and
  becomes the commit on `main`. A change that breaks the data contract gets
  a `!` and says so in the body.
- To take a branch all the way to merged, use the `ship-pr` skill
  (`.claude/skills/ship-pr/SKILL.md`): it opens the PR, waits for CI and the
  automatic Claude review, handles findings, and merges when everything is
  green and resolved.
- Releases are automated by release-please (`release.yml`, config in
  `release-please-config.json`). Every push to `main` updates a release PR
  whose version bump and `CHANGELOG.md` entry come from the Conventional
  Commit titles: `fix:` -> patch, `feat:` -> minor, `!` -> major; `ci:`,
  `docs:`, `test:`, `chore:`, `refactor:` make no release. Merging that PR
  tags `vX.Y.Z` and attaches `Scry-X.Y.Z.zip` (the `Scry/` folder) to the
  GitHub Release. Never edit `## Version` in `Scry/Scry.toc` or
  `CHANGELOG.md` by hand: release-please owns both.
- CI (`check.yml`) is `./dev check --ci`. It proves the offline loop only,
  so a merged PR can still be "in-game verification pending"; say so in the
  PR body when that is the case.
- `claude-code-review.yml` reviews every PR; `claude.yml` answers `@claude`
  mentions. A PR that changes either of those two files gets no Claude
  review, so change them in a PR of their own.

## Test harness in one screen

```lua
local Wow = require("tests.wow")
local wow = Wow.new({ player = { name = "Thrall", level = 70 }, dev = true })
wow:login()                      -- TOC files, SavedVariables, ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD
wow:fire("PLAYER_LEVEL_UP", 71)  -- event names are validated against the real event list
wow:advance(5)                   -- clock + C_Timer
wow:slash("/scry status")
wow:reload()                     -- SavedVariables go through text, like the real client
wow.env.ScryDB; wow.ns; wow.printed; wow.errors
wow:assertNoErrors()
```

Reading a real WoW global that has no stub fails with a message telling you to
add one in `tests/wow/api.lua`. A stub must mirror the real return values
exactly; when you are not sure what the client returns, say so and cover it with
an in-game selftest instead of guessing.

## When something is off

- `./dev check` cannot start: `./dev doctor` (usually Docker is not running).
- Lint rejects an API you believe exists: check `./dev api`. If the game was
  patched, run `./dev api-update`. Do not add it to an ignore list.
- `wait` keeps timing out: the human has not reloaded twice, or the addon is not
  enabled in the addon list, or `./dev config` points at the wrong install/flavor.
- Report says `no ScryDevDB session`: the addon failed before `ADDON_LOADED`;
  ask the human for the on-screen Lua error (`/console scriptErrors 1`).
