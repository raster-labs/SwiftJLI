// SPDX-License-Identifier: MIT
import Foundation
import Testing
import SwiftJLI

@Test(arguments: [12, 16]) func paddedOddSizedSamplesPreservePrecision(_ precision: Int) throws {
    let descriptor = try ImageDescriptor.greyscale16(
        width: 3, height: 3, meaningfulBits: precision, rowBytes: 8, offset: 2)
    #expect(descriptor.requiredByteCount == 26)
    #expect(descriptor.meaningfulBits == precision)
    let maximum: UInt16 = precision == 12 ? 4095 : 65535
    let values: [UInt16] = [0, maximum, 1, 37, 201, maximum, 0, 2, 997]
    let destination = try ImageDestination.allocate(descriptor: descriptor)
    let image = try destination.write { bytes in
        for y in 0..<3 {
            for x in 0..<3 {
                let offset = 2 + y * 8 + x * 2
                let value = values[y * 3 + x]
                bytes[offset] = UInt8(truncatingIfNeeded: value)
                bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
            }
        }
    }
    let observed = try image.storage.withUnsafeBytes { bytes -> [UInt16] in
        var samples: [UInt16] = []
        for y in 0..<3 {
            for x in 0..<3 {
                let offset = 2 + y * 8 + x * 2
                samples.append(UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
            }
            #expect(bytes[2 + y * 8 + 6] == 0)
            #expect(bytes[2 + y * 8 + 7] == 0)
        }
        #expect(bytes[0] == 0 && bytes[1] == 0)
        return samples
    }
    #expect(observed == values)
    #expect(image.descriptor == descriptor)
}

@Test func shortCapacityAndInvalidStrideAreRejected() throws {
    let short = try PlaneDescriptor(width: 3, height: 2, rowBytes: 8, byteCount: 13)
    #expect(throws: CodecError.self) { try ImageDescriptor(width: 3, height: 2, planes: [short]) }
    let exact = try PlaneDescriptor(width: 3, height: 2, rowBytes: 8, byteCount: 14)
    let descriptor = try ImageDescriptor(width: 3, height: 2, planes: [exact])
    #expect(descriptor.requiredByteCount == 14)
    let insufficientOwner = try OwnedImageStorage(byteCount: 13)
    #expect(throws: CodecError.self) {
        try ImageDestination(descriptor: descriptor, storage: insufficientOwner)
    }
    for row in [-2, 0, 5, 7] {
        #expect(throws: CodecError.self) {
            try ImageDescriptor.greyscale16(width: 3, height: 2, rowBytes: row)
        }
    }
    #expect(throws: CodecError.self) {
        try ImageDescriptor.greyscale16(width: 1, height: 1, offset: 1)
    }
}

@Test func extremeIntegerInputsThrowWithoutOverflowTraps() {
    for (width, height) in [(Int.max, 1), (1, Int.max), (Int.max, Int.max), (-1, 1), (0, 1)] {
        #expect(throws: CodecError.self) {
            try ImageDescriptor.greyscale16(width: width, height: height)
        }
    }
    #expect(throws: CodecError.self) {
        try ImageDescriptor.greyscale16(width: 1, height: 1, offset: Int.max)
    }
    #expect(throws: CodecError.self) {
        try ImageDescriptor.greyscale16(width: 1, height: 2, rowBytes: Int.max - 1)
    }
}

@Test func meaningfulPrecisionRejectsInvalidValues() {
    for precision in [Int.min, -1, 0, 17, Int.max] {
        #expect(throws: CodecError.self) {
            try ImageDescriptor.greyscale16(width: 1, height: 1, meaningfulBits: precision)
        }
    }
}

@Test func planarDescriptorsMapEveryComponentAndRejectOverlap() throws {
    let red = try PlaneDescriptor(width: 1, height: 1, components: [0], rowBytes: 2, byteCount: 6)
    let green = try PlaneDescriptor(width: 1, height: 1, components: [1], offset: 2, rowBytes: 2, byteCount: 6)
    let blue = try PlaneDescriptor(width: 1, height: 1, components: [2], offset: 4, rowBytes: 2, byteCount: 6)
    let valid = try ImageDescriptor(width: 1, height: 1, components: [.red, .green, .blue],
                                    colour: .rgb, planes: [red, green, blue])
    #expect(valid.requiredByteCount == 6)
    #expect(throws: CodecError.self) {
        try ImageDescriptor(width: 1, height: 1, components: [.red, .green, .blue],
                            colour: .rgb, planes: [red, green])
    }
    let overlapping = try PlaneDescriptor(width: 1, height: 1, components: [2], offset: 2,
                                           rowBytes: 2, byteCount: 6)
    #expect(throws: CodecError.self) {
        try ImageDescriptor(width: 1, height: 1, components: [.red, .green, .blue],
                            colour: .rgb, planes: [red, green, overlapping])
    }
}

@Test func nativeByteOrderIsResolvedAndColourMeaningValidated() throws {
    let plane = try PlaneDescriptor(width: 1, height: 1, rowBytes: 2, byteCount: 2)
    let descriptor = try ImageDescriptor(width: 1, height: 1, byteOrder: .native, planes: [plane])
    #expect(descriptor.byteOrder != .native)
    #expect(throws: CodecError.self) {
        try ImageDescriptor(width: 1, height: 1, components: [.red], colour: .greyscale, planes: [plane])
    }
    #expect(throws: CodecError.self) {
        try ImageDescriptor(width: 1, height: 1, alpha: .straight, planes: [plane])
    }
}
