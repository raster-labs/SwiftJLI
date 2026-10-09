import Foundation
import SwiftJLI
let limits = try ResourceLimits(deadlineSeconds: CommandLine.arguments.contains("--normal") ? 120 : Double.greatestFiniteMagnitude)
do {
    _ = try Decoder().inspect(Data(), options: .init(resourceLimits: limits))
    print("Unexpected success")
} catch { print("Returned error: \(error)") }
