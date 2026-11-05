import Foundation
import MODULE
let args = CommandLine.arguments
let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let rgb = args[2] == "rgb"
let decoder = DECODER
let workPointer = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 16)
defer { workPointer.deallocate() }
let workspace = UnsafeMutableRawBufferPointer(start: workPointer, count: 1 << 20)
func value<T>(_ outcome: OUTCOME<T>) -> T {
    switch outcome { case .success(let value): return value; case .failure: fatalError("parity decode refused") }
}
let output = data.withUnsafeBytes { input -> Data in
    if rgb {
        let info = value(decoder.INSPECT_RGB(input, headerWorkspace: workspace CONFIG))
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: info.arenaByteCount, alignment: 16)
        defer { pointer.deallocate() }
        let arena = UnsafeMutableRawBufferPointer(start: pointer, count: info.arenaByteCount)
        precondition(value(decoder.DECODE_RGB(input, arena: arena, workspace: workspace CONFIG)) == info)
        return Data(bytes: pointer, count: info.outputByteCount)
    } else {
        let info = value(decoder.INSPECT_LOSSLESS(input, workspace: workspace))
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: info.outputByteCount, alignment: 16)
        defer { pointer.deallocate() }
        precondition(value(decoder.DECODE_LOSSLESS(input, into: .init(start: pointer, count: info.outputByteCount), workspace: workspace)) == info)
        return Data(bytes: pointer, count: info.outputByteCount)
    }
}
try output.write(to: URL(fileURLWithPath: args[4]))
