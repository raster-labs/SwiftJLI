// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
enum QualifiedQuantization {
    static func fillZigzagOrder(_ order: UnsafeMutableBufferPointer<Int>) {
        precondition(order.count == 64)
        let definition: StaticString = """
        \u{00}\u{01}\u{08}\u{10}\u{09}\u{02}\u{03}\u{0a}\
        \u{11}\u{18}\u{20}\u{19}\u{12}\u{0b}\u{04}\u{05}\
        \u{0c}\u{13}\u{1a}\u{21}\u{28}\u{30}\u{29}\u{22}\
        \u{1b}\u{14}\u{0d}\u{06}\u{07}\u{0e}\u{15}\u{1c}\
        \u{23}\u{2a}\u{31}\u{38}\u{39}\u{32}\u{2b}\u{24}\
        \u{1d}\u{16}\u{0f}\u{17}\u{1e}\u{25}\u{2c}\u{33}\
        \u{3a}\u{3b}\u{34}\u{2d}\u{26}\u{1f}\u{27}\u{2e}\
        \u{35}\u{3c}\u{3d}\u{36}\u{2f}\u{37}\u{3e}\u{3f}
        """
        definition.withUTF8Buffer { bytes in
            precondition(bytes.count == 64)
            for index in 0..<64 { order[index] = Int(bytes[index]) }
        }
    }
    static func fillInverseZigzagOrder(_ order: UnsafeBufferPointer<Int>,
                                      into inverse: UnsafeMutableBufferPointer<Int>) {
        precondition(order.count == 64 && inverse.count == 64)
        for index in 0..<64 { inverse[order[index]] = index }
    }
}
