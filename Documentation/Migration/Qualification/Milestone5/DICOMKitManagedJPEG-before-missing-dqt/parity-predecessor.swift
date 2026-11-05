import Foundation
import JLISwift
let args = CommandLine.arguments
let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let rgb = args[2] == "rgb"
let decoder = JLIDecoder()
let workPointer = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 16)
defer { workPointer.deallocate() }
let workspace = UnsafeMutableRawBufferPointer(start: workPointer, count: 1 << 20)
func value<T>(_ outcome: JLICoreOutcome<T>) -> T {
    switch outcome { case .success(let value): return value; case .failure: fatalError("parity decode refused") }
}
let output = data.withUnsafeBytes { input -> Data in
    if rgb {
        let info = value(decoder.inspectBaselineRGBCore(input, headerWorkspace: workspace , configuration: .init(sourceColorModel: args[3] == "rgb" ? .rgb : args[3] == "ycbcr" ? .yCbCr : nil)))
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: info.arenaByteCount, alignment: 16)
        defer { pointer.deallocate() }
        let arena = UnsafeMutableRawBufferPointer(start: pointer, count: info.arenaByteCount)
        precondition(value(decoder.decodeBaselineRGBCore(input, arena: arena, workspace: workspace , configuration: .init(sourceColorModel: args[3] == "rgb" ? .rgb : args[3] == "ycbcr" ? .yCbCr : nil))) == info)
        return Data(bytes: pointer, count: info.outputByteCount)
    } else {
        let info = value(decoder.inspectLosslessMonochromeCore(input, workspace: workspace))
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: info.outputByteCount, alignment: 16)
        defer { pointer.deallocate() }
        precondition(value(decoder.decodeLosslessMonochromeCore(input, into: .init(start: pointer, count: info.outputByteCount), workspace: workspace)) == info)
        return Data(bytes: pointer, count: info.outputByteCount)
    }
}
try output.write(to: URL(fileURLWithPath: args[4]))
