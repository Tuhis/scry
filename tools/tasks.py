#!/usr/bin/env python3
"""Tasks that run INSIDE the toolchain container. Do not call directly: use ./dev.

tools/dev.py (host side) forwards here; this file may assume lua5.1, luacheck,
busted, stylua, lua-language-server, ripgrep and /opt/wow-api exist.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API_DIR = os.environ.get("WOW_API_DIR", "/opt/wow-api")
ADDON = "Scry"
SCHEMA = "schema/ScryDB.schema.json"
GOLDEN = "tests/golden/Scry.lua"
LUA_DIRS = [ADDON, "tests", "tools/lua", "tools/docker"]
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
MAX_OUTPUT_LINES = 120


def run(cmd, stdin=None, env=None):
    p = subprocess.run(
        cmd, cwd=ROOT, input=stdin, text=True, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    return p.returncode, ANSI.sub("", p.stdout)


def addon_files():
    out = []
    for base, _, files in os.walk(os.path.join(ROOT, ADDON)):
        out += [os.path.relpath(os.path.join(base, f), ROOT) for f in files if f.endswith(".lua")]
    return sorted(out)


# ---------------------------------------------------------------- SavedVariables
def sv_to_json(text):
    """SavedVariables file text -> dict of its globals (raw, see tools/lua/sv2json.lua)."""
    p = subprocess.run(["lua5.1", "tools/lua/sv2json.lua"], cwd=ROOT, input=text, text=True, capture_output=True)
    if p.returncode != 0:
        raise ValueError(p.stderr.strip() or "sv2json failed")
    return json.loads(p.stdout)


def load_schema():
    with open(os.path.join(ROOT, SCHEMA)) as f:
        return json.load(f)


def coerce(value, schema, root):
    """Resolve Lua-table ambiguity using the schema: {} <-> [] and array-looking maps."""
    while isinstance(schema, dict) and "$ref" in schema:
        node = root
        for part in schema["$ref"].lstrip("#/").split("/"):
            node = node[part]
        schema = node
    if not isinstance(schema, dict):
        return value
    kind = schema.get("type")
    if kind == "array":
        if value == {}:
            value = []
        if isinstance(value, list):
            return [coerce(v, schema.get("items", {}), root) for v in value]
    elif kind == "object":
        if isinstance(value, list):
            value = {str(i + 1): v for i, v in enumerate(value)}
        if isinstance(value, dict):
            out = {}
            for k, v in value.items():
                sub = schema.get("properties", {}).get(k)
                if sub is None:
                    for pattern, s in schema.get("patternProperties", {}).items():
                        if re.search(pattern, k):
                            sub = s
                            break
                if sub is None:
                    sub = schema.get("additionalProperties", {})
                out[k] = coerce(v, sub, root)
            return out
    return value


def validate(db, schema):
    import jsonschema

    validator = jsonschema.Draft202012Validator(schema)
    errors = []
    for e in sorted(validator.iter_errors(db), key=lambda e: list(e.absolute_path)):
        path = "ScryDB" + "".join(f"[{p!r}]" if isinstance(p, str) else f"[{p}]" for p in e.absolute_path)
        errors.append(f"{path}: {e.message}")
    return errors


def load_sv(text):
    """-> (globals dict with ScryDB coerced by the schema, list of schema violations)"""
    data = sv_to_json(text)
    schema = load_schema()
    errors = []
    if "ScryDB" in data:
        data["ScryDB"] = coerce(data["ScryDB"], schema, schema)
        errors = validate(data["ScryDB"], schema)
    return data, errors


# ------------------------------------------------------------------------- steps
def step_fmt(ci=False):
    cmd = ["stylua"] + (["--check"] if ci else []) + LUA_DIRS + [".luacheckrc"]
    return run(cmd)


def step_lint():
    return run(["luacheck", "--no-color", "--codes", "-q"] + LUA_DIRS)


def step_events():
    return run(["lua5.1", "tools/lua/eventcheck.lua"] + addon_files())


def step_test(extra=(), update_golden=False):
    env = dict(os.environ)
    if update_golden:
        env["SCRY_UPDATE_GOLDEN"] = "1"
    cmd = ["busted", "--lpath=./?.lua;./?/init.lua", "-o", "plainTerminal"] + list(extra)
    if not any(not a.startswith("-") for a in extra):
        cmd.append("tests/spec")
    return run(cmd, env=env)


def step_contract():
    path = os.path.join(ROOT, GOLDEN)
    if not os.path.exists(path):
        return 1, f"{GOLDEN} missing: run ./dev golden"
    with open(path) as f:
        try:
            data, errors = load_sv(f.read())
        except ValueError as e:
            return 1, str(e)
    if "ScryDB" not in data:
        return 1, f"{GOLDEN} does not define ScryDB"
    if errors:
        hint = f"\nThe addon output and {SCHEMA} disagree. Fix whichever is wrong (see docs/DATA_CONTRACT.md)."
        return 1, "\n".join(errors) + hint
    return 0, ""


def step_typecheck():
    log = "/tmp/luals"
    code, out = run([
        "lua-language-server", "--check", os.path.join(ROOT, ADDON),
        "--configpath", os.path.join(ROOT, ".luarc.json"),
        "--checklevel=Warning", "--check_format=json", f"--logpath={log}", f"--metapath={log}/meta",
    ])
    report = os.path.join(log, "check.json")
    problems = []
    if os.path.exists(report):
        with open(report) as f:
            found = json.load(f)
            for uri, diags in found.items() if isinstance(found, dict) else []:
                rel = uri.split("/work/")[-1] if "/work/" in uri else uri
                for d in diags:
                    line = d["range"]["start"]["line"] + 1
                    message = d["message"].splitlines()[0]
                    problems.append(f"{rel}:{line}: {message} ({d.get('code', '')})")
        os.remove(report)
    if problems:
        return 1, "\n".join(sorted(problems))
    if code != 0:
        return code, out
    return 0, ""


def run_steps(steps):
    failed = []
    for name, fn in steps:
        start = time.time()
        code, out = fn()
        took = time.time() - start
        if code == 0:
            print(f"ok    {name} ({took:.1f}s)")
        else:
            failed.append(name)
            print(f"FAIL  {name} ({took:.1f}s)")
            lines = out.rstrip().splitlines()
            if len(lines) > MAX_OUTPUT_LINES:
                lines = lines[:MAX_OUTPUT_LINES] + [f"... {len(lines) - MAX_OUTPUT_LINES} more lines"]
            print("\n".join("      " + line for line in lines))
        sys.stdout.flush()
    return failed


# ---------------------------------------------------------------------- commands
def cmd_check(args):
    steps = [
        ("format" + (" (verify)" if args.ci else " (auto-applied)"), lambda: step_fmt(args.ci)),
        ("lint: luacheck + WoW API existence", step_lint),
        ("events: subscribed events exist", step_events),
        ("test: busted against the offline WoW environment", step_test),
        ("contract: golden SavedVariables match the schema", step_contract),
        ("typecheck: lua-language-server + WoW annotations", step_typecheck),
    ]
    failed = run_steps(steps)
    if failed:
        print(f"\nCHECK FAILED ({len(failed)} of {len(steps)} steps)")
        return 1
    print("\nCHECK PASSED")
    return 0


def cmd_test(args):
    code, out = step_test(args.busted_args)
    print(out.rstrip())
    return code


def cmd_golden(args):
    code, out = step_test(["tests/spec/contract_spec.lua"], update_golden=True)
    if code != 0:
        print(out.rstrip())
        return code
    code, out = step_contract()
    print(f"updated {GOLDEN}" if code == 0 else f"updated {GOLDEN}, but it violates the schema:\n{out}")
    return code


def cmd_api(args):
    if args.source:
        code, out = run([
            "sh", "-c",
            'cd "$1/ui-source/Interface/AddOns" && rg --no-heading -n -i -M 220 -g "*.lua" -g "*.xml" -- "$2" .',
            "sh", API_DIR, args.pattern,
        ])
    else:
        code, out = run(["rg", "-i", "-M", "600", "--", args.pattern, os.path.join(API_DIR, "index.txt")])
    lines = out.rstrip().splitlines() if out.strip() else []
    for line in lines[: args.limit]:
        print(line)
    if len(lines) > args.limit:
        print(f"... {len(lines) - args.limit} more matches (narrow the pattern or raise -n)")
    if not lines:
        print("no matches" + ("" if args.source else ". Not in the API reference = assume it does not exist in this client."))
        return 1
    return 0


def cmd_svjson(args):
    try:
        data, errors = load_sv(sys.stdin.read())
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 2
    json.dump({"data": data, "schemaErrors": errors}, sys.stdout)
    return 0


def main():
    parser = argparse.ArgumentParser(prog="tasks.py")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("check")
    p.add_argument("--ci", action="store_true")
    p.set_defaults(fn=cmd_check)
    p = sub.add_parser("test")
    p.add_argument("busted_args", nargs=argparse.REMAINDER)
    p.set_defaults(fn=cmd_test)
    sub.add_parser("golden").set_defaults(fn=cmd_golden)
    p = sub.add_parser("api")
    p.add_argument("pattern")
    p.add_argument("--source", action="store_true")
    p.add_argument("-n", "--limit", type=int, default=40)
    p.set_defaults(fn=cmd_api)
    sub.add_parser("svjson").set_defaults(fn=cmd_svjson)
    args = parser.parse_args()
    sys.exit(args.fn(args))


if __name__ == "__main__":
    main()
