#!/usr/bin/env python3
"""Independent normal-input interoperability checks for the Milestone 4 CLI."""
import argparse
import hashlib
import json
import pathlib
import struct
import subprocess


def nrrd_samples(data):
    normal = data.find(b"\n\n")
    windows = data.find(b"\r\n\r\n")
    if windows >= 0 and (normal < 0 or windows < normal):
        header, payload = data[:windows], data[windows + 4:]
    elif normal >= 0:
        header, payload = data[:normal], data[normal + 2:]
    else:
        raise AssertionError("Missing attached NRRD header separator")
    lines = header.decode("ascii").splitlines()
    assert lines[0] in {"NRRD0001", "NRRD0002", "NRRD0003", "NRRD0004", "NRRD0005"}
    fields = {}
    for line in lines[1:]:
        if line.startswith("#"):
            continue
        key, value = line.split(":", 1)
        fields[key.lower()] = value.strip()
    assert fields["type"].lower() in {"uint16", "uint16_t", "ushort", "unsigned short", "unsigned short int"}
    assert fields["dimension"] == "2" and fields["encoding"].lower() == "raw"
    width, height = map(int, fields["sizes"].split())
    assert len(payload) == width * height * 2
    order = {"little": "<", "big": ">"}[fields["endian"].lower()]
    return width, height, struct.unpack(order + str(width * height) + "H", payload)


def pgm_samples(data):
    magic, shape, maximum, payload = data.split(b"\n", 3)
    assert magic == b"P5" and maximum == b"65535"
    width, height = map(int, shape.split())
    assert len(payload) == width * height * 2
    return width, height, struct.unpack(">" + str(width * height) + "H", payload)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=pathlib.Path, required=True)
    parser.add_argument("--fixtures", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    binary, fixtures, output = args.binary.resolve(), args.fixtures.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"binary": str(binary), "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
              "runner_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
              "scope": "Normal full-precision UInt16 greyscale interoperability and file/stream publication",
              "commands": [], "assertions": [], "status": "running"}

    def save():
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(argv, expected=0, payload=None):
        result = subprocess.run(list(map(str, argv)), input=payload, capture_output=True, timeout=30)
        report["commands"].append({"argv": list(map(str, argv)), "exit_code": result.returncode,
                                   "expected_exit_code": expected, "stdout_bytes": len(result.stdout),
                                   "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
                                   "stderr": result.stderr.decode("utf-8", errors="replace")})
        save()
        assert result.returncode == expected, report["commands"][-1]
        return result

    def passed(name):
        report["assertions"].append(name)
        save()

    try:
        for source in sorted(fixtures.glob("grey16-*-*.nrrd")):
            expected = nrrd_samples(source.read_bytes())
            encoded = output / (source.stem + ".jpg")
            decoded = output / (source.stem + " decoded λ.nrrd")
            oracle = output / (source.stem + ".pgm")
            run([binary, "encode", "-i", source, "--input-format", "nrrd", "--output-format", "jpeg",
                 "--mode", "lossless", "-o", encoded])
            run(["/opt/homebrew/bin/djpeg", "-strict", "-pnm", "-outfile", oracle, encoded])
            assert pgm_samples(oracle.read_bytes()) == expected
            passed(source.name + ": CLI encode independently decoded exactly")
            run([binary, "decode", "-i", encoded, "--input-format", "jpeg", "--output-format", "nrrd", "-o", decoded])
            assert nrrd_samples(decoded.read_bytes()) == expected
            passed(source.name + ": file decode preserves dimensions and all UInt16 samples")
        for encoded in sorted(fixtures.glob("grey16-*-oracle.jpg")):
            source = fixtures / (encoded.name.removesuffix("-oracle.jpg") + "-little.nrrd")
            result = run([binary, "decode", "-i", "-", "--input-format", "jpeg", "--output-format", "nrrd", "-o", "-", "--json"], payload=encoded.read_bytes())
            assert nrrd_samples(result.stdout) == nrrd_samples(source.read_bytes())
            assert isinstance(json.loads(result.stderr), dict)
            passed(encoded.name + ": independent JPEG decoded exactly through pipes; JSON confined to stderr")
            result = run([binary, "inspect", "-i", encoded, "--json"])
            assert isinstance(json.loads(result.stdout), dict)
            passed(encoded.name + ": inspect returns structured output")
            result = run([binary, "validate", "-i", encoded, "--json"])
            assert isinstance(json.loads(result.stdout), dict)
            passed(encoded.name + ": independent conformant JPEG validates")
        source = fixtures / "grey16-17x13-little.nrrd"
        destination = output / "existing output λ.jpg"
        destination.write_bytes(b"preserve existing file")
        argv = [binary, "encode", "-i", source, "--input-format", "nrrd", "--output-format", "jpeg", "-o", destination]
        run(argv, expected=6)
        assert destination.read_bytes() == b"preserve existing file"
        passed("Existing output is preserved without explicit overwrite")
        run(argv + ["--overwrite"])
        assert destination.read_bytes().startswith(b"\xff\xd8")
        passed("Explicit overwrite publishes a JPEG")
        report["status"] = "passed"
    except BaseException as error:
        report["status"] = "failed"
        report["failure"] = repr(error)
        raise
    finally:
        save()
    print(f"{len(report['commands'])} commands; {len(report['assertions'])} independent assertions passed")


if __name__ == "__main__":
    main()
