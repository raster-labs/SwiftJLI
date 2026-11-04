struct Owner: ~Copyable {
 let pointer: UnsafeMutableRawPointer
 let count: Int
 init(_ count: Int) { self.count = count; pointer = .allocate(byteCount: count, alignment: 16) }
 deinit { pointer.deallocate() }
 var bytes: UnsafeMutableRawBufferPointer { .init(start: pointer, count: count) }
}
struct Cancellation {
 let context: UnsafeRawPointer?
 let check: @convention(c) (UnsafeRawPointer?) -> Bool
}
enum Outcome<T: ~Copyable>: ~Copyable { case success(T), failure(Int) }
func synchronous(_ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawBufferPointer,
                 cancellation: Cancellation) -> Outcome<Int> {
 if cancellation.check(cancellation.context) { return .failure(1) }
 guard input.count <= output.count else { return .failure(2) }
 output.copyMemory(from: input)
 return .success(input.count)
}
func adapt(_ input: borrowing Owner, _ output: borrowing Owner) -> Outcome<Int> {
 var cancelled = false
 return withUnsafePointer(to: &cancelled) { pointer in
  synchronous(UnsafeRawBufferPointer(input.bytes), into: output.bytes,
    cancellation: .init(context: pointer, check: { $0!.assumingMemoryBound(to: Bool.self).pointee }))
 }
}
let input = Owner(2), output = Owner(4)
input.bytes[0] = 17; input.bytes[1] = 255
switch adapt(input, output) {
case .success(let count): precondition(count == 2 && output.bytes[0] == 17 && output.bytes[1] == 255)
case .failure: fatalError("probe failed")
}
