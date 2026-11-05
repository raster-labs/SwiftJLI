#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Black-box CLI, codec payload verb, stream/format/resource/exit-status and staged manual installation regression checks."""
import argparse, hashlib, json, os, re, shutil, signal, struct, subprocess, sys, tempfile, time
from pathlib import Path

def make_nrrd_u16(width: int, height: int, endian: str = 'little', extra_headers: str = '') -> bytes:
    header = (
        f"NRRD0004\n"
        f"# Synthetic 16-bit greyscale fixture\n"
        f"type: uint16\n"
        f"dimension: 2\n"
        f"sizes: {width} {height}\n"
        f"encoding: raw\n"
        f"endian: {endian}\n"
        f"{extra_headers}\n"
    ).encode('ascii')
    fmt = '<H' if endian == 'little' else '>H'
    payload = bytearray()
    for y in range(height):
        for x in range(width):
            val = (x * 193 + y * 31957) & 0xFFFF
            payload.extend(struct.pack(fmt, val))
    return header + bytes(payload)

def parse_nrrd_u16(data: bytes):
    sep = data.find(b'\n\n')
    assert sep > 0
    header_lines = data[:sep].decode('ascii').splitlines()
    assert header_lines[0] == 'NRRD0004'
    fields = {}
    for line in header_lines[1:]:
        if not line or line.startswith('#'):
            continue
        k, v = line.split(':', 1)
        fields[k.strip().lower()] = v.strip()
    w, h = [int(t) for t in fields['sizes'].split()]
    fmt = '<H' if fields['endian'].lower() == 'little' else '>H'
    raw = data[sep + 2:]
    assert len(raw) == w * h * 2
    samples = [struct.unpack_from(fmt, raw, i * 2)[0] for i in range(w * h)]
    return w, h, samples

def make_netpbm(width: int, height: int, components: int, bits: int) -> bytes:
    magic = 'P5' if components == 1 else 'P6'
    maxval = (1 << bits) - 1
    header = f"{magic}\n{width} {height}\n{maxval}\n".encode('ascii')
    payload = bytearray()
    for y in range(height):
        for x in range(width * components):
            val = (x * 101 + y * 193) & maxval
            if bits <= 8:
                payload.append(val)
            else:
                payload.extend(struct.pack('>H', val))
    return header + bytes(payload)

def parse_netpbm(data: bytes):
    idx = 0
    tokens = []
    while len(tokens) < 4:
        while idx < len(data) and data[idx] in b' \t\r\n':
            idx += 1
        if data[idx] == ord('#'):
            while idx < len(data) and data[idx] not in b'\r\n':
                idx += 1
            continue
        start = idx
        while idx < len(data) and data[idx] not in b' \t\r\n#':
            idx += 1
        tokens.append(data[start:idx].decode('ascii'))
    assert data[idx] in b' \t\r\n'
    raster = data[idx + 1:]
    magic = tokens[0]
    w, h, maxval = int(tokens[1]), int(tokens[2]), int(tokens[3])
    comps = 1 if magic == 'P5' else 3
    if maxval <= 255:
        assert len(raster) == w * h * comps
        samples = list(raster)
    else:
        assert len(raster) == w * h * comps * 2
        samples = [struct.unpack_from('>H', raster, i * 2)[0] for i in range(w * h * comps)]
    return magic, w, h, maxval, samples

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True,help='New evidence directory')
    args=parser.parse_args();binary=args.binary.resolve();out=args.output.resolve()
    if out.exists():parser.error('Use a fresh output directory')
    out.mkdir(parents=True)
    repo=Path(__file__).resolve().parent.parent
    tool=binary.name;version=(repo/'VERSION').read_text().strip();manual=repo/'ManPages'/(tool+'.1')
    if not manual.is_file():parser.error('Binary name must match this repository manual')
    report={'binary':str(binary),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
            'installer_sha256':hashlib.sha256((repo/'Scripts/install-cli.sh').read_bytes()).hexdigest(),
            'test_runner_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'version':version,'manual_sha256':hashlib.sha256(manual.read_bytes()).hexdigest(),'commands':[],'status':'running'}
    def save(): (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    def run(argv,expected=0,**kwargs):
        r=subprocess.run([str(x) for x in argv],capture_output=True,text=True,timeout=30,**kwargs)
        report['commands'].append({'argv':[str(x) for x in argv],'exit_code':r.returncode,'expected_exit_code':expected,
                                   'stdout':r.stdout,'stderr':r.stderr})
        save();assert r.returncode==expected,(argv,r.returncode,r.stderr);return r
    def run_bytes(argv,expected=0,stdin_bytes=b''):
        r=subprocess.run([str(x) for x in argv],input=stdin_bytes,capture_output=True,timeout=30)
        stderr_text=r.stderr.decode('utf-8',errors='replace')
        report['commands'].append({'argv':[str(x) for x in argv],'exit_code':r.returncode,'expected_exit_code':expected,
                                   'stdout_bytes':len(r.stdout),'stderr':stderr_text})
        save();assert r.returncode==expected,(argv,r.returncode,stderr_text);return r
    def cli(*values,expected=0):return run([binary,*values],expected)
    def document(r):
        d=json.loads(r.stdout);assert d['version']==version and d['minimumAppleOS']=='26.0'
        assert d['canEncode'] is True and d['canDecode'] is True and d['canInspect'] is True and d['formats']==['JPEG (SOF0/SOF1/SOF2/SOF3)']
        return d
    try:
        root=cli('--help');assert 'USAGE:' in root.stdout and 'encode' in root.stdout and not root.stderr
        for form in [[],['-h'],['help']]:assert cli(*form).stdout==root.stdout
        command=cli('capabilities','--help').stdout
        assert cli('help','capabilities').stdout==command and cli('capabilities','-h').stdout==command
        assert '--json' in command and 'EXIT STATUS' in command
        for verb in ['encode','decode','inspect','validate']:
            vhelp=cli(verb,'--help').stdout
            assert cli('help',verb).stdout==vhelp and f'USAGE: {tool} {verb}' in vhelp and 'EXIT STATUS' in vhelp
        for form in [['--version'],['version'],['--version','--quiet']]:assert cli(*form).stdout==tool+' '+version+'\n'
        baseline=document(cli('capabilities','--json'))
        for level in range(1,6):
            for form in [['-'+'v'*level],['-v']*level,['--verbose',str(level)],['--verbose='+str(level)],
                         ['-verbose:',str(level)],['-verbose:'+str(level)],['--verbose','+'*level],['--verbose='+'+'*level]]:
                r=cli('capabilities','--json',*form);assert document(r)==baseline
                assert len(r.stderr.splitlines())==level,(form,r.stderr)
                assert all(f'[{i}]' in r.stderr for i in range(1,level+1))
        for form in [['--verbose'],['-verbose']]:assert len(cli(*form,'capabilities','--json').stderr.splitlines())==1
        assert len(cli('capabilities','-v','--verbose','2','-v').stderr.splitlines())==3
        assert len(cli('capabilities','-vv','-vvv').stderr.splitlines())==5
        quiet=cli('capabilities','--json','--quiet');assert not quiet.stderr and document(quiet)==baseline
        assert cli('--help','--quiet').stdout==root.stdout
        for invalid in ['0','6','10','99999999999999999999999999999','abc','++++++','+2','١','']:
            r=cli('capabilities','--verbose='+invalid,expected=2);assert not r.stdout and r.stderr
        for form in [['--verbose=5','-v'],['-vvvvvv'],['-v','--quiet'],['--quiet','--verbose=1'],['--quiet','--verbose=0'],
                     ['--unknown'],['bogus'],['help','bogus'],['capabilities','extra'],['--verbose:'],['--json'],
                     ['--input','some-path'],['capabilities','--output','x'],['capabilities','--version'],['--input'],
                     ['transcode'],['encode'],['decode','-i','in.jpg'],['inspect','-i','in.jpg','-o','out.pgm'],
                     ['validate','-i','in.jpg','--overwrite'],['decode','-i','in.jpg','-o','out.pgm','--mode','lossless'],
                     ['encode','-i','in.nrrd','-o','out.jpg','--threads','0'],['encode','-i','in.nrrd','-o','out.jpg','--max-memory','0'],
                     ['encode','-i','in.nrrd','-o','out.jpg','--timeout','0'],['encode','-i','in.nrrd','-o','out.jpg','--backend','bogus'],
                     ['encode','-i','in.nrrd','-o','out.jpg','--copy-policy','bogus'],
                     ['encode','-i','-','-o','out.jpg'],['encode','-i','in.nrrd','-o','-'],
                     ['encode','-i','in.nrrd','-o','out.pgm','--output-format','jpeg']]:
            r=cli(*form,expected=2);assert not r.stdout and r.stderr

        with tempfile.TemporaryDirectory(prefix='cli stage spaces ',dir=out) as temp:
            temp=Path(temp);payload=temp/'private image λ.raw';payload.write_bytes(b'unchanged')
            # Unsupported headerless .raw format is rejected with exit 4 without leaking path or creating output.
            for verb,extra in [('encode',['--output',str(temp/'must-not-exist.jpg')]),
                               ('decode',['--output',str(temp/'must-not-exist.nrrd')]),
                               ('inspect',[]),
                               ('validate',[])]:
                r=cli(verb,'--input',str(payload),*extra,'-vvvvv',expected=4)
                assert not r.stdout and str(payload) not in r.stderr and payload.read_bytes()==b'unchanged'
                for e in extra:
                    if e.startswith(str(temp)):assert not Path(e).exists()

            # 1. NRRD 16-bit greyscale lossless round-trip (little-endian, big-endian, and spatial kinds).
            nrrd_le = temp/'source_le.nrrd'
            nrrd_be = temp/'source_be.nrrd'
            nrrd_le.write_bytes(make_nrrd_u16(17, 13, 'little', 'kinds: domain domain\n'))
            nrrd_be.write_bytes(make_nrrd_u16(17, 13, 'big'))
            _, _, expected_u16 = parse_nrrd_u16(nrrd_le.read_bytes())

            jpg_16 = temp/'lossless16.jpg'
            enc_r = cli('encode','-i',str(nrrd_le),'-o',str(jpg_16),'--json','-vvvvv')
            assert not enc_r.stdout and jpg_16.is_file()
            enc_lines = enc_r.stderr.splitlines()
            assert len(enc_lines) == 6 # 5 diagnostic lines + 1 JSON report line on stderr
            enc_json = json.loads(enc_lines[-1])
            assert enc_json['command'] == 'encode' and enc_json['width'] == 17 and enc_json['height'] == 13
            assert enc_json['meaningfulBits'] == 16 and enc_json['copyEventCount'] == 0
            assert enc_json['fidelity'] == 'exactSamples' and enc_json['maximumAbsoluteError'] == 0
            assert enc_json['pixelAllocationCount'] == 0 and enc_json['peakWorkspaceBytes'] is None
            assert str(nrrd_le) not in enc_r.stderr and str(jpg_16) not in enc_r.stderr

            # Big-endian NRRD produces the exact same lossless JPEG stream.
            jpg_16_be = temp/'lossless16_be.jpg'
            cli('encode','-i',str(nrrd_be),'-o',str(jpg_16_be))
            assert jpg_16_be.read_bytes() == jpg_16.read_bytes()

            # Inspect & validate (plain text and --json).
            insp_plain = cli('inspect','-i',str(jpg_16))
            assert 'codingProcess: predictive' in insp_plain.stdout and 'lossless: true' in insp_plain.stdout
            assert 'fidelity: exactSamples' in insp_plain.stdout
            insp_json = json.loads(cli('inspect','-i',str(jpg_16),'--json').stdout)
            assert insp_json['codingProcess'] == 'predictive' and insp_json['width'] == 17 and insp_json['height'] == 13
            assert insp_json['bitsPerComponent'] == 16 and insp_json['isLossless'] is True and insp_json['predictor'] == 1
            assert insp_json['fidelity'] == 'exactSamples' and insp_json['maximumAbsoluteError'] == 0

            val_plain = cli('validate','-i',str(jpg_16))
            assert 'valid: true' in val_plain.stdout and 'fidelity: exactSamples' in val_plain.stdout
            val_json = json.loads(cli('validate','-i',str(jpg_16),'--json').stdout)
            assert val_json['valid'] is True and val_json['bitsPerComponent'] == 16 and val_json['copyEventCount'] == 0
            assert val_json['fidelity'] == 'exactSamples' and val_json['pixelAllocationCount'] == 1
            assert val_json['peakWorkspaceBytes'] is None

            # Decode back to NRRD and verify exact samples.
            decoded_nrrd = temp/'decoded16.nrrd'
            dec_r = cli('decode','-i',str(jpg_16),'-o',str(decoded_nrrd),'--json')
            assert not dec_r.stdout
            dec_json = json.loads(dec_r.stderr.strip())
            assert dec_json['command'] == 'decode' and dec_json['outputFormat'] == 'nrrd' and dec_json['copyEventCount'] == 0
            assert dec_json['fidelity'] == 'exactSamples' and dec_json['maximumAbsoluteError'] == 0
            assert dec_json['pixelAllocationCount'] == 1 and dec_json['peakWorkspaceBytes'] is None
            w, h, actual_u16 = parse_nrrd_u16(decoded_nrrd.read_bytes())
            assert (w, h) == (17, 13) and actual_u16 == expected_u16

            # 2. Existing destination protection (--overwrite required, exit 6).
            before_bytes = decoded_nrrd.read_bytes()
            cli('decode','-i',str(jpg_16),'-o',str(decoded_nrrd),expected=6)
            assert decoded_nrrd.read_bytes() == before_bytes
            cli('decode','-i',str(jpg_16),'-o',str(decoded_nrrd),'--overwrite',expected=0)
            assert decoded_nrrd.read_bytes() == before_bytes

            # Symlink destination refused even with --overwrite (exit 6).
            symlink_target = temp/'symlink_target.nrrd'
            symlink_target.write_bytes(b'do-not-touch')
            symlink_out = temp/'symlink_out.nrrd'
            symlink_out.symlink_to(symlink_target)
            cli('decode','-i',str(jpg_16),'-o',str(symlink_out),'--overwrite',expected=6)
            assert symlink_target.read_bytes() == b'do-not-touch'

            # 3. Netpbm PGM/PPM/PNM qualification across bit depths (2, 8, 10, 12, 16) and greyscale/RGB.
            for bits in [2, 8, 10, 12, 16]:
                for comps, ext in [(1, 'pgm'), (3, 'ppm')]:
                    src_pnm = temp/f'src_{comps}c_{bits}b.{ext}'
                    src_pnm.write_bytes(make_netpbm(11, 9, comps, bits))
                    _, _, _, orig_mv, orig_samples = parse_netpbm(src_pnm.read_bytes())
                    assert orig_mv == (1 << bits) - 1
                    rt_jpg = temp/f'rt_{comps}c_{bits}b.jpg'
                    cli('encode','-i',str(src_pnm),'-o',str(rt_jpg))
                    rt_pnm = temp/f'rt_{comps}c_{bits}b.pnm'
                    cli('decode','-i',str(rt_jpg),'-o',str(rt_pnm))
                    m_rt, w_rt, h_rt, mv_rt, samples_rt = parse_netpbm(rt_pnm.read_bytes())
                    assert m_rt == ('P5' if comps == 1 else 'P6')
                    assert (w_rt, h_rt, mv_rt) == (11, 9, orig_mv) and samples_rt == orig_samples

            pgm_12 = temp/'in12.pgm'
            pgm_12.write_bytes(make_netpbm(19, 15, 1, 12))
            _, _, _, maxval12, expected12 = parse_netpbm(pgm_12.read_bytes())
            jpg_12 = temp/'lossless12.jpg'
            cli('encode','-i',str(pgm_12),'-o',str(jpg_12),'--predictor','2','--restart-interval','19')
            insp12 = json.loads(cli('inspect','-i',str(jpg_12),'--json').stdout)
            assert insp12['bitsPerComponent'] == 12 and insp12['predictor'] == 2 and insp12['restartInterval'] == 19
            assert insp12['isLossless'] is True and insp12['fidelity'] == 'exactSamples'

            # Decoding 12-bit JPEG to NRRD must fail with exit 4 (NRRD is full 16-bit only) without creating output!
            bad_nrrd = temp/'must_not_exist_12.nrrd'
            cli('decode','-i',str(jpg_12),'-o',str(bad_nrrd),expected=4)
            assert not bad_nrrd.exists()

            # Near-lossless point-transform encode & decode: isLossless must be False, fidelity == boundedError.
            jpg_near = temp/'near12.jpg'
            enc_near = cli('encode','-i',str(pgm_12),'-o',str(jpg_near),'--mode','near-lossless','--max-error','3','--json')
            enc_near_json = json.loads(enc_near.stderr.strip())
            assert enc_near_json['fidelity'] == 'boundedError' and enc_near_json['maximumAbsoluteError'] == 3
            insp_near = json.loads(cli('inspect','-i',str(jpg_near),'--json').stdout)
            assert insp_near['codingProcess'] == 'predictive' and insp_near['pointTransform'] == 2
            assert insp_near['isLossless'] is False and insp_near['fidelity'] == 'boundedError' and insp_near['maximumAbsoluteError'] == 3
            out_near = temp/'out_near12.pgm'
            cli('decode','-i',str(jpg_near),'-o',str(out_near))
            _, _, _, _, near_samples = parse_netpbm(out_near.read_bytes())
            assert all(abs(a - b) <= 3 for a, b in zip(near_samples, expected12))

            # 8-bit RGB PPM lossless & lossy DCT (sequential and progressive, scalar and accelerated).
            ppm_8 = temp/'in8.ppm'
            ppm_8.write_bytes(make_netpbm(32, 24, 3, 8))
            _, _, _, _, expected_rgb8 = parse_netpbm(ppm_8.read_bytes())
            jpg_rgb_lossless = temp/'rgb_lossless.jpg'
            cli('encode','-i',str(ppm_8),'-o',str(jpg_rgb_lossless))
            out_ppm_lossless = temp/'out_rgb_lossless.ppm'
            cli('decode','-i',str(jpg_rgb_lossless),'-o',str(out_ppm_lossless))
            _, _, _, _, actual_rgb8 = parse_netpbm(out_ppm_lossless.read_bytes())
            assert actual_rgb8 == expected_rgb8

            # Decoding RGB JPEG to .pgm must fail with exit 4 before creating output.
            bad_pgm = temp/'must_not_exist_rgb.pgm'
            cli('decode','-i',str(jpg_rgb_lossless),'-o',str(bad_pgm),expected=4)
            assert not bad_pgm.exists()

            # Lossy progressive DCT encode/inspect/validate/decode across backends (platform-aware for accelerated).
            has_accelerate = (sys.platform == 'darwin')
            for backend in ['scalar', 'preferred-accelerated']:
                jpg_dct = temp/f'rgb_dct_{backend}.jpg'
                cli('encode','-i',str(ppm_8),'-o',str(jpg_dct),'--mode','lossy','--quality','90',
                    '--subsampling','444','--progressive','successive-approximation','--backend',backend)
                dct_info = json.loads(cli('inspect','-i',str(jpg_dct),'--json').stdout)
                assert dct_info['codingProcess'] == 'progressiveDCT' and dct_info['isProgressive'] is True
                assert dct_info['isLossless'] is False and dct_info['fidelity'] == 'lossy' and dct_info['maximumAbsoluteError'] is None
                assert dct_info['chromaSubsampling'] == '4:4:4'
                val_dct = json.loads(cli('validate','-i',str(jpg_dct),'--backend',backend,'--json').stdout)
                assert val_dct['valid'] is True and val_dct['fidelity'] == 'lossy' and val_dct['maximumAbsoluteError'] is None
                out_pnm = temp/f'out_dct_{backend}.pnm'
                cli('decode','-i',str(jpg_dct),'-o',str(out_pnm),'--backend',backend)
                m_dct, w_dct, h_dct, mv_dct, _ = parse_netpbm(out_pnm.read_bytes())
                assert (m_dct, w_dct, h_dct, mv_dct) == ('P6', 32, 24, 255)

            jpg_dct_acc = temp/'rgb_dct_accelerated.jpg'
            out_pnm_acc = temp/'out_dct_accelerated.pnm'
            if has_accelerate:
                cli('encode','-i',str(ppm_8),'-o',str(jpg_dct_acc),'--mode','lossy','--quality','90',
                    '--subsampling','444','--progressive','successive-approximation','--backend','accelerated')
                val_acc = json.loads(cli('validate','-i',str(jpg_dct_acc),'--backend','accelerated','--json').stdout)
                assert val_acc['valid'] is True and val_acc['backend'] == 'accelerated'
                cli('decode','-i',str(jpg_dct_acc),'-o',str(out_pnm_acc),'--backend','accelerated')
                m_acc, w_acc, h_acc, mv_acc, _ = parse_netpbm(out_pnm_acc.read_bytes())
                assert (m_acc, w_acc, h_acc, mv_acc) == ('P6', 32, 24, 255)
            else:
                cli('encode','-i',str(ppm_8),'-o',str(jpg_dct_acc),'--mode','lossy','--quality','90',
                    '--subsampling','444','--progressive','successive-approximation','--backend','accelerated',expected=4)
                assert not jpg_dct_acc.exists()
                cli('validate','-i',str(temp/'rgb_dct_scalar.jpg'),'--backend','accelerated',expected=4)
                cli('decode','-i',str(temp/'rgb_dct_scalar.jpg'),'-o',str(out_pnm_acc),'--backend','accelerated',expected=4)
                assert not out_pnm_acc.exists()

            # 4. Shell pipe chaining (-i - and -o -) without stdout contamination.
            dec_pipe = run_bytes([binary,'decode','-i',str(jpg_16),'-o','-','--output-format','nrrd','--json','-vvv'])
            assert parse_nrrd_u16(dec_pipe.stdout) == (17, 13, expected_u16)
            enc_pipe = run_bytes([binary,'encode','-i','-','--input-format','nrrd','-o','-','--output-format','jpeg','--json','-vv'],
                                 stdin_bytes=dec_pipe.stdout)
            assert enc_pipe.stdout == jpg_16.read_bytes()
            val_pipe = run_bytes([binary,'validate','-i','-','--input-format','jpeg','--json'],stdin_bytes=enc_pipe.stdout)
            assert json.loads(val_pipe.stdout.decode('utf-8'))['valid'] is True

            # 5. Malformed/truncated input (exit 3), unsupported NRRD/Netpbm features (exit 4), resource limits (exit 5), I/O errors (exit 6).
            trunc_nrrd = temp/'trunc.nrrd'
            trunc_nrrd.write_bytes(nrrd_le.read_bytes()[:-2])
            cli('encode','-i',str(trunc_nrrd),'-o',str(temp/'no1.jpg'),expected=3)

            detached_nrrd = temp/'detached.nrrd'
            detached_nrrd.write_text('NRRD0004\ntype: uint16\ndimension: 2\nsizes: 4 4\nencoding: raw\nendian: little\ndata file: external.raw\n\n')
            r_det = cli('encode','-i',str(detached_nrrd),'-o',str(temp/'no2.jpg'),expected=4)
            assert 'external.raw' not in r_det.stderr

            kv_nrrd = temp/'kv.nrrd'
            kv_nrrd.write_bytes(make_nrrd_u16(4, 4, 'little', 'secret_key_xyz:=secret_val_abc\n'))
            r_kv = cli('encode','-i',str(kv_nrrd),'-o',str(temp/'no_kv.jpg'),expected=4)
            assert 'secret_key_xyz' not in r_kv.stderr and 'secret_val_abc' not in r_kv.stderr

            unknown_field_nrrd = temp/'unknown_field.nrrd'
            unknown_field_nrrd.write_bytes(make_nrrd_u16(4, 4, 'little', 'space_custom_secret: right-anterior-superior\n'))
            r_uf = cli('encode','-i',str(unknown_field_nrrd),'-o',str(temp/'no_uf.jpg'),expected=4)
            assert 'space_custom_secret' not in r_uf.stderr and 'right-anterior-superior' not in r_uf.stderr

            bad_kinds_nrrd = temp/'bad_kinds.nrrd'
            bad_kinds_nrrd.write_bytes(make_nrrd_u16(4, 4, 'little', 'kinds: RGB-color domain\n'))
            r_bk = cli('encode','-i',str(bad_kinds_nrrd),'-o',str(temp/'no_bk.jpg'),expected=4)
            assert 'RGB-color' not in r_bk.stderr

            bad_maxval_pgm = temp/'bad_maxval.pgm'
            bad_maxval_pgm.write_bytes(b'P5\n2 2\n100\n\x01\x02\x03\x04')
            cli('encode','-i',str(bad_maxval_pgm),'-o',str(temp/'no3.jpg'),expected=4)

            over_maxval_pgm = temp/'over_maxval.pgm'
            over_maxval_pgm.write_bytes(b'P5\n2 1\n3\n\x01\x04')
            cli('encode','-i',str(over_maxval_pgm),'-o',str(temp/'no4.jpg'),expected=3)

            # Checked dimension admission in readNetpbm before multiplication/allocation (exit 5).
            huge_dim_ppm = temp/'huge_dim.ppm'
            huge_dim_ppm.write_bytes(b'P6\n2000000 1\n255\n\x00\x00\x00')
            cli('encode','-i',str(huge_dim_ppm),'-o',str(temp/'no_huge.jpg'),expected=5)

            trunc_jpg = temp/'trunc.jpg'
            trunc_jpg.write_bytes(jpg_16.read_bytes()[:20])
            cli('inspect','-i',str(trunc_jpg),expected=3)
            cli('validate','-i',str(trunc_jpg),expected=3)
            cli('decode','-i',str(trunc_jpg),'-o',str(temp/'no5.nrrd'),expected=3)

            # Backend unavailable (exit 4): metal or accelerated on lossless JPEG.
            cli('decode','-i',str(jpg_16),'-o',str(temp/'no6.nrrd'),'--backend','metal',expected=4)
            cli('decode','-i',str(jpg_16),'-o',str(temp/'no7.nrrd'),'--backend','accelerated',expected=4)

            # Resource limit exceeded (exit 5): --max-memory 256 bytes.
            cli('encode','-i',str(nrrd_le),'-o',str(temp/'no8.jpg'),'--max-memory','256',expected=5)
            cli('decode','-i',str(jpg_16),'-o',str(temp/'no9.nrrd'),'--max-memory','256',expected=5)
            assert not (temp/'no8.jpg').exists() and not (temp/'no9.nrrd').exists()

            # Combined buffer --max-memory check: big enough for raw input alone, too small for rawInput + decoded Image.
            nrrd_64 = temp/'nrrd64.nrrd'
            nrrd_64.write_bytes(make_nrrd_u16(64, 64, 'little')) # 8192-byte payload + header
            cli('encode','-i',str(nrrd_64),'-o',str(temp/'no_comb.jpg'),'--max-memory','12000',expected=5)
            assert not (temp/'no_comb.jpg').exists()

            # Command-wide --timeout on blocking pipe read -> exit 5.
            timeout_out = temp/'timeout_out.nrrd'
            tr_fd, tw_fd = os.pipe()
            try:
                t_proc = subprocess.Popen(
                    [str(binary),'decode','-i','-','--input-format','jpeg','-o',str(timeout_out),'--timeout','0.05'],
                    stdin=tr_fd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
                )
                os.close(tr_fd); tr_fd = -1
                _, t_err = t_proc.communicate(timeout=5)
            finally:
                if tr_fd >= 0: os.close(tr_fd)
                os.close(tw_fd)
            report['commands'].append({'argv':[str(binary),'decode','-i','-','--input-format','jpeg','-o',str(timeout_out),'--timeout','0.05'],
                                       'condition':'timeout during blocking pipe read','exit_code':t_proc.returncode,
                                       'expected_exit_code':5,'stderr':t_err});save()
            assert t_proc.returncode == 5 and not timeout_out.exists(), (t_proc.returncode, t_err)

            # Command-wide --timeout on stalled stdout pipe write (nonblocking write with full buffer) -> exit 5.
            big_nrrd = temp/'big_nrrd.nrrd'
            big_nrrd.write_bytes(make_nrrd_u16(512, 512, 'little')) # 512 KiB > OS pipe capacity (16-64 KiB)
            big_jpg = temp/'big.jpg'
            cli('encode','-i',str(big_nrrd),'-o',str(big_jpg))
            wr_fd, ww_fd = os.pipe()
            try:
                w_proc = subprocess.Popen(
                    [str(binary),'decode','-i',str(big_jpg),'-o','-','--output-format','nrrd','--timeout','0.05'],
                     stdout=ww_fd, stderr=subprocess.PIPE, text=True
                )
                os.close(ww_fd); ww_fd = -1
                w_rc = w_proc.wait(timeout=5)
                w_err = w_proc.stderr.read() if w_proc.stderr else ''
            finally:
                if ww_fd >= 0: os.close(ww_fd)
                os.close(wr_fd)
            report['commands'].append({'argv':[str(binary),'decode','-i',str(big_jpg),'-o','-','--output-format','nrrd','--timeout','0.05'],
                                       'condition':'timeout during stalled pipe write','exit_code':w_rc,
                                       'expected_exit_code':5,'stderr':w_err});save()
            assert w_rc == 5, (w_rc, w_err)

            # Codec deadline sweep (5/10/15 ms twice) on normal 512x512 RGB progressive scalar encode:
            # allow completed-before-deadline exit 0 (with valid JPEG output) or deadline exit 5 (with no output),
            # reject exit 130 in every case, and require at least one deadline exit 5.
            big_ppm = temp/'normal-rgb-512.ppm'
            big_ppm.write_bytes(make_netpbm(512, 512, 3, 8))
            dl_codes = []
            for dl_idx, dl_sec in enumerate(['0.005', '0.01', '0.015', '0.005', '0.01', '0.015']):
                dl_jpg = temp/f'deadline_dct_{dl_idx}.jpg'
                dl_argv = [str(binary),'encode','-i',str(big_ppm),'-o',str(dl_jpg),'--mode','lossy',
                           '--progressive','successive-approximation','--backend','scalar','--timeout',dl_sec]
                dl_r = subprocess.run(dl_argv, capture_output=True, text=True, timeout=30)
                report['commands'].append({'argv':dl_argv,'condition':f'codec deadline sweep ({dl_sec}s)',
                                           'exit_code':dl_r.returncode,'allowed_exit_codes':[0, 5],
                                           'stdout':dl_r.stdout,'stderr':dl_r.stderr,'output_exists':dl_jpg.exists()});save()
                assert dl_r.returncode != 130 and dl_r.returncode in (0, 5), (dl_argv, dl_r.returncode, dl_r.stderr)
                if dl_r.returncode == 5:
                    assert 'resourceLimitExceeded:' in dl_r.stderr and not dl_jpg.exists(), (dl_argv, dl_r.stderr)
                else:
                    assert dl_jpg.exists() and not dl_r.stderr, (dl_argv, dl_r.stderr)
                    dl_bytes = dl_jpg.read_bytes()
                    assert dl_bytes.startswith(b'\xff\xd8') and dl_bytes.endswith(b'\xff\xd9')
                dl_codes.append(dl_r.returncode)
            assert 5 in dl_codes, dl_codes

            # Missing input file, directory input, or named FIFO input (exit 6 without blocking).
            cli('inspect','-i',str(temp/'does_not_exist.jpg'),expected=6)
            cli('inspect','-i',str(temp),'--input-format','jpeg',expected=6)
            fifo_path = temp/'named_fifo.jpg'
            os.mkfifo(fifo_path)
            cli('inspect','-i',str(fifo_path),'--input-format','jpeg',expected=6)

            # 6. User cancellation (SIGINT -> exit 130) on both decode and inspect without leaving output files.
            cancel_out = temp/'cancelled_out.nrrd'
            for cancel_argv in [
                [str(binary),'decode','-i','-','--input-format','jpeg','-o',str(cancel_out)],
                [str(binary),'inspect','-i','-','--input-format','jpeg']
            ]:
                r_fd, w_fd = os.pipe()
                try:
                    proc = subprocess.Popen(
                        cancel_argv,
                        stdin=r_fd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
                    )
                    os.close(r_fd); r_fd = -1
                    time.sleep(0.05)
                    proc.send_signal(signal.SIGINT)
                    out_s, err_s = proc.communicate(timeout=10)
                finally:
                    if r_fd >= 0: os.close(r_fd)
                    os.close(w_fd)
                report['commands'].append({'argv':cancel_argv,
                                           'condition':'SIGINT during pipe read','exit_code':proc.returncode,
                                           'expected_exit_code':130,'stderr':err_s});save()
                assert proc.returncode == 130 and not cancel_out.exists(), (proc.returncode, err_s)

            # 7. Closed stdout pipe -> exit 6.
            readfd,writefd=os.pipe();os.close(readfd)
            try:
                r=subprocess.run([str(binary),'--help'],stdout=writefd,stderr=subprocess.PIPE,text=True,timeout=10)
            finally:os.close(writefd)
            report['commands'].append({'argv':[str(binary),'--help'],'condition':'stdout pipe with no readers',
                                       'exit_code':r.returncode,'expected_exit_code':6,'stderr':r.stderr});save()
            assert r.returncode==6 and 'I/O failure' in r.stderr

            # 8. Installation and repeat update must carry the matching manual even if one is stale.
            stage=temp/'stage with spaces';prefix='/opt/suite tools';installed=stage/'opt/suite tools'
            command=[repo/'Scripts/install-cli.sh','--binary',binary,'--prefix',prefix,'--destdir',stage]
            run(command);assert (installed/'bin'/tool).stat().st_mode & 0o777==0o755
            page=installed/'share/man/man1'/(tool+'.1');assert page.read_bytes()==manual.read_bytes()
            page.write_text('obsolete manual\n');run(command);assert page.read_bytes()==manual.read_bytes()
            assert page.stat().st_mode & 0o777==0o644
            run([installed/'bin'/tool,'--version'])
            man=shutil.which('man');mandoc=shutil.which('mandoc')
            if not man or not mandoc:raise RuntimeError('man and mandoc are required for manual qualification')
            location=run([man,'-M',installed/'share/man','-w',tool]);assert str(page) in location.stdout
            lint=run([mandoc,'-T','lint',page]);assert not lint.stdout and not lint.stderr,(lint.stdout,lint.stderr)
            rendered=run([mandoc,'-T','ascii',page]);(out/'manual-rendered.txt').write_text(rendered.stdout)
            plain=re.sub(r'.\x08', '', rendered.stdout)
            (out/'manual-plain.txt').write_text(plain)
            assert 'DIAGNOSTIC LEVELS' in plain and tool in plain
            (out/'manual.1').write_bytes(manual.read_bytes())
            run([repo/'Scripts/install-cli.sh','--prefix','relative','--binary',binary],2)
            run([repo/'Scripts/install-cli.sh','--binary'],2)
            wrong=temp/'wrong version';wrong.write_text('#!/bin/sh\nprintf "wrong 0\\n"\n');wrong.chmod(0o755)
            run([repo/'Scripts/install-cli.sh','--binary',wrong,'--prefix',prefix,'--destdir',stage],2)
            assert page.read_bytes()==manual.read_bytes()
            environment=dict(os.environ,DESTDIR=str(stage))
            run([repo/'Scripts/install-cli.sh','--binary',binary,'--prefix',prefix],env=environment)

            # Reject a stale source manual before changing an installed binary/manual pair.
            fixture=temp/'stale source';(fixture/'Scripts').mkdir(parents=True);(fixture/'ManPages').mkdir()
            shutil.copy2(repo/'Scripts/install-cli.sh',fixture/'Scripts/install-cli.sh')
            (fixture/'VERSION').write_text(version+'\n')
            (fixture/'ManPages'/(tool+'.1')).write_text('.TH '+tool.upper()+' 1 "September 19, 2026" "0.0.0"\n')
            run([fixture/'Scripts/install-cli.sh','--binary',binary,'--prefix',prefix,'--destdir',stage],2)
            assert page.read_bytes()==manual.read_bytes()
            # A symlink destination is refused instead of following it outside the installation.
            (installed/'bin'/tool).unlink();(installed/'bin'/tool).symlink_to(payload)
            run(command,6);assert payload.read_bytes()==b'unchanged'
        report['status']='passed';report['checks']=len(report['commands']);save()
        print(f'{tool}: {len(report["commands"])} process checks passed');return 0
    except Exception as error:
        report['status']='failed';report['failure']=str(error);save();raise
if __name__=='__main__':sys.exit(main())
