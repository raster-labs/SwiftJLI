import Foundation
import Dispatch
@testable import SwiftJLI
@main struct Bench {
 static func main() async throws {
  for (width,height,sampling) in [(512,512,JLIChromaSubsampling.yuv420),(513,509,.yuv420),(512,512,.yuv444)] {
   var pixels = [UInt8](repeating: 0, count: width*height*3)
   for y in 0..<height { for x in 0..<width { for c in 0..<3 { pixels[(y*width+x)*3+c] = UInt8(truncatingIfNeeded: x*13+y*7+c*61) } } }
   let input = try JLIImage(width:width,height:height,pixelFormat:.uint8,colorModel:.rgb,data:pixels)
   var cfg = JLIEncoderConfiguration.default; cfg.chromaSubsampling = sampling
   let jpeg = Data(try JLIEncoder().encode(input, configuration:cfg))
   let decoder = try SwiftJLI.Decoder()
   for (name,policy) in [("scalar",ExecutionPolicy.scalarCPU),("automatic",.automatic)] {
    var times = [Double]()
    for iteration in 0..<25 {
     let start = DispatchTime.now().uptimeNanoseconds
     let output = try await decoder.decode(jpeg, options:.init(executionPolicy:policy))
     let ms = Double(DispatchTime.now().uptimeNanoseconds-start)/1e6
     guard output.image.descriptor.width == width, output.report.copyEvents.isEmpty else { fatalError("invalid result") }
     if iteration >= 5 { times.append(ms) }
    }
    let item: [String:Any] = ["case":"\(width)x\(height)-\(sampling)","policy":name,"encodedBytes":jpeg.count,"warmups":5,"milliseconds":times]
    print(String(decoding:try JSONSerialization.data(withJSONObject:item,options:[.sortedKeys]),as:UTF8.self))
   }
  }
 }
}
