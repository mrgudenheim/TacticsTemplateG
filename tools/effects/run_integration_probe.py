#!/usr/bin/env python3
"""Run the TacticsG Effects integration probe and score it properly.

    run_integration_probe.py --godot <engine>

🔴 THE EXIT CODE IS NOT THE VERDICT, and that was measured rather than assumed.
Seeding `effects_cast_host.gd` to drop its ability-id range check made the probe
throw `Out of bounds get index '-1'` and ABORT at check 16 of 31 — a GDScript
runtime error kills the method, not the process. With `--quit-after` the engine
then exited **0**, having printed no verdict at all. A runner that trusted the
exit code would have called that a pass.

So three things are required, and the middle one is the one that catches an abort:
  * the `PROBE: PASS` marker is present,
  * the number of `PROBE: ok` lines equals EXPECTED_CHECKS,
  * no `PROBE: FAIL` line appears.
"""
import argparse, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = "res://tools/effects/ttg_integration_probe.tscn"
EXPECTED_CHECKS = 31

ap = argparse.ArgumentParser()
ap.add_argument("--godot", required=True)
ap.add_argument("--quit-after", default="400")
args = ap.parse_args()

proc = subprocess.run([args.godot, "--path", str(ROOT), SCENE, "--quit-after", args.quit_after],
                      capture_output=True, text=True, timeout=600)
out = proc.stdout + proc.stderr
ok = len(re.findall(r"^PROBE: ok ", out, re.M))
bad = re.findall(r"^PROBE: FAIL .*$", out, re.M)
passed = "PROBE: PASS" in out

problems = []
if not passed:
    problems.append("no `PROBE: PASS` marker — the probe aborted or failed")
if ok != EXPECTED_CHECKS:
    problems.append(f"ran {ok} checks, expected {EXPECTED_CHECKS} — an abort drops the TOTAL, not just the verdict")
problems += bad

for line in bad:
    print(line)
if problems:
    print(f"INTEGRATION_PROBE: FAIL ({len(problems)})")
    for p in problems:
        print("   " + p)
    sys.exit(1)
print(f"INTEGRATION_PROBE: PASS ({ok} checks, engine exit {proc.returncode})")
