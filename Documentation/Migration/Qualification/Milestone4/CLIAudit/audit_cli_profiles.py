#!/usr/bin/env python3
"""Independent normal-image CLI checks against libjpeg-turbo."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess


def read_pnm(data):
    fields = []
    pos = 0
    while len(fields) < 4:
        while data[pos] in b" \t\r\n":
            pos += 1
        if data[pos] == 35:
            pos = data.index(b"\n", pos) + 1
            continue
        end = pos
        while data[end] not in b" \t\r\n":
            end += 1
        fields.append(data[pos:end])
        pos = end
    assert data[pos] in b" \t\r\n"
    payload = data[pos + 1:]
    magic, width, height, maximum = fields
    width, height, maximum = map(int, (width, height, maximum))
    components = {b"P5": 1, b"P6": 3}[magic]
    count = width * height * components
    if maximum < 256:
        assert len(payload) == count
        samples = tuple(payload)
    else:
        assert len(payload) == count * 2
        samples = struct.unpack(">" + str(count) + "H", payload)
    return (width, height, components, maximum), samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    binary = args.binary.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {"binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
              "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "status": "running", "commands": [], "assertions": []}

    def save():
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(argv):
        result = subprocess.run([str(x) for x in argv], capture_output=True, timeout=60)
        report["commands"].append({"argv": [str(x) for x in argv], "exit_code": result.returncode,
                                   "stderr": result.stderr.decode(errors="replace"),
                                   "stdout_sha256": hashlib.sha256(result.stdout).hexdigest()})
        save()
        assert result.returncode == 0, report["commands"][-1]
        return result

    def compare(a, b, tolerance, label):
        da, sa = read_pnm(a.read_bytes())
        db, sb = read_pnm(b.read_bytes())
        assert da == db, (da, db)
        delta = max(abs(x - y) for x, y in zip(sa, sb))
        assert delta <= tolerance, (label, delta, tolerance)
        report["assertions"].append({"name": label, "maximum_difference": delta, "limit": tolerance})
        save()

    try:
        for components, bits in [(1, 2), (1, 8), (1, 12), (1, 16), (3, 8), (3, 12), (3, 16)]:
            width, height = 19, 15
            maximum = (1 << bits) - 1
            values = [(i * 197 + (i // width) * 31) & maximum for i in range(width * height * components)]
            values[:2] = [0, maximum]
            ext = "pgm" if components == 1 else "ppm"
            name = f"c{components}-b{bits}"
            source = out / (name + "." + ext)
            source.write_bytes(f"P{5 if components == 1 else 6}\n{width} {height}\n{maximum}\n".encode() +
                               (bytes(values) if bits <= 8 else struct.pack(">" + str(len(values)) + "H", *values)))
            for producer in ("cli", "oracle"):
                jpeg = out / f"{name}-{producer}.jpg"
                if producer == "cli":
                    run([binary, "encode", "-i", source, "-o", jpeg, "--mode", "lossless"])
                else:
                    run(["/opt/homebrew/bin/cjpeg", "-strict", "-precision", bits, "-lossless", "1,0", "-outfile", jpeg, source])
                oracle = out / f"{name}-{producer}-oracle.{ext}"
                decoded = out / f"{name}-{producer}-cli.{ext}"
                run(["/opt/homebrew/bin/djpeg", "-strict", "-pnm", "-outfile", oracle, jpeg])
                run([binary, "decode", "-i", jpeg, "-o", decoded])
                compare(source, oracle, 0, name + " " + producer + " JPEG exact independent decode")
                compare(source, decoded, 0, name + " " + producer + " JPEG exact CLI decode")
            if bits in (8, 12):
                for progressive in (False, True):
                    name_dct = f"{name}-dct-{'progressive' if progressive else 'sequential'}"
                    for producer in ("cli", "oracle"):
                        jpeg = out / f"{name_dct}-{producer}.jpg"
                        if producer == "cli":
                            run([binary, "encode", "-i", source, "-o", jpeg, "--mode", "lossy", "--quality", "90",
                                 "--subsampling", "greyscale" if components == 1 else "444",
                                 "--progressive", "successive-approximation" if progressive else "sequential"])
                        else:
                            extra = ["-progressive"] if progressive else []
                            run(["/opt/homebrew/bin/cjpeg", "-strict", "-precision", bits, "-quality", "90", "-sample", "1x1", *extra, "-outfile", jpeg, source])
                        oracle = out / f"{name_dct}-{producer}-oracle.{ext}"
                        decoded = out / f"{name_dct}-{producer}-cli.{ext}"
                        run(["/opt/homebrew/bin/djpeg", "-strict", "-dct", "int", "-pnm", "-outfile", oracle, jpeg])
                        run([binary, "decode", "-i", jpeg, "-o", decoded])
                        compare(oracle, decoded, 2 if bits == 8 else 4, name_dct + " " + producer + " independent DCT decode")
        source = out / "c1-b12.pgm"
        near = out / "bounded-error.jpg"
        decoded = out / "bounded-error.pgm"
        run([binary, "encode", "-i", source, "-o", near, "--mode", "near-lossless", "--max-error", "5"])
        result = run([binary, "inspect", "-i", near, "--json"])
        info = json.loads(result.stdout)
        assert info["pointTransform"] == 2 and info["isLossless"] is False
        report["assertions"].append({"name": "Nonzero point transform is not reported lossless"})
        run([binary, "decode", "-i", near, "-o", decoded])
        compare(source, decoded, 3, "near-lossless actual point transform bound")
        report["status"] = "passed"
    except BaseException as error:
        report.update(status="failed", failure=repr(error))
        raise
    finally:
        save()
    print(f"{len(report['commands'])} commands; {len(report['assertions'])} independent assertions passed")


if __name__ == "__main__":
    main()
