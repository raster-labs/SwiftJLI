import Foundation
@testable import SwiftJLI
@main struct Export {
 static func main() throws {
  let w = 257, h = 257
  let pixels = (0..<(w*h*3)).map { UInt8(truncatingIfNeeded:$0*13) }
  var cfg = JLIEncoderConfiguration.default; cfg.adaptiveQuantization = false
  let image = try JLIImage(width:w,height:h,pixelFormat:.uint8,colorModel:.rgb,data:pixels)
  try Data(JLIEncoder().encode(image,configuration:cfg)).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
