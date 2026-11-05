import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys

root = Path('/private/tmp')
fixture = root / 'swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory/lossless16-2048.jpg'
profile_paths = {name: root / ('swiftjli-lossless-profile' + suffix) for name, suffix in [('beforeFused', ''), ('afterFused', '-fused')]}
matrix_paths = {name: root / f'swiftjli-native-matrix-{name}' for name in ['baseline', 'candidate']}
result = {'baselineRevision': 'd25d4567c7932a0b3fd181901d16ce35a9eded29',
          'matrixMethod': 'Public SwiftJLI.Decoder.decode, allocated output, 5 warmups then 20 individual samples per case, 2 rounds with binary order reversed. Input read and exact full-image verification outside timing.',
          'fusedMethod': '5 warmup processes per binary; 20 alternating processes per binary, each reports elapsed for 10 public decoder calls; values are batch-average seconds per decode, excluding process launch. Same mixed2048 fixture, before/after fused fastpath only.',
          'binarySHA256': {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (profile_paths | matrix_paths).items()},
          'harnessSHA256': {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in ['swiftjli-native-matrix.swift', 'swiftjli-lossless-profile.swift']},
          'fixtureSHA256': {str(path.name): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((root / 'swiftjli-native-matrix-fixtures').glob('*'))},
          'fusedSamples': {name: [] for name in profile_paths}, 'matrix': []}
out = root / 'swiftjli-native-matrix-results.json'
if '--matrix-only' in sys.argv:
    result = json.loads(out.read_text())
for iteration in ([] if '--matrix-only' in sys.argv else range(-5, 20)):
    order = list(profile_paths) if iteration % 2 == 0 else list(reversed(profile_paths))
    for name in order:
        text = subprocess.check_output([str(profile_paths[name]), str(fixture), '10'], text=True)
        seconds = float(text.split('elapsed=')[1].split(' seconds')[0]) / 10
        if iteration >= 0:
            result['fusedSamples'][name].append(seconds)
print('Fused medians', {k: statistics.median(v) for k, v in result['fusedSamples'].items()}, flush=True)
out.write_text(json.dumps(result, indent=2) + '\n')
if '--fused-only' in sys.argv:
    raise SystemExit(0)
for round_number in [1, 2]:
    order = ['baseline', 'candidate'] if round_number == 1 else ['candidate', 'baseline']
    for name in order:
        command = [str(matrix_paths[name]), 'benchmark', str(root / 'swiftjli-native-matrix-fixtures')]
        raw_path = root / f'swiftjli-native-matrix-{name}-round{round_number}.jsonl'
        with raw_path.open('w') as file:
            subprocess.run(command, check=True, stdout=file)
        records = [json.loads(line) for line in raw_path.read_text().splitlines()]
        result['matrix'].append({'round': round_number, 'binary': name, 'command': command, 'records': records})
        out.write_text(json.dumps(result, indent=2) + '\n')
        print('Completed', name, 'round', round_number, len(records), 'cases', flush=True)
