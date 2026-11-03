#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Failure-only evidence collection. The original swift-test step remains failed;
# a debugger reproduction never replaces its exit status or qualification result.
set -eu

python3 - "$@" <<'PY'
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

if len(sys.argv) < 2:
    raise SystemExit("usage: diagnose-macos-test-crash.sh OUTPUT_DIRECTORY [swift test arguments]")
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
marker = output / "started"
started = marker.stat().st_mtime if marker.exists() else time.time()
arguments = sys.argv[2:] or ["-c", "release"]
report = {"purpose": "diagnosis only; original release-test failure is retained",
          "testArguments": arguments}

def collect_crashes():
    destination = output / "crash-reports"
    destination.mkdir(exist_ok=True)
    for directory in (Path.home() / "Library/Logs/DiagnosticReports",
                      Path("/Library/Logs/DiagnosticReports")):
        if not directory.exists():
            continue
        for pattern in ("swiftpm-testing-helper*", "SwiftJLIPackageTests*", "xctest*"):
            for source in directory.glob(pattern):
                try:
                    if source.is_file() and source.stat().st_mtime >= started:
                        shutil.copy2(source, destination / source.name)
                except OSError as error:
                    print(f"Could not retain {source.name}: {error}", flush=True)

collect_crashes()
try:
    compiler = Path(subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip())
    helper = compiler.parent.parent / "libexec/swift/pm/swiftpm-testing-helper"
    binary_directory = Path(subprocess.check_output(
        ["swift", "build", "-c", "release", "--show-bin-path"], text=True).strip())
    bundle = binary_directory / "SwiftJLIPackageTests.xctest/Contents/MacOS/SwiftJLIPackageTests"
    if not helper.is_file() or not bundle.is_file():
        raise RuntimeError(f"Expected existing helper/bundle unavailable: {helper}; {bundle}")

    # Launch the already-built Swift Testing bundle through the same helper used
    # by SwiftPM. Do not filter, rebuild, serialise, suppress or retry tests to pass.
    # LLDB's failure-only commands run after the debugger catches the native crash.
    command = ["xcrun", "lldb", "--no-lldbinit", "--batch",
               "--one-line", "settings set target.disable-aslr false",
               "--one-line", "run",
               "--one-line-on-crash", "thread backtrace all",
               "--one-line-on-crash", "register read",
               "--one-line-on-crash", "image list",
               "--", str(helper), "--test-bundle-path", str(bundle),
               *arguments, str(bundle), "--testing-library", "swift-testing"]
    report["command"] = command
    with (output / "lldb.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            report["debuggerExitCode"] = process.wait(timeout=240)
        except subprocess.TimeoutExpired:
            report["timedOutSeconds"] = 240
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            report["debuggerExitCode"] = process.returncode
    # A successful debugger exit does not imply the inferior test process passed.
except (OSError, RuntimeError, subprocess.SubprocessError) as error:
    report["diagnosticError"] = str(error)
finally:
    collect_crashes()
    (output / "diagnostic.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
PY
