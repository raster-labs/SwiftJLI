#!/usr/bin/env python3
"""Reproducible cold-process macOS caller-storage allocation check."""
from pathlib import Path
import argparse, base64, hashlib, json, os, platform, re, subprocess, time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    args = parser.parse_args()
    output, scratch = args.output.resolve(), args.scratch.resolve()
    if output.exists() or scratch.exists():
        parser.error('output and scratch must both be fresh paths')
    if output == scratch or output in scratch.parents or scratch in output.parents:
        parser.error('output and scratch must be disjoint directories')
    output.mkdir(parents=True); scratch.mkdir(parents=True)
    receipt = {'scope': 'cold public operation; caller/setup/bootstrap excluded; not a performance test',
               'platform': platform.platform(), 'commands': [], 'cases': [], 'passed': False,
               'sources': {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT/'Sources').rglob('*.swift'))}}
    def save(): (output/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    def run(argv, name, env=None):
        started = time.time()
        r = subprocess.run(list(map(str, argv)), cwd=ROOT, env=env, capture_output=True, timeout=300)
        (output/(name+'.stdout')).write_bytes(r.stdout); (output/(name+'.stderr')).write_bytes(r.stderr)
        receipt['commands'].append({'argv': list(map(str, argv)), 'cwd': str(ROOT), 'exitCode': r.returncode,
                                    'elapsedSeconds': time.time()-started, 'logPrefix': name})
        save()
        if r.returncode: raise RuntimeError(f'{name}: exit {r.returncode}')
        return r
    save()
    try:
        run(['xcrun','swift','--version'], 'swift-version')
        run(['xcrun','swift','build','--package-path', HERE,'--scratch-path', scratch/'build',
             '--jobs','2','-c','release'], 'build')
        binary = scratch/'build/out/Products/Release/QualifiedJPEGProbe'
        if not binary.is_file():
            candidates = list((scratch/'build').glob('*/release/QualifiedJPEGProbe'))
            if len(candidates) != 1: raise RuntimeError('Cannot locate unique release executable')
            binary = candidates[0]
        library = scratch/'libheap.dylib'
        run(['xcrun','clang','-Wall','-Wextra','-Werror','-O2','-dynamiclib',HERE/'heap.c','-o',library], 'interposer-build')
        lossless_source = ROOT/'Tests/SwiftJLITests/Native/LosslessRestartTests.swift'
        text = lossless_source.read_text().split('static let cjpegRestart12: [UInt8] = [',1)[1].split(']',1)[0]
        (output/'lossless.jpg').write_bytes(bytes(int(v,16) for v in re.findall(r'0x([0-9A-Fa-f]+)',text)))
        rgb_source = ROOT/'Tests/SwiftJLITests/ChromaReferenceFixtures.swift'
        text = rgb_source.read_text().split('Fixture(name: "baseline_422_64x18"',1)[1]
        (output/'rgb.jpg').write_bytes(base64.b64decode(re.search(r'jpeg: "([^"]+)"',text).group(1)))
        profile_source = ROOT/'Sources/SwiftJLI/Qualified/QualifiedXYBProfile.swift'
        literal = profile_source.read_text().split('"""',2)[1]
        icc = bytes.fromhex(''.join(re.findall(r'[0-9a-f]{2,}', literal)))
        rgb = (output/'rgb.jpg').read_bytes()
        payload = b'ICC_PROFILE\0' + bytes([1,1]) + icc
        (output/'xyb-labelled.jpg').write_bytes(rgb[:2] + b'\xff\xe2' + (len(payload)+2).to_bytes(2,'big') + payload + rgb[2:])
        receipt['xybFixtureConstruction'] = 'Existing synthetic RGB fixture with canonical XYB ICC inserted to exercise the cold colour branch; allocation test only, not a colour oracle.'
        receipt['xybProfileSourceSHA256'] = sha(profile_source)
        receipt['fixtures'] = {p.name: {'sha256': sha(p), 'bytes': p.stat().st_size} for p in output.glob('*.jpg')}
        receipt['fixtureSources'] = {str(p.relative_to(ROOT)): sha(p) for p in [lossless_source,rgb_source]}
        receipt['harness'] = {str(p.relative_to(ROOT)): sha(p) for p in HERE.rglob('*') if p.is_file() and '.build' not in p.parts and '.swiftpm' not in p.parts}
        receipt['binarySHA256'] = sha(binary); receipt['interposerSHA256'] = sha(library)
        for mode in ['control','swift-control','inspect-lossless','decode-lossless','inspect-rgb','decode-rgb',
                     'inspect-lossless-cancel','decode-lossless-cancel','inspect-rgb-cancel','decode-rgb-cancel',
                     'inspect-lossless-invalid','decode-lossless-invalid','inspect-rgb-invalid','decode-rgb-invalid',
                     'decode-lossless-entropy','decode-rgb-entropy','inspect-rgb-missing-dqt','decode-rgb-missing-dqt',
                     'inspect-rgb-xyb','decode-rgb-xyb']:
            rgb = 'rgb' in mode
            argv = [binary,mode,output/('xyb-labelled.jpg' if mode.endswith('-xyb') else 'rgb.jpg' if rgb else 'lossless.jpg'),64*18*12 if rgb else 13*9*2,1<<20 if rgb else 6160]
            r = run(argv, mode, dict(os.environ, DYLD_INSERT_LIBRARIES=str(library)))
            result = json.loads(r.stdout); receipt['cases'].append(result)
            if result['outcomeExpected'] is not True: raise RuntimeError('Unexpected codec outcome')
            if mode.endswith('control'):
                if result['allocations'] <= 0: raise RuntimeError('Allocation control was invisible')
            elif result['allocations'] != 0 or result['mappings'] != 0:
                raise RuntimeError('Qualified operation allocated')
        after = {str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT/'Sources').rglob('*.swift'))}
        if after != receipt['sources']: raise RuntimeError('Source changed during qualification')
        receipt['passed'] = True
    except Exception as error:
        receipt['error'] = str(error)
        raise
    finally:
        save()

if __name__ == '__main__': main()
