// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
struct QualifiedMarkerReader {
    private let data: QualifiedByteView
    private let callerStorage: QualifiedParseCapture
    private var offset = 0
    private var cancellation: QualifiedCancellation
    private var nextCancellationCheckpoint = 65_536
    init(borrowing bytes: UnsafeRawBufferPointer, storage: QualifiedParseCapture, cancellation: QualifiedCancellation) {
        data = QualifiedByteView(borrowing: bytes); callerStorage = storage; self.cancellation = cancellation
    }
    mutating func parseCore() -> QualifiedParseOutcome {
        if case .failure(let failure) = validateSOI() { return .failure(failure) }
        var frame = QualifiedFrameSlot.none
        var scans = callerStorage.records.scanStorage()
        var interval = 0
        var sawEOI = false
        markers: while offset < data.count - 1 {
            if case .failure(let failure) = cancellation.check() { return .failure(failure) }
            let marker: UInt8
            switch nextMarker() {
            case .failure(let failure): return .failure(failure)
            case .success(nil): break markers
            case .success(.some(let value)): marker = value
            }
            switch marker {
            case QualifiedMarker.sof0, QualifiedMarker.sof3:
                guard case .none = frame else { return .failure(.init(code: 101, kind: .decoding)) }
                switch readSOF(progressive: false, lossless: marker == QualifiedMarker.sof3) {
                case .success(let value): frame = .some(value)
                case .failure(let failure): return .failure(failure)
                }
            case QualifiedMarker.sof1, QualifiedMarker.sof2:
                return .failure(.init(code: 174, kind: .unsupported))
            case QualifiedMarker.dqt:
                if case .failure(let failure) = readDQT() { return .failure(failure) }
            case QualifiedMarker.dht:
                if case .failure(let failure) = readDHT() { return .failure(failure) }
            case QualifiedMarker.dri:
                switch readUInt16() {
                case .success(4): break
                case .success: return .failure(.init(code: 102, kind: .decoding))
                case .failure(let failure): return .failure(failure)
                }
                switch readUInt16() {
                case .success(let value): interval = Int(value)
                case .failure(let failure): return .failure(failure)
                }
            case QualifiedMarker.sos:
                guard scans.count < callerStorage.maximumScans else { return .failure(.init(code: 103, kind: .unsupported)) }
                let scan: QualifiedScanHeader
                switch readSOS() {
                case .success(let value): scan = value
                case .failure(let failure): return .failure(failure)
                }
                let entropy: Range<Int>
                switch readEntropyRange() {
                case .success(let value): entropy = value
                case .failure(let failure): return .failure(failure)
                }
                if case .failure(let failure) = callerStorage.scan(scan, frame: frame, entropy: entropy, restartInterval: interval) { return .failure(failure) }
                scans.append(QualifiedScanData(header: scan)); callerStorage.records.didAppendScan()
            case QualifiedMarker.eoi:
                guard offset == data.count || (offset % 2 == 1 && offset + 1 == data.count && data[offset] == 0) else {
                    return .failure(.init(code: 104, kind: .decoding))
                }
                sawEOI = true; break markers
            case QualifiedMarker.app1, QualifiedMarker.app2, 0xee:
                switch readSegmentRange() {
                case .success(let range): callerStorage.application(marker: marker, range: range, input: data)
                case .failure(let failure): return .failure(failure)
                }
            case 0xd0...0xd7: continue
            default:
                if case .failure(let failure) = skipSegment() { return .failure(failure) }
            }
        }
        guard sawEOI else { return .failure(.init(code: 105, kind: .decoding)) }
        guard case .some(let value) = frame else { return .failure(.init(code: 106, kind: .invalidJPEG)) }
        return .success(QualifiedParsedJPEG(frameInfo: value, scans: scans))
    }
    private mutating func readDQT() -> QualifiedOutcome<Void> {
        let end: Int
        switch segmentEnd(minimumPayload: 0) {
        case .success(let value): end = value
        case .failure(let failure): return .failure(failure)
        }
        while offset < end {
            let info: UInt8
            switch readByte() {
            case .success(let value): info = value
            case .failure(let failure): return .failure(failure)
            }
            let precision = Int(info >> 4), id = Int(info & 15)
            guard precision <= 1 else { return .failure(.init(code: 113, kind: .decoding, detail0: precision)) }
            guard id <= 3 else { return .failure(.init(code: 114, kind: .decoding, detail0: id)) }
            let count = 64 * (precision + 1)
            guard count <= end - offset else { return .failure(.init(code: 115, kind: .decoding)) }
            let start = offset; offset += count
            callerStorage.quantization(id: id, precision: precision, range: start..<offset)
        }
        return .success(())
    }
    private mutating func readDHT() -> QualifiedOutcome<Void> {
        let end: Int
        switch segmentEnd(minimumPayload: 0) {
        case .success(let value): end = value
        case .failure(let failure): return .failure(failure)
        }
        while offset < end {
            let info: UInt8
            switch readByte() {
            case .success(let value): info = value
            case .failure(let failure): return .failure(failure)
            }
            let tableClass = Int(info >> 4), id = Int(info & 15)
            guard tableClass <= 1 else { return .failure(.init(code: 175, kind: .decoding)) }
            guard end - offset >= 16 else { return .failure(.init(code: 116, kind: .decoding)) }
            let bits = offset
            var count = 0, space = 0
            for length in 1...16 {
                let value = Int(data[offset]); offset += 1
                count += value; space += value
                guard space <= (1 << length) else { return .failure(.init(code: 117, kind: .decoding, detail0: length)) }
                space <<= 1
            }
            guard count <= 256 else { return .failure(.init(code: 118, kind: .decoding)) }
            guard count <= end - offset else { return .failure(.init(code: 119, kind: .decoding)) }
            let values = offset; offset += count
            callerStorage.table(isDC: tableClass == 0, id: id, bits: bits, values: values, count: count)
        }
        return .success(())
    }
    private mutating func segmentEnd(minimumPayload: Int) -> QualifiedOutcome<Int> {
        let coreOutcome1 = readUInt16()
        guard case .success(let coreValue1) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }
        let payload = Int(coreValue1) - 2
        guard payload >= minimumPayload, payload <= data.count - offset else {
            return .failure(QualifiedFailure(code: 107, kind: .decoding))
        }
        return .success(offset + payload)
    }
    private mutating func validateSOI() -> QualifiedOutcome<Void> {
        guard data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 else {
            return .failure(QualifiedFailure(code: 108, kind: .invalidJPEG))
        }
        offset = 2
        return .success(())
    }
    private mutating func nextMarker() -> QualifiedOutcome<UInt8?> {
        while offset < data.count {
            if case .failure(let failure) = checkCancellation() { return .failure(failure) }
            if data[offset] == 0xFF {
                offset += 1
                // Skip padding 0xFF bytes
                while offset < data.count && data[offset] == 0xFF {
                    if case .failure(let failure) = checkCancellation() { return .failure(failure) }
                    offset += 1
                }
                if offset < data.count && data[offset] != 0x00 {
                    let marker = data[offset]
                    offset += 1
                    return .success(marker)
                }
            } else {
                offset += 1
            }
        }
        return .success(nil)
    }
    private mutating func skipSegment() -> QualifiedOutcome<Void> {
        let coreOutcome1 = readUInt16()
        guard case .success(let length) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }
        let skip = Int(length) - 2
        guard skip >= 0, offset + skip <= data.count else {
            return .failure(QualifiedFailure(code: 109, kind: .decoding))
        }
        offset += skip
        return .success(())
    }
    private mutating func readSegmentRange() -> QualifiedOutcome<Range<Int>> {
        let coreOutcome1 = segmentEnd(minimumPayload: 0)
        guard case .success(let end) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }
        let start = offset
        offset = end
        return .success(start..<end)
    }
    private mutating func readSOF(progressive: Bool, lossless: Bool = false) -> QualifiedFrameOutcome {
        let coreOutcome1 = segmentEnd(minimumPayload: 6)
        guard case .success(let endOffset) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }

        let coreOutcome2 = readByte()
        guard case .success(let coreValue2) = coreOutcome2 else { return .failure(coreOutcome2.failureValue) }
        let precision = Int(coreValue2)
        let coreOutcome3 = readUInt16()
        guard case .success(let coreValue3) = coreOutcome3 else { return .failure(coreOutcome3.failureValue) }
        let height = Int(coreValue3)
        let coreOutcome4 = readUInt16()
        guard case .success(let coreValue4) = coreOutcome4 else { return .failure(coreOutcome4.failureValue) }
        let width = Int(coreValue4)
        let coreOutcome5 = readByte()
        guard case .success(let coreValue5) = coreOutcome5 else { return .failure(coreOutcome5.failureValue) }
        let numComponents = Int(coreValue5)
        if !callerStorage.accepts(componentCount: numComponents) {
            return .failure(QualifiedFailure(code: 111, kind: .unsupported))
        }

        guard endOffset - offset == numComponents * 3 else { return .failure(QualifiedFailure(code: 112, kind: .decoding)) }
        var components = callerStorage.records.frameStorage()
        for _ in 0..<numComponents {
            let coreOutcome6 = readByte()
            guard case .success(let id) = coreOutcome6 else { return .failure(coreOutcome6.failureValue) }
            let coreOutcome7 = readByte()
            guard case .success(let sampling) = coreOutcome7 else { return .failure(coreOutcome7.failureValue) }
            let coreOutcome8 = readByte()
            guard case .success(let quantId) = coreOutcome8 else { return .failure(coreOutcome8.failureValue) }
            guard !components.contains(where: { $0.id == id }) else {
                return .failure(.init(code: 177, kind: .decoding))
            }
            components.append(QualifiedComponentInfo(
                id: id,
                horizontalSampling: Int(sampling >> 4),
                verticalSampling: Int(sampling & 0x0F),
                quantTableIndex: Int(quantId)
            ))
        }

        offset = endOffset
        return .success(QualifiedFrameInfo(
            precision: precision,
            width: width,
            height: height,
            components: components,
            isProgressive: progressive,
            isLossless: lossless
        ))
    }
    private mutating func readSOS() -> QualifiedScanHeaderOutcome {
        let coreOutcome1 = segmentEnd(minimumPayload: 4)
        guard case .success(let endOffset) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }

        let coreOutcome2 = readByte()
        guard case .success(let coreValue2) = coreOutcome2 else { return .failure(coreOutcome2.failureValue) }
        let numComponents = Int(coreValue2)
        if !callerStorage.accepts(componentCount: numComponents) {
            return .failure(QualifiedFailure(code: 120, kind: .unsupported))
        }
        guard endOffset - offset == numComponents * 2 + 3 else { return .failure(QualifiedFailure(code: 121, kind: .decoding)) }
        var components = callerStorage.records.componentStorage()

        for _ in 0..<numComponents {
            let coreOutcome3 = readByte()
            guard case .success(let selector) = coreOutcome3 else { return .failure(coreOutcome3.failureValue) }
            let coreOutcome4 = readByte()
            guard case .success(let tableIds) = coreOutcome4 else { return .failure(coreOutcome4.failureValue) }
            components.append((
                componentSelector: selector,
                dcTableId: Int(tableIds >> 4),
                acTableId: Int(tableIds & 0x0F)
            ))
        }

        let coreOutcome5 = readByte()
        guard case .success(let coreValue5) = coreOutcome5 else { return .failure(coreOutcome5.failureValue) }
        let spectralStart = Int(coreValue5)
        let coreOutcome6 = readByte()
        guard case .success(let coreValue6) = coreOutcome6 else { return .failure(coreOutcome6.failureValue) }
        let spectralEnd = Int(coreValue6)
        let coreOutcome7 = readByte()
        guard case .success(let successive) = coreOutcome7 else { return .failure(coreOutcome7.failureValue) }

        return .success(QualifiedScanHeader(
            components: components,
            spectralStart: spectralStart,
            spectralEnd: spectralEnd,
            successiveApproxHigh: Int(successive >> 4),
            successiveApproxLow: Int(successive & 0x0F)
        ))
    }
    private mutating func readEntropyRange() -> QualifiedOutcome<Range<Int>> {
        // The segment is a verbatim slice (stuffed pairs and RST markers stay
        // in; `QualifiedBitReader` unstuffs), so only the END needs finding: scan to the
        // first 0xFF whose successor is neither 0x00 (stuffing) nor 0xD0–0xD7
        // (RST0–7) — or a trailing lone 0xFF — leaving `offset` on the 0xFF for
        // nextMarker(). One slice copy replaces the previous per-byte append
        // (which paid an Array uniqueness check + growth per byte and showed up
        // at ~7-9% of a whole lossless decode).
        let n = data.count
        let start = offset
        var pos = offset
        var nextCheckpoint = pos
        do {
            let p = data
            while pos < n {
                if pos >= nextCheckpoint {
                    if case .failure(let failure) = cancellation.check() { return .failure(failure) }
                    nextCheckpoint = pos > Int.max - 65_536 ? Int.max : pos + 65_536
                }
                if p[pos] != 0xFF { pos += 1; continue }
                guard pos + 1 < n else { break }              // trailing lone 0xFF
                let next = p[pos + 1]
                if next == 0x00 || (next >= 0xD0 && next <= 0xD7) {
                    pos += 2                                   // stuffing / restart
                } else {
                    break                                      // real marker — stop
                }
            }
        }
        offset = pos
        return .success(start..<pos)
    }
    private mutating func checkCancellation() -> QualifiedOutcome<Void> {
        if offset >= nextCancellationCheckpoint {
            if case .failure(let failure) = cancellation.check() { return .failure(failure) }
            nextCancellationCheckpoint = offset > Int.max - 65_536 ? Int.max : offset + 65_536
        }
        return .success(())
    }
    private mutating func readByte() -> QualifiedOutcome<UInt8> {
        if case .failure(let failure) = checkCancellation() { return .failure(failure) }
        guard offset < data.count else {
            return .failure(QualifiedFailure(code: 122, kind: .decoding))
        }
        let byte = data[offset]
        offset += 1
        return .success(byte)
    }
    private mutating func readUInt16() -> QualifiedOutcome<UInt16> {
        let coreOutcome1 = readByte()
        guard case .success(let high) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }
        let coreOutcome2 = readByte()
        guard case .success(let low) = coreOutcome2 else { return .failure(coreOutcome2.failureValue) }
        return .success((UInt16(high) << 8) | UInt16(low))
    }
}
