// SPDX-License-Identifier: Apache-2.0
// Development-only cold-process allocation check. All fixture and callback setup
// precedes arming. Public module import is intentional; no @testable shortcuts.
import Foundation
import SwiftJLI
import Darwin
import ProbeControl

let args = CommandLine.arguments
precondition(args.count == 5, "MODE JPEG OUTPUT_CAPACITY WORKSPACE_CAPACITY")
let mode = args[1]
var bytes = try Data(contentsOf: URL(fileURLWithPath: args[2]))
let invalid = mode.hasSuffix("-invalid")
let missingDQT = mode.hasSuffix("-missing-dqt")
let entropyFailure = mode.hasSuffix("-entropy")
if invalid { bytes[0] = 0 }
if entropyFailure {
    let positions = (0..<(bytes.count - 1)).filter { bytes[$0] == 0xff && bytes[$0 + 1] == 0xda }
    let sos = positions[0]
    let length = Int(bytes[sos + 2]) * 256 + Int(bytes[sos + 3])
    bytes = bytes.prefix(sos + 2 + length) + [0xff, 0xd9]
}
if missingDQT {
    let valid = Array(bytes)
    var stripped = Array(valid.prefix(2)), offset = 2
    while offset + 4 < valid.count && valid[offset + 1] != 0xda {
        let end = offset + 2 + Int(valid[offset + 2]) * 256 + Int(valid[offset + 3])
        if valid[offset + 1] != 0xdb { stripped += valid[offset..<end] }
        offset = end
    }
    stripped += valid[offset...]; bytes = Data(stripped)
}
let outCount = Int(args[3])!, workCount = Int(args[4])!
let output = UnsafeMutableRawPointer.allocate(byteCount: outCount, alignment: 16)
let work = UnsafeMutableRawPointer.allocate(byteCount: workCount, alignment: 16)
defer { output.deallocate(); work.deallocate() }
let destination = UnsafeMutableRawBufferPointer(start: output, count: outCount)
let workspace = UnsafeMutableRawBufferPointer(start: work, count: workCount)
guard let path = getenv("DYLD_INSERT_LIBRARIES"), let library = dlopen(path, RTLD_NOW) else {
    fputs("Set DYLD_INSERT_LIBRARIES to the probe interposer.\n", stderr); exit(2)
}
let arm = unsafeBitCast(dlsym(library, "qj_arm")!, to: (@convention(c) () -> Void).self)
let disarm = unsafeBitCast(dlsym(library, "qj_disarm")!, to: (@convention(c) () -> Void).self)
let allocations = unsafeBitCast(dlsym(library, "qj_allocations")!, to: (@convention(c) () -> UInt64).self)
let mappings = unsafeBitCast(dlsym(library, "qj_mappings")!, to: (@convention(c) () -> UInt64).self)
let decoder = QualifiedJPEGDecoder(profile: .jliswift060)
var ok = false
var produced = 0
let cancelled = mode.hasSuffix("-cancel")
let token = QualifiedCancellation(isCancelled: cancelled ? { _ in true } : nil)
bytes.withUnsafeBytes { input in
    // Dispatch happens outside the measurement; the first call really is cold.
    if mode.hasPrefix("inspect-lossless") {
        arm()
        switch decoder.inspectLosslessMonochrome(input, workspace: workspace, cancellation: token) {
        case .success(let info): ok = true; produced = info.outputByteCount
        case .failure(let failure): ok = (cancelled && failure.kind == .cancelled) || (invalid && failure.kind == .invalidJPEG) || (entropyFailure && failure.kind == .decoding) || (missingDQT && failure.code == 178 && failure.kind == .decoding)
        }
        disarm()
    } else if mode.hasPrefix("decode-lossless") {
        arm()
        switch decoder.decodeLosslessMonochrome(input, into: destination, workspace: workspace, cancellation: token) {
        case .success(let info): ok = true; produced = info.outputByteCount
        case .failure(let failure): ok = (cancelled && failure.kind == .cancelled) || (invalid && failure.kind == .invalidJPEG) || (entropyFailure && failure.kind == .decoding) || (missingDQT && failure.code == 178 && failure.kind == .decoding)
        }
        disarm()
    } else if mode.hasPrefix("inspect-rgb") {
        arm()
        switch decoder.inspectBaselineRGB(input, headerWorkspace: workspace, cancellation: token) {
        case .success(let info): ok = true; produced = info.outputByteCount
        case .failure(let failure): ok = (cancelled && failure.kind == .cancelled) || (invalid && failure.kind == .invalidJPEG) || (entropyFailure && failure.kind == .decoding) || (missingDQT && failure.code == 178 && failure.kind == .decoding)
        }
        disarm()
    } else if mode.hasPrefix("decode-rgb") {
        arm()
        switch decoder.decodeBaselineRGB(input, arena: destination, workspace: workspace, cancellation: token) {
        case .success(let info): ok = true; produced = info.outputByteCount
        case .failure(let failure): ok = (cancelled && failure.kind == .cancelled) || (invalid && failure.kind == .invalidJPEG) || (entropyFailure && failure.kind == .decoding) || (missingDQT && failure.code == 178 && failure.kind == .decoding)
        }
        disarm()
    } else if mode == "control" {
        arm()
        let pointer = qjp_allocate(65536)!
        pointer.storeBytes(of: UInt8(17), as: UInt8.self)
        produced = Int(pointer.load(as: UInt8.self))
        disarm(); qjp_free(pointer); ok = produced == 17
    } else if mode == "swift-control" {
        arm()
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: 65536, alignment: 16)
        pointer.storeBytes(of: UInt8(23), as: UInt8.self)
        produced = Int(pointer.load(as: UInt8.self))
        disarm(); pointer.deallocate(); ok = produced == 23
    }
}
let count = allocations(), maps = mappings()
print("{\"mode\":\"\(mode)\",\"allocations\":\(count),\"mappings\":\(maps),\"producedBytes\":\(produced),\"outcomeExpected\":\(ok)}")
if !ok || (mode.hasSuffix("control") ? count == 0 : count != 0 || maps != 0) { exit(1) }
