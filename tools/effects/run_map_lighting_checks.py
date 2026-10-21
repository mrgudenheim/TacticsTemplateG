#!/usr/bin/env python3
"""Run the map PSX-lighting + tint-sink regression and score it properly.

    run_map_lighting_checks.py --godot <engine>

🔴 THE EXIT CODE IS NOT THE VERDICT, for the reason `run_integration_probe.py`
already documents and this scene reproduced while it was being written: a GDScript
runtime error kills the enclosing METHOD, not the process. A bad `bool(...)` call in
`_check_parse` silently dropped two checks and the scene went on to print a verdict
for the remaining ones. So the check COUNT is scored, not just the marker.

The scene needs a real framebuffer (it reads pixels) and a ROM path configured in
`user://external_data_paths.cfg`. Never pass --headless.
"""
import argparse, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = "res://tools/effects/map_lighting_regression.tscn"
EXPECTED_CHECKS = 22

ap = argparse.ArgumentParser()
ap.add_argument("--godot", required=True)
ap.add_argument("--timeout", type=int, default=900)
args = ap.parse_args()

proc = subprocess.run([args.godot, "--path", str(ROOT), SCENE],
                      capture_output=True, text=True, timeout=args.timeout)
out = proc.stdout + proc.stderr
ok = len(re.findall(r"^MAPLIGHT: ok ", out, re.M))
bad = re.findall(r"^MAPLIGHT: FAIL .*$", out, re.M)
passed = "MAPLIGHT: PASS" in out

problems = []
if not passed:
    problems.append("no `MAPLIGHT: PASS` marker — the scene aborted or failed")
if ok != EXPECTED_CHECKS:
    problems.append(f"ran {ok} checks, expected {EXPECTED_CHECKS} — an abort drops the TOTAL, not just the verdict")
problems += bad

for line in re.findall(r"^MAPLIGHT: ARM .*$|^MAPLIGHT: flat-vs-lit .*$", out, re.M):
    print(line)
if problems:
    print(f"MAP_LIGHTING: FAIL ({len(problems)})")
    for p in problems:
        print("   " + p)
    sys.exit(1)
print(f"MAP_LIGHTING: PASS ({ok} checks, engine exit {proc.returncode})")
