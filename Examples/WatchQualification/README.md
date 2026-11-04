# Physical Watch qualification harness

Development-only Swift Testing package for the physical-device gate
(TEST-06, PLAT-01), continued within Milestone 5 release completion. It is outside the shipping dependency graph. It uses
the public API and the existing `ResourceLimits.watch` without raising budgets.
No physical Watch result is claimed by the presence of this package.

Six serial tests cover:

- The Watch defaults and descriptor-only decoded-size boundaries below, at and
  above 32 MiB, without allocating those boundary images.
- Sixteen 12/16-bit lossless round trips into padded caller storage, exact
  deterministic sample expectations, unchanged encoded bytes, allocation
  identity, copy reports and rejection of a second writer.
- Eight encodes using at most two simultaneous readers, with joined tasks.
- 8/12-bit greyscale/RGB sequential/progressive DCT under every advertised
  backend with Watch budgets. This checks resource behaviour and output
  descriptors, not independent DCT fidelity; the repository's oracle evidence
  remains the fidelity gate.
- A 1024×513 input that fits decoded storage but exceeds the conservative
  encoder workspace reservation, followed by a successful smaller operation.
- Eight processing-callback cancellations, encode/decode deadline rejection
  with a deliberately shortened deadline, and recovery under normal limits.

Each completed case prints a `WATCH_QUALIFICATION` JSON record containing the
environment, OS, budgets, elapsed wall time and process peak RSS. A test-runner
failure or assertion failure invalidates the run even if records were printed.
The six expected case names are fixed in the test source.

## Validate the harness on a Mac

From the repository root:

```sh
swift test --package-path Examples/WatchQualification --disable-xctest -j 2
swift test --package-path Examples/WatchQualification -c release --disable-xctest -j 2
```

These records say `host-harness-check`. Watch simulator records say
`watch-simulator`. Neither closes physical-device qualification. A Watch SDK
compile proves compilation only. Do not use sanitizer RSS as device memory
evidence.

## Physical device procedure — unexecuted

The latest [local inventory](../../Documentation/Migration/Qualification/Milestone5/ReleaseCompletion/device-inventory.json)
finds no physical iPhone, iPad or Watch. A development signing identity and a
provisioning profile exist, but signing this Watch test runner is unverified.
The initial `xcrun devicectl ... --help` probe unexpectedly triggered automatic
Xcode component setup; it completed before interruption. Subsequent inventory
used installed tool binaries directly. No device tests ran during that check.

Connect a developer-enabled, paired Watch running watchOS 26 or later. From
`Examples/WatchQualification`, discover the actual destination and scheme:

```sh
xcodebuild -list -json
xcodebuild -showdestinations -scheme WatchQualification-Package
```

Unlock and trust the paired iPhone, enable Developer Mode as prompted, and
select the authorised development team. Use a **physical watchOS** destination;
the absence of such a destination is an unavailable gate. Signing and running
this package on physical hardware remain unverified. If Xcode requires an
application host, add and qualify a development-only host before claiming this
procedure works. Do not substitute a simulator or disable code signing.

The capture below is a procedure template, not executed device evidence. Set
the three environment values to a new absolute evidence directory, the actual
destination ID and signing team. Run from the repository root. It uses only the
existing synthetic harness, does not change device settings, and preserves
actual command exits and source snapshots even on failure. Review device power
and thermal state before running; keep private device identifiers local when
preparing a public report.

```sh
export WATCH_EVIDENCE=/absolute/new/watch-device-evidence
export WATCH_DESTINATION=PHYSICAL_WATCH_DESTINATION_ID
export WATCH_TEAM=YOUR_TEAM_ID
python3 -B - <<'PY'
import importlib.util, json, os, pathlib, signal, subprocess
root = pathlib.Path.cwd()
spec = importlib.util.spec_from_file_location('device_check', root / 'Scripts/verify-watch-device-tests.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
out = pathlib.Path(os.environ['WATCH_EVIDENCE']).resolve()
out.mkdir(parents=True, exist_ok=False)
device, team = os.environ['WATCH_DESTINATION'], os.environ['WATCH_TEAM']
report = {'status': 'running', 'platform': 'watchOS', 'configuration': 'Release',
          'scheme': 'WatchQualification-Package', 'packagePath': 'Examples/WatchQualification',
          'device': {'udid': device}, 'commands': [],
          'capturePaths': {'repository': str(root), 'evidence': str(out),
                           'resultBundle': str(out / 'Tests.xcresult')}}
def save():
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
def run(name, argv, filename, timeout=120):
    with (out / filename).open('wb') as stdout, (out / (name + '.stderr')).open('wb') as stderr:
        process = subprocess.Popen(argv, cwd=root / report['packagePath'], stdout=stdout,
                                   stderr=stderr, start_new_session=True)
        timed_out = False
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                code = process.wait(timeout=5)
    report['commands'].append({'name': name, 'argv': argv, 'exit_code': code,
                               'timedOut': timed_out, 'timeoutSeconds': timeout,
                               'cwd': str(root / report['packagePath']),
                               'stdout': filename, 'stderr': name + '.stderr',
                               'stdoutSHA256': check.sha(out / filename),
                               'stderrSHA256': check.sha(out / (name + '.stderr'))})
    save()
    if code or timed_out:
        raise RuntimeError(name + ' failed or timed out')
try:
    report['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    report['sourceSHA256Before'] = check.source_hashes(root)
    tree = subprocess.check_output(['git', 'ls-tree', '-rz', '--full-tree', report['revision'], '--',
        'Sources', 'Package.swift', 'Examples/WatchQualification/Package.swift',
        'Examples/WatchQualification/Tests/WatchQualificationTests/WatchQualificationTests.swift'], text=True)
    check.shared.validate_source_identity(root, [root / p for p in report['sourceSHA256Before']], tree)
    run('xcode', ['xcodebuild', '-version'], 'xcode.log')
    run('compiler', ['xcrun', 'swift', '--version'], 'compiler.log')
    run('sdk', ['xcrun', '--sdk', 'watchos', '--show-sdk-version'], 'sdk.log')
    report['toolchain'] = {name: (out / (name + '.log')).read_text().strip()
                           for name in ('xcode', 'compiler', 'sdk')}
    run('devices', ['xcrun', 'xcdevice', 'list', '--timeout', '15'], 'devices.json', 30)
    check.physical_device(json.loads((out / 'devices.json').read_text()), device)
    run('test', ['xcodebuild', 'test', '-scheme', report['scheme'], '-configuration', 'Release',
        '-destination', 'platform=watchOS,id=' + device, '-destination-timeout', '120',
        '-parallel-testing-enabled', 'NO', '-derivedDataPath', str(out / 'DerivedData'),
        '-resultBundlePath', str(out / 'Tests.xcresult'), 'DEVELOPMENT_TEAM=' + team], 'test.log', 1800)
    report['status'] = 'completed'
except BaseException as error:
    report.update(status='failed', error=str(error))
    raise
finally:
    report['captureSHA256'] = {name: check.sha(out / name) for name in check.CAPTURE_FILES if (out / name).is_file()}
    if (out / 'Tests.xcresult').is_dir():
        report['xcresultFilesSHA256'] = check.shared.bundle_hashes(out / 'Tests.xcresult')
    report['sourceSHA256After'] = check.source_hashes(root)
    save()
PY
python3 -B Scripts/verify-watch-device-tests.py \
  --evidence "$WATCH_EVIDENCE" --output "$WATCH_EVIDENCE/verification"
```

Run verification only after capture exits zero. `completed` means the commands
finished; the separate verifier determines whether six tests passed. It requires
the recorded Release command, zero failed/skipped/expected-failure counts,
six unique `physical-watch` records, and the original `xcdevice` inventory to
agree with xcresult on physical Watch platform, destination, ARM architecture,
model, OS version and build. Missing or unfamiliar hardware metadata fails
closed and needs inspection of genuine device evidence, not fabricated fields.
Each case's OS version/build must also match that hardware. The first successful
physical end-to-end capture, including Xcode's actual physical-device summary
shape, remains unexecuted; the documented schema is a strict preparation,
not confirmed physical-platform support.
The `report.json` schema is the object written above: command receipts, selected
destination, configuration, original repository/evidence/result paths, command
working directory, revision, toolchain values read from their nonempty logs,
before/after source hashes, capture-time input hashes and the original xcresult
file manifest. Preserve `devices.json`, the three toolchain logs, `test.log`,
`test.stderr`, other command stderr logs and `Tests.xcresult` with it.
Verification binds the single `-resultBundlePath` and test working directory
to those original paths, and all supplied bytes to their capture-time hashes.
The whole evidence directory may move: original paths stay in the receipt,
while the verified `--evidence/Tests.xcresult` copy must retain identical bytes.

The verifier imports hash/source/bundle utilities from the unchanged simulator
verifier. It copies xcresult before querying, allows SQLite cache changes only
on that copy, rejects mutation of original inputs, and requires package,
shipping and harness sources to match the recorded Git revision. Outputs must
be fresh. The existing simulator verifier continues to accept simulator
evidence only. This device verifier has negative/parser checks, not a successful
hardware qualification run; its checks can be reproduced with:

```sh
python3 -B -m unittest discover -s Scripts/tests -p test_watch_device_verifier.py -v
```

Record the source commit and clean/dirty status, hashes of this harness and
shipping sources, Xcode/compiler/SDK versions, exact Watch model and OS build,
power/thermal conditions, invocation, exit code, full log and xcresult. Require
six passing tests, zero failures/skips and six records whose environment is
`physical-watch`. Review the actual numbers; a passing test count alone does
not establish safe device ceilings.

Repeat ordinary and failure workloads on the target device, inspect retained
memory after joined work using device tooling, and investigate crashes,
termination, increasing retained memory or unacceptable latency. These small
fixtures do not exhaust every resource ceiling, prove all allocation failures,
or qualify every supported profile at its maximum admitted size. Expand the
measured workload if device results expose a risk. Existing full oracle, fuzz,
allocator and worker-cancellation evidence remains separately pinned.

RSS includes the test runner and runtime and is a cumulative process high-water
mark, not per-operation workspace. The 64 MiB budget is an operation admission
ceiling, not an assertion that total process RSS stays below 64 MiB. Two small
concurrent operations do not establish process-wide admission for arbitrary
concurrency. Deadline measurements include test/setup overhead; callback
cancellation does not establish mid-kernel cancellation latency.

Any necessary default adjustment requires a coordinated shared-contract
revision and requalification. After reviewing real device evidence, update
the current Milestone 5 release-completion record and acceptance ledger.
Even a successful six-test receipt leaves `resourceCeilingsQualified` and
`stableReleaseQualified` false: the repeated device-memory review and remaining
release gates need their own evidence and acceptance.
