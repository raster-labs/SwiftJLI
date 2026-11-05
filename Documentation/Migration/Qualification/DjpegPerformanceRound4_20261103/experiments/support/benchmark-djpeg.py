#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compare original and candidate SwiftJLI CLIs with djpeg on identical inputs.

The corpus is the synthetic November 2026 benchmark corpus. Timings include
process launch, input reads, decode and PNM output to /dev/null. This is not an
in-process codec benchmark. Correctness gates precede all accepted timings.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import statistics
import subprocess
import time


CASES = [
    ("lossless16", 512, 0, None),
    ("lossless16", 2048, 0, None),
    ("dct12", 512, 4, 12),
    ("rgb8", 512, 2, None),
    ("progressiveRGB8", 512, 2, None),
]
WHITESPACE = b" \t\r\n\v\f"


def parse_pnm(data):
    offset, tokens = 0, []
    while len(tokens) < 4:
        while offset < len(data) and data[offset] in WHITESPACE:
            offset += 1
        if offset < len(data) and data[offset] == ord("#"):
            while offset < len(data) and data[offset] not in b"\r\n":
                offset += 1
            continue
        start = offset
        while offset < len(data) and data[offset] not in WHITESPACE:
            offset += 1
        if start == offset:
            raise ValueError("Incomplete PNM header")
        tokens.append(data[start:offset].decode("ascii"))
    if offset >= len(data):
        raise ValueError("Missing PNM raster separator")
    magic, width, height, maximum = tokens[0], *map(int, tokens[1:])
    components = {"P5": 1, "P6": 3}.get(magic, 0)
    if components == 0 or min(width, height, maximum) <= 0 or maximum > 65535:
        raise ValueError("Unsupported PNM layout")
    sample_bytes = 1 if maximum < 256 else 2
    expected = width * height * components * sample_bytes
    # A lone CR separator followed by an LF-valued pixel is valid too. Use
    # the exact raster length to distinguish that from a CRLF line ending.
    separator = 1
    if data[offset:offset + 2] == b"\r\n" and len(data) - offset - 2 == expected:
        separator = 2
    payload = data[offset + separator:]
    if len(payload) != expected:
        raise ValueError("Incorrect PNM raster length")
    samples = list(payload) if sample_bytes == 1 else [
        int.from_bytes(payload[i:i + 2], "big") for i in range(0, len(payload), 2)]
    return (magic, width, height, maximum), samples


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def stats(values):
    ordered = sorted(values)
    return {"samples": values, "median": statistics.median(values),
            "p95": ordered[max(0, (95 * len(values) + 99) // 100 - 1)],
            "minimum": ordered[0], "maximum": ordered[-1]}


def run_bounded(command, timeout, **kwargs):
    # Kill the complete group on timeout, including /usr/bin/time's child.
    # Killing only the wrapper can leave a decoder running and its pipes open.
    with subprocess.Popen(command, start_new_session=True, **kwargs) as process:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
            raise
        completed = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
        completed.check_returncode()
        return completed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--djpeg", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--warmups", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument("--rounds", type=int, default=2)
    parser.add_argument("--matrix", choices=["original", "lossless-patterns"], default="original",
                        help="Original CLI cases or all 16 flat/ramp/noise/mixed lossless cases")
    parser.add_argument("--command-timeout", type=float, default=60,
                        help="Maximum seconds per subprocess, including its child processes (default: 60)")
    args = parser.parse_args()
    if min(args.warmups, args.iterations, args.rounds) < 1:
        parser.error("Counts must be positive")
    if not math.isfinite(args.command_timeout) or args.command_timeout <= 0:
        parser.error("Command timeout must be finite and positive")
    paths = {name: getattr(args, name).resolve() for name in ("baseline", "candidate", "djpeg")}
    result = {"status": "running", "method": __doc__, "arguments": vars(args).copy(),
              "records": [], "excluded": []}
    result["arguments"] = {k: str(v) if isinstance(v, Path) else v for k, v in result["arguments"].items()}
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save():
        args.output.write_text(json.dumps(result, indent=2) + "\n")

    def run(command, **kwargs):
        result["activeCommand"] = command
        return run_bounded(command, args.command_timeout, **kwargs)

    save()
    try:
        result["binarySHA256"] = {name: digest(path) for name, path in paths.items()}
        result["djpegVersion"] = run([str(paths["djpeg"]), "-version"],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout.strip()
        rss_pattern = re.compile(rb"\n\s*(\d+)\s+maximum resident set size")
        cases = CASES if args.matrix == "original" else [
            (pattern, size, 0, None) for pattern in ("flat", "ramp", "noise", "mixed")
            for size in (19, 512, 2048, 3072)]
        for round_number in range(1, args.rounds + 1):
            for profile, size, tolerance, precision in cases:
                fixture = args.fixtures / f"{profile}-{size}.jpg"
                commands = {
                    name: ([str(path)] + (["-precision", str(precision)] if precision else []) + [str(fixture)])
                    if name == "djpeg" else [str(path), "decode", "-i", str(fixture), "-o", "-", "--output-format", "pnm"]
                    for name, path in paths.items()}
                outputs, resource_rejections = {}, {}
                for name, command in commands.items():
                    try:
                        completed = run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    except subprocess.CalledProcessError as error:
                        if args.matrix != "lossless-patterns" or name == "djpeg" or error.returncode != 5:
                            raise
                        resource_rejections[name] = {
                            "exitCode": error.returncode,
                            "stderr": error.stderr.decode("utf-8", errors="replace")}
                        continue
                    if completed.stderr:
                        raise RuntimeError(f"Unexpected {name} diagnostics: {completed.stderr!r}")
                    outputs[name] = completed.stdout
                if resource_rejections:
                    if set(resource_rejections) != {"baseline", "candidate"}:
                        raise RuntimeError(f"Baseline/candidate resource admission changed: {profile}-{size}")
                    result["excluded"].append({"round": round_number, "profile": profile, "size": size,
                        "inputSHA256": digest(fixture), "inputBytes": fixture.stat().st_size,
                        "commands": commands, "resourceRejections": resource_rejections,
                        "reason": "Both SwiftJLI builds reject the case under the unchanged CLI workspace limit; no accepted timing."})
                    print(f"excluded {profile}-{size}: both SwiftJLI builds returned resource limit exit 5", flush=True)
                    save()
                    continue
                parsed = {name: parse_pnm(data) for name, data in outputs.items()}
                if parsed["baseline"] != parsed["candidate"]:
                    raise RuntimeError(f"Candidate samples/layout changed: {profile}-{size}")
                if parsed["candidate"][0] != parsed["djpeg"][0]:
                    raise RuntimeError(f"Comparator layout differs: {profile}-{size}")
                difference = max(abs(a - b) for a, b in zip(parsed["candidate"][1], parsed["djpeg"][1]))
                record = {"round": round_number, "profile": profile, "size": size,
                          "inputSHA256": digest(fixture), "inputBytes": fixture.stat().st_size,
                          "validation": {"baselineCandidateExactSamples": True,
                                         "baselineCandidateExactPNM": outputs["baseline"] == outputs["candidate"],
                                         "maximumDjpegSampleDifference": difference, "tolerance": tolerance,
                                         "outputSHA256": {name: hashlib.sha256(data).hexdigest() for name, data in outputs.items()}},
                          "commands": commands}
                del outputs, parsed
                if difference > tolerance:
                    record["reason"] = "Predeclared sample tolerance exceeded; no accepted timing."
                    result["excluded"].append(record)
                    print(f"excluded {profile}-{size}: difference {difference} > {tolerance}", flush=True)
                    save()
                    continue
                durations, rss = {name: [] for name in paths}, {name: [] for name in paths}
                result["partial"] = {"record": record, "elapsedSeconds": durations, "peakRSSBytes": rss}
                names = list(paths)
                for iteration in range(-args.warmups, args.iterations):
                    # Rotate first position and reverse on alternate cycles so no
                    # implementation consistently benefits from ordering.
                    shift = (iteration + round_number) % len(names)
                    order = names[shift:] + names[:shift]
                    if ((iteration + round_number) // len(names)) % 2:
                        order.reverse()
                    for name in order:
                        if iteration < 0:
                            run(commands[name], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                            continue
                        started = time.perf_counter_ns()
                        completed = run(["/usr/bin/time", "-l", *commands[name]],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                        elapsed = (time.perf_counter_ns() - started) / 1e9
                        match = rss_pattern.search(completed.stderr)
                        if not match:
                            raise RuntimeError(f"Missing Darwin RSS: {completed.stderr!r}")
                        durations[name].append(elapsed)
                        rss[name].append(int(match[1]))
                for name in paths:
                    record[name] = {"elapsedSeconds": stats(durations[name]), "peakRSSBytes": stats(rss[name]),
                                    "medianMPixelsPerSecond": size * size / statistics.median(durations[name]) / 1e6}
                result["records"].append(record)
                result.pop("partial", None)
                save()
                print(f"round {round_number} {profile}-{size}: " + ", ".join(
                    f"{name} {statistics.median(durations[name])*1000:.3f} ms / {statistics.median(rss[name])/2**20:.2f} MiB"
                    for name in paths), flush=True)
        result["status"] = "passed"
        result.pop("activeCommand", None)
        save()
    except BaseException as error:
        result["status"] = "failed"
        result["failure"] = {"type": type(error).__name__, "message": str(error)}
        if isinstance(error, subprocess.CalledProcessError):
            result["failure"]["exitCode"] = error.returncode
        diagnostic = getattr(error, "stderr", None)
        if diagnostic:
            result["failure"]["stderrTail"] = (diagnostic.decode("utf-8", errors="replace")
                                                   if isinstance(diagnostic, bytes) else diagnostic)[-8192:]
        save()
        raise


if __name__ == "__main__":
    main()
