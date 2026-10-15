#!/usr/bin/env python3
"""Normal-stream deadline, cancellation and descriptor-lifecycle checks."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import time

from audit_cli_interop import nrrd_samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    binary, out = args.binary.resolve(), args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {"status": "running", "commands": [], "assertions": [],
              "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
              "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}

    def save():
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")

    def record(argv, code, stderr, elapsed, condition):
        report["commands"].append({"argv": list(map(str, argv)), "exit_code": code,
                                   "stderr": stderr.decode(errors="replace"),
                                   "elapsed_seconds": elapsed, "condition": condition})
        save()

    def assertion(label):
        report["assertions"].append(label)
        save()

    try:
        samples = tuple((i * 73) & 65535 for i in range(512 * 512))
        source = out / "normal-512.nrrd"
        source.write_bytes(b"NRRD0005\ntype: uint16\ndimension: 2\nsizes: 512 512\nencoding: raw\nendian: little\n\n" +
                           struct.pack("<" + str(len(samples)) + "H", *samples))
        jpeg = out / "normal-512.jpg"
        argv = [binary, "encode", "-i", source, "-o", jpeg]
        started = time.monotonic()
        result = subprocess.run(argv, capture_output=True, timeout=10)
        record(argv, result.returncode, result.stderr, time.monotonic() - started, "ordinary valid input")
        assert result.returncode == 0
        assertion("Normal image encoded successfully")

        for cancellation in (False, True):
            destination = out / ("cancelled.nrrd" if cancellation else "timed-out.nrrd")
            rd, wr = os.pipe()
            original = fcntl.fcntl(rd, fcntl.F_GETFL)
            argv = [binary, "decode", "-i", "-", "--input-format", "jpeg", "-o", destination,
                    "--timeout", "5" if cancellation else "0.15"]
            started = time.monotonic()
            proc = subprocess.Popen(argv, stdin=rd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                if cancellation:
                    time.sleep(0.1)
                    proc.send_signal(signal.SIGINT)
                stdout, stderr = proc.communicate(timeout=3)
                record(argv, proc.returncode, stderr, time.monotonic() - started,
                       "SIGINT while awaiting stdin" if cancellation else "stdin remains open without data")
                assert proc.returncode == (130 if cancellation else 5)
                assert not stdout and not destination.exists()
                assert (fcntl.fcntl(rd, fcntl.F_GETFL) & os.O_NONBLOCK) == (original & os.O_NONBLOCK)
                assertion("Stdin cancellation" if cancellation else "Stdin deadline")
                assertion("Inherited stdin blocking mode restored")
            finally:
                if proc.poll() is None:
                    proc.kill(); proc.wait()
                os.close(rd); os.close(wr)

        # The receiver owns its pipe but temporarily does not consume a valid output image.
        rd, wr = os.pipe()
        original = fcntl.fcntl(wr, fcntl.F_GETFL)
        argv = [binary, "decode", "-i", jpeg, "-o", "-", "--output-format", "nrrd", "--timeout", "0.5"]
        started = time.monotonic()
        proc = subprocess.Popen(argv, stdout=wr, stderr=subprocess.PIPE)
        try:
            _, stderr = proc.communicate(timeout=3)
            record(argv, proc.returncode, stderr, time.monotonic() - started, "normal output receiver paused")
            assert proc.returncode == 5
            # Darwin also changes a non-O_NONBLOCK status bit on an ordinary pipe
            # write. A direct Python os.write control established that behaviour.
            assert (fcntl.fcntl(wr, fcntl.F_GETFL) & os.O_NONBLOCK) == (original & os.O_NONBLOCK)
            assertion("Output backpressure obeys command deadline")
            assertion("Inherited stdout blocking mode restored")
        finally:
            if proc.poll() is None:
                proc.kill(); proc.wait()
            os.close(wr); os.close(rd)

        argv = [binary, "decode", "-i", jpeg, "-o", "-", "--output-format", "nrrd", "--timeout", "5"]
        started = time.monotonic()
        proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        chunks = []
        try:
            while True:
                block = proc.stdout.read(4096)
                if not block:
                    break
                chunks.append(block)
                time.sleep(0.001)
            stderr = proc.stderr.read()
            proc.wait(timeout=3)
            record(argv, proc.returncode, stderr, time.monotonic() - started, "slow receiver drains 4 KiB chunks")
            assert proc.returncode == 0
            assert nrrd_samples(b"".join(chunks)) == (512, 512, samples)
            assertion("Slow receiver preserves complete image samples")
        finally:
            if proc.poll() is None:
                proc.kill(); proc.wait()
            proc.stdout.close(); proc.stderr.close()
        assert not list(out.glob(".swiftjli-tmp-*"))
        assertion("No temporary output remains after deadline or cancellation")
        report["status"] = "passed"
    except BaseException as error:
        report.update(status="failed", failure=repr(error))
        raise
    finally:
        save()
    print(f"{len(report['commands'])} commands; {len(report['assertions'])} I/O assertions passed")


if __name__ == "__main__":
    main()
