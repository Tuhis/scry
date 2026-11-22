# Development environment

For humans setting up a machine, and for agents diagnosing one. `./dev doctor`
reports the state of everything described here.

## What is required

| Need | Why | Check |
|---|---|---|
| Python 3.9+ | Runs `./dev` (standard library only) | `python3 --version` |
| Docker (daemon running, usable without sudo) | All tools run in a pinned container | `docker run --rm hello-world` |
| Git | Build ids, normal workflow | `git --version` |
| ~3 GB disk | Toolchain image ~0.8 GB, simulator image ~1.3 GB | |
| Network on first use | Building the images downloads tools and WoW UI data. After that everything runs offline (containers run with networking disabled) | |
| WoW: Forever on the same machine | Only for the in-game loop | `./dev doctor` |

Nothing else is installed on the host: Lua 5.1, luacheck, busted, StyLua,
lua-language-server, the WoW API reference and the simulator all live in the images
defined in `tools/docker/`. The image is rebuilt automatically when those files change.

First `./dev check` builds the toolchain image (a few minutes). First
`./dev sim` builds the simulator (about ten minutes: it compiles wowless and
downloads Blizzard's UI code).

## Recommended: Windows + WSL2

WoW runs on Windows; development runs in WSL.

1. Install WSL2 with Ubuntu, and Docker: either Docker Desktop with WSL
   integration enabled for the distro, or Docker Engine inside WSL.
2. Clone the repo **inside the WSL filesystem** (e.g. `~/src/scry`), not under
   `/mnt/c`. Bind mounts from the Windows filesystem are slow and file watching
   is unreliable there.
3. Run the agent (Claude Code etc.) inside WSL, in the repo.
4. `./dev doctor`. WoW is auto-detected in the usual places under `/mnt/<drive>/`;
   otherwise:
   `./dev config --wow-dir "/mnt/c/Program Files (x86)/World of Warcraft"`
5. `./dev deploy` copies the addon to
   `<wow>/_forever_/Interface/AddOns/Scry`. It copies rather than symlinks because
   the Windows game client cannot follow WSL symlinks. `./dev deploy --watch`
   in a spare terminal redeploys on every save.

## Native Windows

Works, with slower container file access.

1. Install Git for Windows, Python 3, Docker Desktop.
2. Use `dev.cmd <command>` from cmd/PowerShell or `./dev <command>` from Git Bash.
3. `dev.cmd config --wow-dir "C:\Program Files (x86)\World of Warcraft"` if
   auto-detection fails.

Claude Code hooks call `./dev` through a POSIX shell (Git Bash), which Claude
Code on Windows already requires.

## No WoW on the machine (VMs, cloud agents, CI)

The offline loop and the simulator work fully. `deploy`, `wait`, `report`, `sv`
and `screenshot` exit with a message explaining that a WoW installation is
needed. Work done there is "offline-verified"; in-game verification stays pending
until someone runs the in-game loop on a machine with the game.

## Game-side setup (once)

- Enable Scry in the addon list on the character select screen.
- `/console scriptErrors 1` to see Lua errors on screen. Optional.
- Keep the game windowed or on a second monitor so reloading on request is cheap.
- A macro or keybind for `/reload` (or `/scry rl`) helps: the loop needs two
  reloads per iteration.

What the agent cannot do, and the human must: start the game, log in, reload,
and perform in-game actions. The tooling deliberately does not send keystrokes
to the game client.

## Local settings

`.scry.local.json` (git-ignored), written by `./dev config`:

```json
{ "wow_dir": "/mnt/c/Program Files (x86)/World of Warcraft", "flavor": "_forever_", "account": null }
```

- `wow_dir`: the folder containing `_forever_`. `SCRY_WOW_DIR` overrides it.
- `flavor`: which client folder to deploy to and read from.
- `account`: `WTF/Account/<name>` folder to read SavedVariables from. Default is
  whichever account's `Scry.lua` was written most recently.

## How the in-game feedback works

The game writes SavedVariables only on `/reload`, logout or exit, and only then
can anything outside the game see addon state. Scry uses that as its debug channel:

- `ScryDevDB` (second SavedVariable) holds the current session's build id,
  captured Lua errors with stack traces, selftest results and a log.
- `./dev deploy` stamps each deployed copy with a unique build id.
- `./dev wait` watches `WTF/Account/*/SavedVariables/Scry.lua` and reports once a
  session of the deployed build has been saved. After a deploy that takes two
  reloads: the first loads the new code (and saves the old session), the second
  saves the new session.
- Screenshots (`/scry shot` in game) land in `<wow>/_forever_/Screenshots`;
  `./dev screenshot` prints the newest one's path.

## Game version and flavor

Pinned in these places; change them together:

| What | Where |
|---|---|
| Interface version the addon declares | `## Interface:` in `Scry/Scry.toc` |
| API reference used by lint, typecheck, tests, `./dev api` | `WOW_UI_BRANCH`, `WOW_UI_REF`, `WOW_ANNOTATIONS_REF` in `tools/docker/Dockerfile` |
| Simulator game product and client build | `WOWLESS_PRODUCT`, `WOWLESS_REF`, `WOW_BUILD`, `WOW_BUILD_HASH`, `WOW_DBDEFS_REF` in `tools/docker/sim.Dockerfile` |
| Default client version in tests | `default_state()` in `tests/wow/init.lua` |
| Client folder for the in-game loop | `flavor` in `.scry.local.json` |

After a WoW patch: `./dev api-update` moves the API reference to the current
client and rebuilds the toolchain; then `./dev check` shows anything the patch
broke. The simulator does not follow automatically: Blizzard's CDN stops serving a
client build once a newer one is out, so after a patch a rebuild of the simulator
image fails until `WOW_BUILD` / `WOW_BUILD_HASH` / `WOW_DBDEFS_REF` in
`tools/docker/sim.Dockerfile` are updated (the comment there says where the
values come from). An already built image keeps working. wowless's support for
the Forever client is young: expect dozens of "errors not involving the addon".

One caveat for WoW: Forever: the Ketho annotations are written for Retail.
They are only used for what Blizzard's own Forever docs and UI source do not
cover (entries marked `[not in Blizzard docs: verify in game]` in `./dev api`),
so an API listed only there may not exist in Forever. Lint accepts it; an
in-game selftest is what proves it.

Sources of the API reference: Blizzard's generated API documentation and UI
source as mirrored at github.com/Gethe/wow-ui-source, and the LuaLS annotations
from github.com/Ketho/vscode-wow-api (MIT) for what Blizzard does not document.
The simulator is github.com/wowless/wowless (MIT), which describes itself as
pre-alpha: treat it as a smoke test, not as ground truth.
