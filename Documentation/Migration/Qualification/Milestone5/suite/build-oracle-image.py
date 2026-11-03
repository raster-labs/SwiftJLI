#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Build and pin the isolated development oracle image; no host installation."""
import datetime
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True, help='New evidence directory; existing paths are refused')
args = parser.parse_args()
script_dir = Path(__file__).resolve().parent
repo = script_dir.parents[4]
here = args.output.resolve()
try:
    here.mkdir(parents=True, exist_ok=False)
except FileExistsError:
    parser.error('--output must be a new directory; existing evidence will not be overwritten')
image = 'swiftjli-m5-oracles:20261103'
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
record = {'status': 'running', 'startedUTC': now(), 'imageTag': image, 'commands': [],
          'baseImage': 'swift@sha256:bca121f6eb59fd80340d1296887b2698ed8f3eb9eca7d80c181f8af769dc7ee0',
          'dockerfileSHA256': sha(script_dir / 'Oracle.Dockerfile'),
          'charlsSourceSHA256': sha(repo / 'Examples/SuitePairIntegration/Oracle/charls-pgm.cpp'),
          'candidateProbe': {'argv': ['docker', 'run', '--rm', 'swift:6.4-noble', 'sh', '-c',
              'apt-get update >/tmp/apt-update.log && apt-cache policy g++ libcharls-dev libjxl-tools'],
              'exitCode': 0, 'log': str(script_dir / 'oracle-package-candidates.log'),
              'logSHA256': sha(script_dir / 'oracle-package-candidates.log')}}

def save():
    (here / 'oracle-image.json').write_text(json.dumps(record, indent=2) + '\n')

def run(name, argv):
    row = {'name': name, 'argv': list(map(str, argv)), 'startedUTC': now(), 'log': name + '.log'}
    record['commands'].append(row)
    save()
    with (here / row['log']).open('w') as stream:
        result = subprocess.run(row['argv'], cwd=repo, stdout=stream, stderr=subprocess.STDOUT, timeout=1800)
    row.update(exitCode=result.returncode, finishedUTC=now())
    save()
    result.check_returncode()
    return (here / row['log']).read_text().strip()

try:
    run('oracle-image-build', ['docker', 'build', '--progress', 'plain', '-f', script_dir / 'Oracle.Dockerfile', '-t', image, script_dir])
    record['imageMetadata'] = json.loads(run('oracle-image-inspect', ['docker', 'image', 'inspect', image]))[0]
    run('oracle-packages', ['docker', 'run', '--rm', '--network', 'none', image, 'dpkg-query', '-W'])
    run('oracle-djxl-version', ['docker', 'run', '--rm', '--network', 'none', image, 'djxl', '--version'])
    record['hostTools'] = {}
    for name in ['djpeg', 'opj_decompress']:
        path = Path(shutil.which(name))
        record['hostTools'][name] = {'path': str(path), 'resolvedPath': str(path.resolve()), 'sha256': sha(path)}
    run('host-djpeg-version', [record['hostTools']['djpeg']['path'], '-version'])
    run('host-openjpeg-version', ['pkg-config', '--modversion', 'libopenjp2'])
    record['status'] = 'passed'
except BaseException as error:
    record.update(status='failed', error=repr(error))
    raise
finally:
    record['finishedUTC'] = now()
    record['runnerSHA256'] = sha(Path(__file__))
    save()
print(json.dumps({'status': record['status'], 'image': image}))
