#!/usr/bin/env python3
"""Scry development CLI (host side). Run as ./dev <command>; see ./dev --help.

Needs only Python 3.9+ and Docker on the host. Everything that inspects or runs
addon code is forwarded into a pinned toolchain container (tools/docker/), so
results are identical on Linux, WSL, Windows and CI. Commands that touch the WoW
installation (deploy, wait, report, sv, screenshot) run on the host.
"""
import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "Scry"
DOCKER_DIR = os.path.join(ROOT, "tools", "docker")
LOCAL_CONFIG = os.path.join(ROOT, ".scry.local.json")
STATE_DIR = os.path.join(ROOT, ".scry")
DEPLOY_MARKER = ".scry-deploy.json"
IN_CONTAINER = bool(os.environ.get("SCRY_IN_CONTAINER"))
# Inputs of `check`: if none of these changed since the last green run, the Stop hook skips.
CHECKED_PATHS = [ADDON, "tests", "tools", "schema", ".luacheckrc", ".luarc.json", "stylua.toml"]


def die(message, code=1):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(code)


def note(message):
    print(message, file=sys.stderr, flush=True)


# ------------------------------------------------------------------------ docker
def docker_ok():
    if not shutil.which("docker"):
        return False, "docker not found on PATH"
    p = subprocess.run(["docker", "version", "--format", "{{.Server.Version}}"], capture_output=True, text=True)
    if p.returncode != 0:
        return False, "docker is installed but the daemon is not reachable (is Docker running?)"
    return True, p.stdout.strip()


def image_tag(name, files):
    h = hashlib.sha256()
    for f in files:
        with open(os.path.join(DOCKER_DIR, f), "rb") as fh:
            h.update(f.encode() + b"\0" + fh.read().replace(b"\r\n", b"\n"))
    return f"{name}:{h.hexdigest()[:12]}"


def dev_image():
    return image_tag("scry-dev", ["Dockerfile", "gen_api.lua"])


def sim_image():
    return image_tag("scry-sim", ["sim.Dockerfile"])


def ensure_image(tag, dockerfile, first_time_hint):
    if subprocess.run(["docker", "image", "inspect", tag], capture_output=True).returncode == 0:
        return
    ok, info = docker_ok()
    if not ok:
        die(f"{info}. Run ./dev doctor.")
    note(f"building toolchain image {tag} ({first_time_hint}) ...")
    p = subprocess.run(
        ["docker", "build", "-q", "-f", os.path.join(DOCKER_DIR, dockerfile), "-t", tag, DOCKER_DIR],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    if p.returncode != 0:
        note(p.stdout[-6000:])
        die(f"building {tag} failed (output above)")
    # drop images built from older versions of the Dockerfile
    name = tag.split(":")[0]
    old = subprocess.run(["docker", "images", name, "--format", "{{.Repository}}:{{.Tag}}"], capture_output=True, text=True)
    for other in old.stdout.split():
        if other != tag:
            subprocess.run(["docker", "image", "rm", other], capture_output=True)
    note(f"built {tag}")


def docker_run_args(image, mounts, network=False):
    args = ["docker", "run", "--rm", "-i"]
    if not network:
        args += ["--network", "none"]
    if hasattr(os, "getuid"):
        args += ["-u", f"{os.getuid()}:{os.getgid()}"]
    for src, dst in mounts:
        args += ["-v", f"{src}:{dst}"]
    return args + [image]


def tasks(task_args, stdin_text=None, capture=False):
    """Run tools/tasks.py inside the toolchain container."""
    if IN_CONTAINER:
        cmd = [sys.executable, os.path.join(ROOT, "tools", "tasks.py")] + task_args
    else:
        image = dev_image()
        ensure_image(image, "Dockerfile", "first run or toolchain changed; takes a few minutes")
        cmd = docker_run_args(image, [(ROOT, "/work")]) + ["python3", "tools/tasks.py"] + task_args
    return subprocess.run(
        cmd, cwd=ROOT, input=stdin_text, text=True,
        stdout=subprocess.PIPE if capture else None,
        stdin=None if stdin_text is not None else subprocess.DEVNULL,
    )


# ------------------------------------------------------------- WoW installation
def load_config():
    cfg = {"wow_dir": None, "flavor": "_forever_", "account": None}
    if os.path.exists(LOCAL_CONFIG):
        with open(LOCAL_CONFIG) as f:
            cfg.update(json.load(f))
    if os.environ.get("SCRY_WOW_DIR"):
        cfg["wow_dir"] = os.environ["SCRY_WOW_DIR"]
    return cfg


def wow_candidates():
    tails = [
        "Program Files (x86)/World of Warcraft", "Program Files/World of Warcraft",
        "World of Warcraft", "Games/World of Warcraft", "Battle.net/World of Warcraft",
    ]
    roots = []
    if os.name == "nt":
        roots = [f"{d}:/" for d in "CDEFGH"]
    else:
        roots = sorted(glob.glob("/mnt/[a-z]/")) + ["/Applications/"]
    return [os.path.join(r, t) for r in roots for t in tails]


def find_wow(cfg):
    """-> (flavor dir, how it was found) or (None, reason)"""
    if cfg["wow_dir"]:
        base, how = cfg["wow_dir"], "configured"
    else:
        base = next((c for c in wow_candidates() if os.path.isdir(os.path.join(c, cfg["flavor"]))), None)
        how = "auto-detected"
        if not base:
            return None, "no WoW installation configured or found in the usual places"
    flavor_dir = os.path.join(base, cfg["flavor"])
    if not os.path.isdir(flavor_dir):
        return None, f"{flavor_dir} does not exist (wow_dir {how}; flavor {cfg['flavor']})"
    return flavor_dir, how


def require_wow():
    cfg = load_config()
    flavor_dir, info = find_wow(cfg)
    if not flavor_dir:
        die(
            f"{info}.\nThis command needs the WoW installation. Tell the tooling where it is:\n"
            '  ./dev config --wow-dir "/mnt/c/Program Files (x86)/World of Warcraft"\n'
            "On a machine without WoW only the offline loop (./dev check, ./dev sim) is available."
        )
    return cfg, flavor_dir


def addon_target(flavor_dir):
    return os.path.join(flavor_dir, "Interface", "AddOns", ADDON)


def sv_file(cfg, flavor_dir):
    pattern = os.path.join(flavor_dir, "WTF", "Account", cfg["account"] or "*", "SavedVariables", f"{ADDON}.lua")
    files = glob.glob(pattern)
    return max(files, key=os.path.getmtime) if files else None


def deployed_info(flavor_dir):
    marker = os.path.join(addon_target(flavor_dir), DEPLOY_MARKER)
    if os.path.exists(marker):
        with open(marker) as f:
            return json.load(f)
    return None


def git_rev():
    try:
        sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True)
        if sha.returncode != 0:
            return "nogit"
        dirty = subprocess.run(["git", "status", "--porcelain", "--", ADDON], cwd=ROOT, capture_output=True, text=True)
        return sha.stdout.strip() + ("-dirty" if dirty.stdout.strip() else "")
    except OSError:
        return "nogit"


def source_files():
    src = os.path.join(ROOT, ADDON)
    out = []
    for base, _, files in os.walk(src):
        for f in files:
            out.append(os.path.relpath(os.path.join(base, f), src).replace(os.sep, "/"))
    return sorted(out)


def read_bytes(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def deploy_once(flavor_dir, force):
    addons = os.path.join(flavor_dir, "Interface", "AddOns")
    if not os.path.isdir(addons):
        die(f"{addons} does not exist. Start the game once, or check the configured WoW directory.")
    target = addon_target(flavor_dir)
    previous = deployed_info(flavor_dir)
    if os.path.islink(target):
        die(f"{target} is a symlink. Remove it; ./dev deploy copies files.")
    if os.path.isdir(target) and previous is None and not force:
        die(f"{target} exists but was not created by ./dev deploy (a release install?). Use --force to replace it.")

    build = time.strftime("%Y%m%d-%H%M%S") + "-" + git_rev()
    files = source_files()
    wanted = {f: read_bytes(os.path.join(ROOT, ADDON, f)) for f in files}
    wanted["BuildInfo.lua"] = (
        "-- generated by ./dev deploy\nlocal _, ns = ...\n\n"
        f'ns.build = {{\n\tid = "{build}",\n\tdev = true,\n}}\n'
    ).encode()

    changed = 0
    for rel, data in wanted.items():
        dst = os.path.join(target, rel)
        if rel != "BuildInfo.lua" and read_bytes(dst) != data:
            changed += 1
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(data)
    for base, _, existing in os.walk(target):
        for f in existing:
            rel = os.path.relpath(os.path.join(base, f), target).replace(os.sep, "/")
            if rel not in wanted and rel != DEPLOY_MARKER:
                os.remove(os.path.join(base, f))
                changed += 1

    toc_hash = hashlib.sha256(wanted[f"{ADDON}.toc"]).hexdigest()
    structural = previous is None or previous.get("files") != files or previous.get("toc") != toc_hash
    with open(os.path.join(target, DEPLOY_MARKER), "w") as f:
        json.dump({"build": build, "files": files, "toc": toc_hash}, f)

    print(f"deployed build {build} -> {target} ({changed} file(s) changed)")
    if structural:
        print("NOTE: the TOC or the file list changed. /reload may not pick that up: restart the game client"
              " (or log out to character select and back) if the new build does not show up.")
    return build


# ---------------------------------------------------------------- in-game report
def read_live(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    p = tasks(["svjson"], stdin_text=text, capture=True)
    if p.returncode != 0:
        die(f"could not parse {path}")
    return json.loads(p.stdout)


def fmt_time(t):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) if isinstance(t, (int, float)) else "?"


def print_report(result, deployed, log_lines=25):
    """Print what the last game session recorded. -> 'ok' | 'problems' | 'stale' | 'nodata'"""
    dev = result["data"].get("ScryDevDB")
    if not isinstance(dev, dict) or "session" not in dev:
        print("no ScryDevDB session in the SavedVariables file (addon never loaded, or loaded but failed very early)")
        return "nodata"
    s = dev["session"]
    print(f"session   build {s.get('build')}, addon {s.get('addonVersion')}, game {s.get('gameVersion')} "
          f"({s.get('interface')}), started {fmt_time(s.get('startedAt'))}")
    status = "ok"
    if deployed and s.get("build") != deployed["build"]:
        print(f"build     STALE: the game session ran build {s.get('build')}, but {deployed['build']} is deployed.")
        print("          Everything below describes OLD code.")
        status = "stale"
    elif deployed:
        print("build     matches the deployed build")

    errors = dev.get("errors") or []
    print(f"errors    {len(errors)}")
    for e in errors:
        print(f"  x{e.get('count', 1)}  {e.get('msg')}")
        for line in str(e.get("stack", "")).strip().splitlines()[:10]:
            print(f"        {line.strip()}")

    st = dev.get("selftest")
    if isinstance(st, dict):
        print(f"selftest  {st.get('total', 0) - st.get('failed', 0)}/{st.get('total', 0)} passed (ran {fmt_time(st.get('ranAt'))})")
        for r in st.get("results") or []:
            if not r.get("ok"):
                print(f"  FAIL  {r.get('name')}: {r.get('msg')}")
    else:
        print("selftest  not run in this session (dev builds run it 2s after login; or type /scry selftest)")

    schema_errors = result.get("schemaErrors") or []
    if "ScryDB" not in result["data"]:
        print("schema    ScryDB is missing from the SavedVariables file")
    elif schema_errors:
        print(f"schema    ScryDB VIOLATES schema/ScryDB.schema.json ({len(schema_errors)}):")
        for e in schema_errors[:30]:
            print(f"  {e}")
    else:
        print("schema    ScryDB is valid")

    log = dev.get("log") or []
    if log:
        print(f"log       last {min(len(log), log_lines)} of {len(log)}:")
        for entry in log[-log_lines:]:
            print(f"  {fmt_time(entry.get('t'))[11:]} {entry.get('level', ''):5} {entry.get('msg')}")

    failed_tests = isinstance(st, dict) and st.get("failed", 0) > 0
    if status == "ok" and (errors or failed_tests or schema_errors or "ScryDB" not in result["data"]):
        status = "problems"
    return status


EXIT = {"ok": 0, "problems": 1, "stale": 2, "nodata": 3}


# ---------------------------------------------------------------------- commands
def check_fingerprint():
    h = hashlib.sha256()
    for top in CHECKED_PATHS:
        path = os.path.join(ROOT, top)
        entries = [path] if os.path.isfile(path) else sorted(
            os.path.join(b, f) for b, _, fs in os.walk(path) for f in fs if "__pycache__" not in b
        )
        for e in entries:
            data = read_bytes(e)
            if data is not None:
                h.update(os.path.relpath(e, ROOT).encode() + b"\0" + data)
    return h.hexdigest()


def stamp_path():
    return os.path.join(STATE_DIR, "last-green-check")


def cmd_check(args):
    code = tasks(["check"] + (["--ci"] if args.ci else [])).returncode
    if code == 0 and args.sim:
        code = cmd_sim(args)
    if code == 0:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(stamp_path(), "w") as f:
            f.write(check_fingerprint())  # after formatting, so the stamp matches the tree
    return code


def cmd_test(args):
    return tasks(["test"] + args.busted_args).returncode


def cmd_golden(args):
    return tasks(["golden"]).returncode


def cmd_api(args):
    return tasks(["api", args.pattern, "-n", str(args.limit)] + (["--source"] if args.source else [])).returncode


def cmd_sim(args):
    image = sim_image()
    ensure_image(image, "sim.Dockerfile", "first run of the simulator; downloads WoW UI data and compiles, ~10 minutes")
    cmd = docker_run_args(image, [(os.path.join(ROOT, ADDON), f"/addons/{ADDON}:ro"), (os.path.join(ROOT, "tools"), "/scrytools:ro")])
    return subprocess.run(cmd + ["python3", "/scrytools/sim.py", ADDON], stdin=subprocess.DEVNULL).returncode


def cmd_config(args):
    stored = {}
    if os.path.exists(LOCAL_CONFIG):
        with open(LOCAL_CONFIG) as f:
            stored = json.load(f)
    for key in ("wow_dir", "flavor", "account"):
        value = getattr(args, key)
        if value is not None:
            stored[key] = value or None
    if stored:
        with open(LOCAL_CONFIG, "w") as f:
            json.dump(stored, f, indent=2)
            f.write("\n")
    cfg = load_config()
    print(json.dumps(cfg, indent=2))
    flavor_dir, info = find_wow(cfg)
    print(f"WoW: {flavor_dir} ({info})" if flavor_dir else f"WoW: not found - {info}")
    return 0


def cmd_deploy(args):
    _, flavor_dir = require_wow()
    deploy_once(flavor_dir, args.force)
    if not args.watch:
        print("next: in game type /reload, exercise the change, /reload again; meanwhile run ./dev wait")
        return 0
    print("watching Scry/ for changes (Ctrl-C to stop) ...")

    def snapshot():
        out = {}
        for rel in source_files():
            st = os.stat(os.path.join(ROOT, ADDON, rel))
            out[rel] = (st.st_mtime_ns, st.st_size)
        return out

    last = snapshot()
    try:
        while True:
            time.sleep(0.5)
            now = snapshot()
            if now != last:
                time.sleep(0.2)  # let the editor finish writing
                last = snapshot()
                deploy_once(flavor_dir, True)
    except KeyboardInterrupt:
        return 0


def cmd_report(args):
    cfg, flavor_dir = require_wow()
    path = sv_file(cfg, flavor_dir)
    if not path:
        print("no SavedVariables file for Scry yet: the addon has not been loaded and then /reload-ed or logged out")
        return EXIT["nodata"]
    result = read_live(path)
    if args.json:
        print(json.dumps({"file": path, "deployed": deployed_info(flavor_dir), **result}, indent=2))
        return 0
    print(f"file      {path} (written {fmt_time(os.path.getmtime(path))})")
    return EXIT[print_report(result, deployed_info(flavor_dir), args.log)]


def cmd_wait(args):
    cfg, flavor_dir = require_wow()
    deployed = deployed_info(flavor_dir)
    if not deployed:
        die("nothing deployed yet: run ./dev deploy first")

    def mtime():
        path = sv_file(cfg, flavor_dir)
        return (path, os.path.getmtime(path)) if path else (None, None)

    baseline = mtime()
    deadline = time.time() + args.timeout
    note(f"waiting up to {args.timeout}s for the game to write SavedVariables (/reload or logout) ...")
    while time.time() < deadline:
        time.sleep(0.5)
        current = mtime()
        if current == baseline or current[0] is None:
            continue
        time.sleep(0.5)  # let the client finish writing
        baseline = mtime()
        result = read_live(baseline[0])
        session = (result["data"].get("ScryDevDB") or {}).get("session") or {}
        if session.get("build") != deployed["build"]:
            note(f"SavedVariables written by build {session.get('build')} (not the deployed {deployed['build']}): "
                 "the game has now loaded the new code. Waiting for the next /reload ...")
            continue
        print(f"file      {baseline[0]} (written {fmt_time(baseline[1])})")
        return EXIT[print_report(result, deployed, args.log)]
    print(f"timed out after {args.timeout}s: the game did not write SavedVariables for build {deployed['build']}.\n"
          "Ask the user to /reload in game (twice after a deploy: once to load the new code, once to save its results), "
          "then run ./dev wait again or ./dev report.")
    return 4


def cmd_sv(args):
    if args.file:
        path = args.file
    else:
        cfg, flavor_dir = require_wow()
        path = sv_file(cfg, flavor_dir)
        if not path:
            die("no SavedVariables file for Scry found in the WoW installation")
    result = read_live(path)
    data = result["data"]
    print(json.dumps(data if args.all else data.get(args.var), indent=2, ensure_ascii=False))
    for e in result["schemaErrors"]:
        note(f"schema violation: {e}")
    return 1 if result["schemaErrors"] else 0


def cmd_screenshot(args):
    _, flavor_dir = require_wow()
    shots = glob.glob(os.path.join(flavor_dir, "Screenshots", "*.*"))
    if not shots:
        print("no screenshots found (take one in game with /scry shot or PrintScreen)")
        return 1
    newest = max(shots, key=os.path.getmtime)
    print(f"{newest}\ntaken {fmt_time(os.path.getmtime(newest))}")
    return 0


def cmd_api_update(args):
    path = os.path.join(DOCKER_DIR, "Dockerfile")
    with open(path) as f:
        text = f.read()
    branch = re.search(r"^ARG WOW_UI_BRANCH=(\S+)", text, re.M).group(1)

    def head(repo, ref):
        p = subprocess.run(["git", "ls-remote", repo, ref], capture_output=True, text=True)
        if p.returncode != 0 or not p.stdout.strip():
            die(f"could not resolve {ref} of {repo}")
        return p.stdout.split()[0]

    updates = {
        "WOW_UI_REF": head("https://github.com/Gethe/wow-ui-source", f"refs/heads/{branch}"),
        "WOW_ANNOTATIONS_REF": head("https://github.com/Ketho/vscode-wow-api", "HEAD"),
    }
    changed = False
    for key, sha in updates.items():
        old = re.search(rf"^ARG {key}=(\S+)", text, re.M).group(1)
        if old != sha:
            changed = True
            text = re.sub(rf"^ARG {key}=\S+", f"ARG {key}={sha}", text, flags=re.M)
        print(f"{key}: {old[:12]} -> {sha[:12]}" + ("" if old != sha else " (unchanged)"))
    if not changed:
        return 0
    with open(path, "w", newline="\n") as f:
        f.write(text)
    image = dev_image()
    ensure_image(image, "Dockerfile", "rebuilding with the new API reference")
    version = subprocess.run(
        docker_run_args(image, []) + ["cat", "/opt/wow-api/ui-source/version.txt"], capture_output=True, text=True
    ).stdout.strip()
    print(f"API reference is now game version {version} (branch {branch}).")
    print("next: ./dev check; if the interface number changed, update '## Interface' in Scry/Scry.toc"
          " and the default build in tests/wow/init.lua.")
    return 0


def cmd_doctor(args):
    problems = 0

    def row(ok, label, detail):
        nonlocal problems
        mark = {True: "ok  ", False: "FAIL", None: "--  "}[ok]
        if ok is False:
            problems += 1
        print(f"{mark}  {label}: {detail}")

    print("Offline loop (required): ./dev check, test, api, sim")
    row(sys.version_info >= (3, 9), "python", sys.version.split()[0] + " (need >= 3.9)")
    if IN_CONTAINER:
        row(True, "toolchain", "running inside the toolchain container")
    else:
        ok, info = docker_ok()
        row(ok, "docker", f"server {info}" if ok else info)
        if ok:
            for label, tag in (("toolchain image", dev_image()), ("simulator image", sim_image())):
                present = subprocess.run(["docker", "image", "inspect", tag], capture_output=True).returncode == 0
                row(True if present else None, label, f"{tag} " + ("present" if present else "not built yet (built automatically on first use)"))
    row(bool(shutil.which("git")), "git", shutil.which("git") or "not found")
    wsl = os.path.exists("/proc/version") and "microsoft" in open("/proc/version").read().lower()
    if wsl and ROOT.startswith("/mnt/"):
        row(None, "repo location", f"{ROOT} is on the Windows filesystem: Docker bind mounts are slow there, "
                                   "keep the repo inside the WSL filesystem (e.g. ~/src/scry)")

    print("\nIn-game loop (needs a WoW installation on this machine): ./dev deploy, wait, report, sv, screenshot")
    cfg = load_config()
    flavor_dir, info = find_wow(cfg)
    if not flavor_dir:
        row(None, "wow", f"{info}. Set it with: ./dev config --wow-dir <path>")
    else:
        row(True, "wow", f"{flavor_dir} ({info})")
        dep = deployed_info(flavor_dir)
        row(True if dep else None, "deployed addon", f"build {dep['build']}" if dep else "not deployed yet (./dev deploy)")
        sv = sv_file(cfg, flavor_dir)
        row(True if sv else None, "SavedVariables", f"{sv} (written {fmt_time(os.path.getmtime(sv))})" if sv else
            "none yet (appears after the addon was loaded once and the game did /reload or logout)")
    print("\n" + ("environment has problems (FAIL lines above)" if problems else "environment ok"))
    return 1 if problems else 0


def cmd_hook(args):
    """Claude Code Stop hook: do not let an agent finish while ./dev check is red."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        payload = {}
    if payload.get("stop_hook_active"):
        return 0
    try:
        with open(stamp_path()) as f:
            if f.read() == check_fingerprint():
                return 0
    except OSError:
        pass
    if not IN_CONTAINER and not docker_ok()[0]:
        note("dev: docker is not available, skipping the automatic ./dev check")
        return 0
    p = subprocess.run([sys.executable, os.path.abspath(__file__), "check"], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if p.returncode == 0:
        return 0
    note("./dev check is failing. Fix it before finishing (or, if it cannot be fixed, say so explicitly "
         "and explain why):\n" + (p.stdout + p.stderr)[-6000:])
    return 2


def main():
    parser = argparse.ArgumentParser(prog="dev", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True, metavar="command")

    p = sub.add_parser("check", help="format, lint (incl. WoW API existence), tests, data contract, typecheck. Run after every change")
    p.add_argument("--ci", action="store_true", help="verify formatting instead of applying it")
    p.add_argument("--sim", action="store_true", help="also run ./dev sim")
    p.set_defaults(fn=cmd_check)
    p = sub.add_parser("test", help="run tests only; extra args go to busted (e.g. tests/spec/core_spec.lua, --filter=level)")
    p.add_argument("busted_args", nargs=argparse.REMAINDER)
    p.set_defaults(fn=cmd_test)
    sub.add_parser("golden", help="regenerate tests/golden/Scry.lua after an intended data contract change").set_defaults(fn=cmd_golden)
    p = sub.add_parser("api", help="search the WoW API reference (functions, events, enums, widget methods)")
    p.add_argument("pattern", help="case-insensitive regex, e.g. 'C_TradeSkillUI', 'event.*TRADE_SKILL', ':RegisterEvent'")
    p.add_argument("--source", action="store_true", help="search Blizzard's UI source code instead (usage examples)")
    p.add_argument("-n", "--limit", type=int, default=40)
    p.set_defaults(fn=cmd_api)
    sub.add_parser("sim", help="load the addon into a headless simulation of the real WoW UI and report Lua errors").set_defaults(fn=cmd_sim)
    p = sub.add_parser("deploy", help="copy the addon into the WoW installation as a dev build")
    p.add_argument("--watch", action="store_true", help="keep running and redeploy on every change")
    p.add_argument("--force", action="store_true", help="replace an existing non-dev install of the addon")
    p.set_defaults(fn=cmd_deploy)
    p = sub.add_parser("wait", help="block until the game saves results of the deployed build, then print the report")
    p.add_argument("--timeout", type=int, default=540)
    p.add_argument("--log", type=int, default=25, help="number of log lines to show")
    p.set_defaults(fn=cmd_wait)
    p = sub.add_parser("report", help="print errors, selftest results, schema validity and log of the last game session")
    p.add_argument("--json", action="store_true")
    p.add_argument("--log", type=int, default=25, help="number of log lines to show")
    p.set_defaults(fn=cmd_report)
    p = sub.add_parser("sv", help="print the live SavedVariables as JSON (and validate ScryDB against the schema)")
    p.add_argument("--var", default="ScryDB")
    p.add_argument("--all", action="store_true", help="all variables in the file")
    p.add_argument("--file", help="convert this SavedVariables file instead of the live one")
    p.set_defaults(fn=cmd_sv)
    sub.add_parser("screenshot", help="print the path of the newest in-game screenshot").set_defaults(fn=cmd_screenshot)
    p = sub.add_parser("config", help="show or set the local WoW installation settings (.scry.local.json)")
    p.add_argument("--wow-dir", dest="wow_dir", help="folder that contains _forever_ etc.")
    p.add_argument("--flavor", help="_forever_ (default), _retail_, _classic_, ...")
    p.add_argument("--account", help="WTF account folder name, if there are several (empty string = newest)")
    p.set_defaults(fn=cmd_config)
    sub.add_parser("doctor", help="check the development environment").set_defaults(fn=cmd_doctor)
    sub.add_parser("api-update", help="bump the pinned WoW API reference to the current game version").set_defaults(fn=cmd_api_update)
    p = sub.add_parser("hook", help=argparse.SUPPRESS)
    p.add_argument("event", choices=["stop"])
    p.set_defaults(fn=cmd_hook)

    args = parser.parse_args()
    sys.exit(args.fn(args))


if __name__ == "__main__":
    main()
