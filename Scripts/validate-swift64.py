#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate this standalone codec package and record the selected toolchain."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

# Contract 0.5.0: Swift 6.2 is the manifest minimum and 6.4 the qualified
# primary toolchain, so both are accepted here. Pinning one exact build string
# made this script unrunnable on every machine but the one that produced the
# original evidence, and pinning a preview Xcode made it unrunnable in CI at
# all. The exact toolchain identity is still recorded in the report below; it
# is evidence, not an admission gate.
ACCEPTED_SWIFT = (
    re.compile(r"Apple Swift version 6\.2(\.\d+)?\b"),
    re.compile(r"Apple Swift version 6\.4(\.\d+)?\b"),
)
DEFAULT_CHECKS = "debug,release,consumer,repetition,sbom"
CHECKS = {"debug", "release", "consumer", "repetition", "sbom", "asan", "tsan"}
REPETITION_FILTER = r"(?i)(cancell|writer|lease|retain|concurrent|publication)"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New evidence directory; never reuse an earlier run")
    parser.add_argument("--checks", default=DEFAULT_CHECKS, help="Comma-separated debug,release,consumer,repetition,sbom,asan,tsan; or all")
    parser.add_argument("--sanitizers", action="store_true", help="Add separate AddressSanitizer and ThreadSanitizer runs")
    parser.add_argument("--jobs", type=int, default=2, help="Build workers per command (1..32; default 2)")
    parser.add_argument("--repetitions", type=int, default=5, help="Fixed repetitions for selected lifetime/cancellation cases (2..50)")
    parser.add_argument("--disable-package-sandbox", action="store_true", help="Explicit nested SwiftPM sandbox workaround; does not change the host sandbox")
    parser.add_argument("--build-engine", choices=("swiftbuild", "native"), default="swiftbuild",
                        help="Build engine; swiftbuild falls back to native where it cannot run (recorded)")
    parser.add_argument("--timeout", type=int, default=600, help="Maximum seconds per command")
    args = parser.parse_args()
    selected = CHECKS.copy() if args.checks == "all" else set(args.checks.split(","))
    if args.sanitizers:
        selected.update({"asan", "tsan"})
    if not selected or not selected <= CHECKS or not 2 <= args.repetitions <= 50 or args.timeout < 1 or not 1 <= args.jobs <= 32:
        parser.error("Use recognised nonempty checks, 2..50 repetitions, 1..32 jobs and a positive timeout")
    repo = Path(__file__).resolve().parent.parent
    manifest = (repo / "Package.swift").read_text()
    match = re.search(r'name:\s*"(SwiftJ2K|SwiftJLS|SwiftJXL|SwiftJLI)"', manifest)
    if not match:
        parser.error("Expected a standalone successor package")
    name = match.group(1)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = (args.output or repo / ".build" / "swift64-evidence" / f"{stamp}-{os.getpid()}").resolve()
    if output.exists():
        parser.error("Output already exists; use a new directory to preserve previous evidence")
    output.mkdir(parents=True)
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = env.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    env["CLANG_MODULE_CACHE_PATH"] = str(output / "clang-cache")
    env["SWIFTPM_MODULECACHE_OVERRIDE"] = str(output / "swift-cache")
    report = {"package": name, "repository": str(repo), "started_utc": stamp,
              "developer_dir": env["DEVELOPER_DIR"], "build_engine": args.build_engine,
              "requested_build_engine": args.build_engine,
              "accepted_swift": [pattern.pattern for pattern in ACCEPTED_SWIFT],
              "selected_checks": sorted(selected), "not_run_checks": sorted(CHECKS - selected),
              "package_sandbox_disabled": args.disable_package_sandbox, "build_jobs": args.jobs,
              "commands": [], "test_runs": [], "sboms": [], "open_gates": [], "status": "running"}

    def save() -> None:
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")

    # Swift Build names each product's intermediates directory after the product.
    # Where a product's name differs from a target's only in case, those are one
    # directory on a case-insensitive filesystem — the macOS default — and the two
    # overwrite each other's dependency files: the compiler then fails with
    # "unable to open dependencies file", and only builds that include both are
    # affected. The executable was renamed to `swiftjli-cli` on 23 September 2026
    # precisely so this cannot happen, but the check stays: it is cheap, it states
    # the invariant the name now satisfies, and it explains the fallback rather
    # than letting a future rename reintroduce a confusing build failure.
    probe = output / "CaseProbe"
    probe.mkdir()
    case_insensitive = (output / "caseprobe").exists()
    probe.rmdir()
    report["filesystem_case_insensitive"] = case_insensitive
    # A package legitimately reuses one spelling for its package, product and
    # target, so repetition is not the test. The defect is two *distinct*
    # spellings that are equal when case-folded, which is what "differ by case
    # alone" means and what shares a directory.
    spellings: dict[str, set[str]] = {}
    for declared in set(re.findall(r'name:\s*"([^"]+)"', manifest)):
        spellings.setdefault(declared.lower(), set()).add(declared)
    collisions = sorted(folded for folded, group in spellings.items() if len(group) > 1)
    report["case_folded_name_collisions"] = collisions
    engine = args.build_engine
    if engine == "swiftbuild" and case_insensitive and collisions:
        engine = "native"
        report["build_engine"] = engine
        report["open_gates"].append(
            "Swift Build engine unusable here: manifest names " + ", ".join(repr(c) for c in collisions)
            + " differ only in case and share an intermediates directory on a case-insensitive "
            "filesystem, so targets overwrite each other's dependency files. Built with the native "
            "engine instead; Swift Build coverage is unexecuted, not passed.")

    def run(label: str, argv: list[str], cwd: Path = repo) -> str:
        log = output / f"{label}.log"
        print(f"{name}: {label}", flush=True)
        started = time.monotonic()
        entry = {"label": label, "argv": argv, "cwd": str(cwd), "log": log.name}
        report["commands"].append(entry)
        try:
            result = subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, timeout=args.timeout)
            text = result.stdout
            entry["exit_code"] = result.returncode
        except subprocess.TimeoutExpired as error:
            text = error.stdout or ""
            if isinstance(text, bytes):
                text = text.decode(errors="replace")
            entry["exit_code"] = None
            entry["timed_out"] = True
        log.write_text(text)
        entry["seconds"] = round(time.monotonic() - started, 3)
        save()
        if entry.get("timed_out") or entry["exit_code"] != 0:
            raise RuntimeError(f"{label} failed; see {log}")
        return text

    def swift(verb: str, scratch: str, package: Path = repo) -> list[str]:
        command = ["xcrun", "swift", verb, "--package-path", str(package),
                   "--scratch-path", str(output / "build" / scratch),
                   "--cache-path", str(output / "cache"), "--config-path", str(output / "config"),
                   "--security-path", str(output / "security"), "--build-system", engine, "--jobs", str(args.jobs)]
        if args.disable_package_sandbox:
            command.append("--disable-sandbox")
        return command

    # Do not silently exclude future XCTest tests to work around an environment failure.
    xctest = any(re.search(r"\bimport\s+XCTest\b|:\s*XCTestCase\b", p.read_text())
                 for p in (repo / "Tests").rglob("*.swift"))
    frameworks = ["--enable-swift-testing", "--enable-xctest" if xctest else "--disable-xctest"]
    report["xctest_detected"] = xctest
    inventory: dict[str, list[str]] = {}

    def discover(label: str, config: str, extra: list[str]) -> list[str]:
        text = run(label + "-discovery", swift("test", label) + ["-c", config] + extra + ["list"] + frameworks)
        names = [line.strip() for line in text.splitlines() if line.startswith(name + "Tests.")]
        if not names:
            raise RuntimeError(f"{label}: zero discovered tests")
        inventory[label] = names
        report.setdefault("test_inventory", {})[label] = names
        save()
        return names

    def test(label: str, config: str, extra: list[str], repeat: bool = False) -> None:
        names = inventory[label]
        if repeat:
            names = [item for item in names if re.search(REPETITION_FILTER, item)]
            if not names:
                raise RuntimeError("Repetition filter selected zero discovered tests")
        repetitions = args.repetitions if repeat else 1
        # `--maximum-repetitions` arrived after Swift 6.2, which contract 0.5.0 keeps
        # as an accepted toolchain. Where the option is absent, repeat the run itself
        # instead of skipping the check: its purpose is to show that the lifetime and
        # cancellation cases survive repeated execution, and separate executions
        # demonstrate that. Every iteration is validated and recorded individually.
        in_process = repeat and supports_repetitions
        iterations = 1 if (in_process or not repeat) else repetitions
        for iteration in range(1, iterations + 1):
            suffix = "" if iterations == 1 else f"-{iteration}"
            xml = output / f"{label}-tests{suffix}.xml"
            argv = swift("test", label) + ["-c", config] + extra + frameworks + ["--skip-build", "--xunit-output", str(xml)]
            if repeat:
                argv += ["--filter", REPETITION_FILTER]
            if in_process:
                argv += ["--maximum-repetitions", str(repetitions)]
            # No repeat-until-pass option: every failure remains a failure.
            counts = None
            try:
                text = run(label + "-tests" + suffix, argv)
            finally:
                if xml.exists():
                    document = ET.parse(xml)
                    cases = document.findall(".//testcase")
                    counts = {"executed_declarations": len(cases),
                              "failed_declarations": sum(c.find("failure") is not None or c.find("error") is not None for c in cases),
                              "skipped_declarations": sum(c.find("skipped") is not None for c in cases)}
                    counts["passed_declarations"] = counts["executed_declarations"] - counts["failed_declarations"] - counts["skipped_declarations"]
                    report["test_runs"].append({"label": label + suffix, "discovered_declarations": len(names),
                        "repetitions": repetitions if in_process else 1,
                        "iteration": iteration, "iterations": iterations, "xml": xml.name, **counts})
                    save()
            if counts is None or counts["executed_declarations"] == 0:
                raise RuntimeError(f"{label}: no executed tests in xUnit evidence")
            if counts["executed_declarations"] != len(names):
                raise RuntimeError(f"{label}: discovered/executed declaration counts differ")
            if counts["failed_declarations"] or counts["skipped_declarations"]:
                raise RuntimeError(f"{label}: failed or skipped cases require disposition")
        # xUnit collapses parameterised cases/repetitions. Logs retain actual case starts.
        passed_cases = 0
        for line in text.splitlines():
            if re.search(r"\bTest (?!run\b|case\b).+ passed after", line):
                parameterised = re.search(r"with (\d+) test cases passed", line)
                passed_cases += int(parameterised.group(1)) if parameterised else 1
        record = report["test_runs"][-1]
        record["swift_testing_passed_case_executions"] = passed_cases * (repetitions if in_process else 1)
        record["parameterised_case_start_events"] = len(re.findall(r"\bTest case passing .* started", text))
        record["repetition_start_events"] = len(re.findall(r"started \(repetition \d+\)", text))
        record["count_note"] = "xUnit counts declarations; passing Swift Testing case executions include argument cases and fixed repetitions. Raw logs retain every event. XCTest counts remain separate."
        if iterations > 1:
            record["iteration_note"] = (f"Repetitions ran as {iterations} separate executions because this toolchain "
                                        "has no --maximum-repetitions; the fields above describe the last of them, "
                                        "and each iteration has its own entry and log.")
        save()

    try:
        actual_swift = run("swift-version", ["xcrun", "swift", "--version"])
        # Xcode is recorded when present. It is not required: the Linux gates and
        # a swift.org toolchain on macOS have no xcodebuild, and demanding one
        # would fail those runs for a reason unrelated to what is being checked.
        try:
            actual_xcode = run("xcode-version", ["xcrun", "xcodebuild", "-version"])
        except Exception:
            actual_xcode = "unavailable"
        if not any(pattern.search(actual_swift) for pattern in ACCEPTED_SWIFT):
            raise RuntimeError(
                "Swift 6.2 or 6.4 is required by contract 0.5.0 PLAT-01; found: "
                + actual_swift.strip().splitlines()[0]
            )
        report["toolchain_swift"] = actual_swift.strip()
        report["toolchain_xcode"] = actual_xcode.strip()
        report["source_commit"] = run("source-commit", ["git", "rev-parse", "HEAD"]).strip()
        report["working_tree"] = run("working-tree", ["git", "status", "--short"])
        report["manifest_sha256"] = hashlib.sha256(manifest.encode()).hexdigest()
        source_files = [repo / "Package.swift"]
        for folder in ("Sources", "Tests", "Scripts"):
            source_files.extend(p for p in (repo / folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts)
        report["source_files_sha256"] = {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source_files)}
        resolved = repo / "Package.resolved"
        report["package_resolved_sha256"] = hashlib.sha256(resolved.read_bytes()).hexdigest() if resolved.exists() else None
        help_texts = {}
        for verb in ("build", "test"):
            help_texts[verb] = run(f"swift-{verb}-help", swift(verb, "help") + ["--help"])
        # `swift package` is a container command, not a leaf one. Swift Argument
        # Parser accepts `--help` on it only when nothing precedes it: once any
        # option is given it is looking for a subcommand and rejects the flag
        # with "Unknown option '--help'". The `help` subcommand takes the same
        # options, works in every form and prints identical text.
        help_texts["package"] = run("swift-package-help", swift("package", "help") + ["help"])
        # SBOM support arrived after Swift 6.2, which contract 0.5.0 keeps as an
        # accepted toolchain: on 6.2 neither `swift build --sbom-spec` nor the
        # `generate-sbom` subcommand exists. Probe for the option this script
        # actually uses rather than assuming. Failing hard here would make the
        # script unrunnable on an accepted toolchain, which is the exact fault
        # the 0.5.0 relaxation recorded at the top of this file removed, and
        # POL-08 makes a missing environment an unexecuted gate, not a pass.
        sbom_supported = "--sbom-spec" in help_texts["build"]
        report["sbom_supported"] = sbom_supported
        supports_repetitions = "--maximum-repetitions" in help_texts["test"]
        report["repetitions_in_process"] = supports_repetitions
        if sbom_supported:
            run("swift-sbom-help", swift("package", "help") + ["generate-sbom", "--help"])
        run("target-info", ["xcrun", "swiftc", "-print-target-info"])
        # Decide the engine once, before anything is built with it, because the
        # build and test gates below share a scratch directory per label and
        # cannot change engine midway. Measured on Apple Swift 6.2.3: `swift test
        # list` under the Swift Build engine prints its build log and no test
        # identifiers at all, so every gate below would have nothing to run and
        # would report zero tests. Whether a later toolchain enumerates them is
        # not asserted here — this probes rather than assumes, and the result is
        # recorded either way.
        if engine == "swiftbuild":
            probe_text = run("swiftbuild-enumeration-probe",
                             swift("test", "engine-probe") + ["-c", "debug", "list"] + frameworks)
            enumerated = sum(1 for line in probe_text.splitlines() if line.startswith(name + "Tests."))
            report["swiftbuild_enumerated_tests"] = enumerated
            if enumerated == 0:
                engine = "native"
                report["build_engine"] = engine
                report["open_gates"].append(
                    "Swift Build engine enumerated no tests on this toolchain ("
                    + report["toolchain_swift"].splitlines()[0].strip()
                    + "): `swift test list` returned its build log and no test identifiers, so the gates "
                    "below would have had nothing to run. Built and tested with the native engine instead; "
                    "Swift Build coverage is unexecuted, not passed.")
            save()
        for config in ("debug", "release"):
            if config in selected:
                # Each invocation owns a fresh output tree. The second build reuses exactly that tree.
                command = swift("build", config) + ["-c", config]
                run(config + "-clean-build", command)
                run(config + "-incremental-build", command)
                discover(config, config, [])
                test(config, config, [])
        if "consumer" in selected:
            consumer = output / "consumer"
            (consumer / "Sources/Consumer").mkdir(parents=True)
            package_path = json.dumps(str(repo))
            (consumer / "Package.swift").write_text(
                # Contract 0.5.0 returned the manifest minimum to 6.2 and the Apple
                # floor to 26.0, and 0.9.0 (D3) confirmed 26.0. A generated consumer
                # pinned above the package it consumes cannot resolve on the
                # toolchain this script accepts, which is the whole point of the
                # check: it must mirror the real floor, not a reversed one.
                '// swift-tools-version: 6.2\nimport PackageDescription\n'
                'let package = Package(name: "FreshConsumer", platforms: [.macOS("26.0")],\n'
                f' dependencies: [.package(name: "{name}", path: {package_path})],\n'
                f' targets: [.executableTarget(name: "Consumer", dependencies: [.product(name: "{name}", package: "{name}")])],\n'
                ' swiftLanguageModes: [.v6])\n')
            # Exercise the maintained public codec example. The former Milestone 1
            # stub asserted that encoding was unavailable and rejected the real
            # implementation. Explicit package naming also permits isolated
            # checkout directories whose basename differs from the module name.
            consumer_source = repo / "Examples/IndependentConsumer/Sources/IndependentConsumer/main.swift"
            (consumer / "Sources/Consumer/main.swift").write_bytes(consumer_source.read_bytes())
            report["consumer_source_sha256"] = hashlib.sha256(consumer_source.read_bytes()).hexdigest()
            run("fresh-local-consumer", swift("run", "consumer", consumer) + ["Consumer"])
            report["open_gates"].append("Fresh URL-based consumer resolution is separate from this local consumer check")
        if "repetition" in selected:
            discover("repetition", "debug", [])
            test("repetition", "debug", [], repeat=True)
        for label, sanitizer in (("asan", "address"), ("tsan", "thread")):
            if label in selected:
                extra = ["--sanitize", sanitizer]
                discover(label, "debug", extra)
                test(label, "debug", extra)
        if "sbom" in selected and not sbom_supported:
            report["open_gates"].append(
                "SBOM generation is unavailable on this toolchain: `swift build` has no "
                "--sbom-spec option before Swift 6.4. No spdx or cyclonedx SBOM was produced, "
                "and the sbom check is unexecuted rather than passed.")
            save()
        if "sbom" in selected and sbom_supported:
            for spec in ("spdx", "cyclonedx"):
                destination = output / "sboms" / spec
                text = run("sbom-" + spec, swift("build", "sbom") + ["-c", "release", "--product", name,
                    "--sbom-spec", spec, "--sbom-output-dir", str(destination), "--sbom-filter", "all"])
                files = sorted(destination.glob("*.json"))
                if not files:
                    raise RuntimeError(f"No {spec} build-associated SBOM emitted")
                for path in files:
                    json.loads(path.read_text())
                    report["sboms"].append({"path": str(path.relative_to(output)),
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "build_associated": True})
                if "skipping SBOM validation" in text:
                    report["open_gates"].append(f"{spec}: installed SwiftPM schema bundle unavailable; SBOM emitted but schema validation skipped")
                save()
        report["status"] = "passed_requested_checks"
        # Print them: an open gate that only ever reaches report.json is easy to
        # read as a pass, and POL-08 turns on the difference.
        for gate in report["open_gates"]:
            print(f"{name}: unexecuted gate: {gate}", flush=True)
        print(f"Evidence: {output / 'report.json'}", flush=True)
        return 0
    except (RuntimeError, OSError, ValueError, ET.ParseError) as error:
        report["status"] = "failed"
        report["failure"] = str(error)
        print(str(error), file=sys.stderr)
        return 1
    finally:
        report["finished_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        save()


if __name__ == "__main__":
    sys.exit(main())
