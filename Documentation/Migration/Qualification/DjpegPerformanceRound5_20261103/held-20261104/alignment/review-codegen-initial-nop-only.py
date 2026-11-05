"""Read-only Mach-O proof for the entry-alignment diagnostic; never builds/runs codecs."""
from pathlib import Path
import datetime
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'build1'
NOP = struct.pack('<I', 0xd503201f)
ROWS = ['_sjli_lossless_left_u16_row', '_sjli_lossless_left_u16_code0_row']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class MachO:
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        header = struct.unpack_from('<8I', self.data)
        assert header[0] == 0xfeedfacf and header[1] == 0x100000c
        self.sections = []
        self.symbols = []
        pos = 32
        symtab = None
        for _ in range(header[4]):
            command, size = struct.unpack_from('<II', self.data, pos)
            if command == 0x19:
                count = struct.unpack_from('<I', self.data, pos + 64)[0]
                for index in range(count):
                    base = pos + 72 + index * 80
                    name = self.data[base:base + 16].split(b'\0')[0].decode()
                    segment = self.data[base + 16:base + 32].split(b'\0')[0].decode()
                    address, length, offset, alignment, relocs, nrelocs = struct.unpack_from('<QQIIII', self.data, base + 32)
                    self.sections.append(dict(name=name, segment=segment, address=address,
                                              length=length, offset=offset, alignment=alignment,
                                              relocs=relocs, nrelocs=nrelocs))
            elif command == 2:
                symtab = struct.unpack_from('<4I', self.data, pos + 8)
            pos += size
        assert symtab is not None
        symoff, nsyms, stroff, strsize = symtab
        for index in range(nsyms):
            string, typ, section, desc, value = struct.unpack_from('<IBBHQ', self.data, symoff + index * 16)
            end = self.data.find(b'\0', stroff + string)
            assert 0 <= string < strsize and end >= stroff + string
            name = self.data[stroff + string:end].decode(errors='replace')
            self.symbols.append(dict(name=name, type=typ, section=section, value=value))
        self.text = next(s for s in self.sections if s['segment'] == '__TEXT' and s['name'] == '__text')
        self.entries = {s['name']: s['value'] for s in self.symbols
                        if s['name'].startswith('_sjli_') and s['type'] & 0xe == 0xe}
        assert len(self.entries) == 4
        self.relocations = []
        for index in range(self.text['nrelocs']):
            address, info = struct.unpack_from('<iI', self.data, self.text['relocs'] + 8 * index)
            assert address >= 0, 'Scattered relocation unsupported by this proof'
            external = (info >> 27) & 1
            symbol = info & 0xffffff
            self.relocations.append(dict(address=address, type=info >> 28,
                                         pcrel=(info >> 24) & 1, length=(info >> 25) & 3,
                                         external=external,
                                         target=self.symbols[symbol]['name'] if external else 'section:' + str(symbol)))

    def text_bytes(self):
        t = self.text
        return self.data[t['offset']:t['offset'] + t['length']]

    def at(self, address, count):
        t = self.text
        assert t['address'] <= address and address + count <= t['address'] + t['length']
        offset = t['offset'] + address - t['address']
        return self.data[offset:offset + count]

    def body(self, name):
        start = self.entries[name]
        end = min([value for value in self.entries.values() if value > start]
                  + [self.text['address'] + self.text['length']])
        raw = self.at(start, end - start)
        padding = 0
        while raw.endswith(NOP):
            raw = raw[:-4]
            padding += 4
        relocations = []
        canonical = bytearray(raw)
        for reloc in self.relocations:
            absolute = reloc['address'] + self.text['address']
            if start <= absolute < start + len(raw):
                relative = absolute - start
                item = dict(reloc, relativeOffset=relative)
                del item['address']
                # Only the known external BL relocation may vary with placement.
                assert item['type'] == 2 and item['pcrel'] == 1 and item['length'] == 2 and item['external'] == 1
                word = struct.unpack_from('<I', canonical, relative)[0]
                assert word & 0xfc000000 == 0x94000000
                struct.pack_into('<I', canonical, relative, word & 0xfc000000)
                relocations.append(item)
        return bytes(canonical), sorted(relocations, key=lambda r: r['relativeOffset']), padding


def equal_bodies(a, b):
    assert set(a.entries) == set(b.entries)
    rows = {}
    for name in a.entries:
        ab, ar, ap = a.body(name)
        bb, br, bp = b.body(name)
        rows[name] = dict(passed=ab == bb and ar == br, instructionBytes=len(ab),
                          instructionCount=len(ab) // 4,
                          canonicalSHA256=hashlib.sha256(ab).hexdigest(),
                          firstPaddingBytes=ap, secondPaddingBytes=bp,
                          callRelocations=ar)
    return rows


def linked_body_proof(obj, binary):
    result = {}
    for name in obj.entries:
        canonical, relocs, padding = obj.body(name)
        expected = bytearray(canonical)
        for reloc in relocs:
            pc = binary.entries[name] + reloc['relativeOffset']
            target = binary.entries[reloc['target']]
            delta = target - pc
            assert delta % 4 == 0 and -(1 << 27) <= delta < (1 << 27)
            word = 0x94000000 | ((delta // 4) & 0x3ffffff)
            struct.pack_into('<I', expected, reloc['relativeOffset'], word)
        actual = binary.at(binary.entries[name], len(expected))
        entry = binary.entries[name]
        result[name] = dict(passed=actual == expected, address=hex(entry),
                            mod32=entry % 32, mod64=entry % 64, mod128=entry % 128,
                            bodyBytes=len(expected), linkedBodySHA256=hashlib.sha256(actual).hexdigest())
    return result


def main():
    destination = OUT / 'codegen-gate.json'
    assert not destination.exists(), 'Refusing to overwrite codegen gate'
    receipt_path = OUT / 'build.json'
    receipt_hash = sha(receipt_path)
    receipt = json.loads(receipt_path.read_text())
    assert receipt['inputsUnchanged'] and receipt['status'] == 'built; codegen and actual linked alignment gate pending'
    control = MachO(receipt['products']['control']['path'])
    aligned = MachO(receipt['products']['aligned']['path'])
    originals = {owner: MachO(receipt['binaries'][owner + 'Original']['cObject']) for owner in ['baseline', 'candidate']}
    comparisons = {owner: equal_bodies(control, obj) for owner, obj in originals.items()}
    aligned_comparison = equal_bodies(control, aligned)
    original_text_matches = {owner: control.text_bytes() == obj.text_bytes() for owner, obj in originals.items()}
    linked = {}
    pins = {str(Path(__file__).resolve()): sha(__file__), str(receipt_path): receipt_hash}
    for label, product in receipt['products'].items():
        assert sha(product['path']) == product['sha256']
        pins[product['path']] = product['sha256']
    binary_hashes = {}
    for label, item in receipt['binaries'].items():
        assert sha(item['path']) == item['sha256'] and sha(item['cObject']) == item['cObjectSHA256']
        assert sha(item['swiftObject']) == receipt['pins'][item['swiftObject']]
        binary_hashes[label] = item['sha256']
        pins[item['path']] = item['sha256']
        pins[item['cObject']] = item['cObjectSHA256']
        pins[item['swiftObject']] = receipt['pins'][item['swiftObject']]
        binary = MachO(item['path'])
        owner = 'baseline' if label.startswith('baseline') else 'candidate'
        obj = aligned if label.endswith('Aligned') else originals[owner]
        linked[label] = linked_body_proof(obj, binary)
    bodies_equal = all(row['passed'] for comparison in comparisons.values() for row in comparison.values())
    aligned_equal = all(row['passed'] for row in aligned_comparison.values())
    linked_equal = all(row['passed'] for comparison in linked.values() for row in comparison.values())
    entries_aligned = all(linked[label][name]['mod128'] == 0 for label in ['baselineAligned', 'candidateAligned'] for name in ROWS)
    all_checks = dict(controlTextEqualsBothOriginals=all(original_text_matches.values()),
                      controlBodiesAndCallsEqualBothOriginals=bodies_equal,
                      alignedBodiesAndCallsUnchanged=aligned_equal,
                      allLinkedBodiesMatchResolvedObjectCode=linked_equal,
                      bothAlignedBinaryRowEntriesModulo128Zero=entries_aligned)
    gate = dict(passed=all(all_checks.values()),
                createdUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                method='Direct Mach-O text, symbol and relocation parsing. Compare every body byte after stripping only trailing boundary NOPs and canonicalising external BL displacement with exact relocation-target equality. Verify every actual linked byte after resolving BL to its recorded symbol. No builds, profiling or codec execution.',
                buildReceiptSHA256=receipt_hash, binarySHA256=binary_hashes,
                pins=pins, checks=all_checks,
                controlTextMatches=original_text_matches,
                controlComparisons=comparisons, alignedComparison=aligned_comparison,
                linkedBodies=linked,
                ABIFrameCallConclusion='Byte equality preserves all opcodes, registers, stack allocation, spills/restores, local branches, sample state and public ABI; the only external call target remains the generic row. Entry padding is excluded only after the last non-NOP instruction of each body.',
                limitations=['This gate permits diagnostic timing only; it does not establish a speed benefit, causal explanation, safety qualification or acceptance of ba277.',
                             '128-byte entry alignment stabilises residues modulo32/64/128; inner loops are not asserted to begin on an alignment boundary.'])
    assert sha(receipt_path) == receipt_hash
    assert all(sha(path) == value for path, value in pins.items())
    destination.write_text(json.dumps(gate, indent=2) + '\n')
    print(json.dumps({'path': str(destination), 'passed': gate['passed'], 'checks': all_checks}, indent=2))
    assert gate['passed'], 'Codegen gate failed'


if __name__ == '__main__':
    main()
