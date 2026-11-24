# Scry

A World of Warcraft addon that records character data (known profession recipes,
kill counts, ...) into SavedVariables so external apps can read it.

This repository is built to be developed by AI agents. You do not need to read
the code: you describe what you want, the agent uses the tooling here to prove
its work, and you press `/reload` in game when it asks.

- Agents: read [AGENTS.md](AGENTS.md).
- Machine setup: [docs/DEV_ENVIRONMENT.md](docs/DEV_ENVIRONMENT.md).
- What the addon exports, for authors of external apps: [docs/DATA_CONTRACT.md](docs/DATA_CONTRACT.md).

## Installing (players)

1. Download `Scry-X.Y.Z.zip` from the newest
   [release](https://github.com/Tuhis/scry/releases/latest).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so that
   `AddOns\Scry\Scry.toc` exists. To update, delete the old `Scry` folder first.
3. Restart the game (a newly added addon is not picked up by `/reload`) and
   check that Scry is enabled in the AddOns list on the character screen.

Your recorded data lives in `WTF\Account\<account>\SavedVariables\Scry.lua`
and survives updates; newer versions migrate it automatically.

## Requirements

- Python 3.9+ and Docker. That is all for the offline loop; every other tool
  lives in a pinned container that `./dev` builds on first use.
- For in-game verification: WoW: Forever installed on the same machine.
  Recommended setup is Windows + WSL2 with the repo inside WSL.

```sh
./dev doctor    # what is set up, what is missing
./dev check     # the gate: format, lint, tests, data contract, typecheck (~6s)
```

## How development works

| Loop | Command | Proves | Needs |
|---|---|---|---|
| Offline | `./dev check` | Code is valid, uses only WoW APIs that exist, logic and exported data shape are right against a simulated client | Docker |
| Simulator | `./dev sim` | Addon loads and runs without Lua errors inside the real Blizzard UI code | Docker |
| In game | `./dev deploy`, `./dev wait` | It works with real game data | WoW + you |

The in-game loop from your side:

1. The agent deploys a build and asks you to `/reload`, do something specific
   in game, and `/reload` again.
2. The game writes SavedVariables on that second reload. The agent reads the
   addon's own error log, selftest results and exported data from that file and
   continues on its own.

One-time game setup: enable the addon, and run `/console scriptErrors 1` so Lua
errors are visible to you as well.

## What keeps unreviewed code honest

- Lint knows every function, event and enum of the current game client
  (generated from Blizzard's API documentation); calling something that does not
  exist fails the check.
- The exported data has a JSON Schema and a golden file; the addon cannot change
  what external apps see without that change showing up in a diff.
- In-game results are tied to a build id, so an agent cannot mistake results
  from old code for results of its latest change.
- A Stop hook keeps Claude Code from finishing a turn while `./dev check` is red.
- CI runs the same `./dev check --ci`.

## Assumptions made when this was scaffolded

- Target is **WoW: Forever** (client 1.60.1, interface 16001, installed in
  `_forever_`). The pinned values that select the client are listed in
  [docs/DEV_ENVIRONMENT.md](docs/DEV_ENVIRONMENT.md#game-version-and-flavor).
- Data flows addon -> apps. Nothing here reads data written by apps yet; see the
  note in [docs/DATA_CONTRACT.md](docs/DATA_CONTRACT.md#apps-writing-to-the-addon).
