// SPDX-License-Identifier: Apache-2.0
// Original shared reader bodies copied byte-for-byte from qualified ACBlock.c.
// Keep the AC/DC translation unit unchanged; these scoped row leaves retain
// the same bounded prefetch and error semantics without cross-file hot calls.
#ifndef SWIFTJLI_ROW_ENTROPY_READER_H
#define SWIFTJLI_ROW_ENTROPY_READER_H
#include "SwiftJLIEntropyC.h"
#include <string.h>

static inline __attribute__((always_inline)) int bulk(const uint8_t *input, size_t count, SJLIACState *r) {
    if (count - r->byte_offset < 8) return 0;
    uint64_t word;
    memcpy(&word, input + r->byte_offset, sizeof(word));
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    word = __builtin_bswap64(word);
#endif
    const uint64_t inverse = ~word;
    if (((inverse - UINT64_C(0x0101010101010101)) & ~inverse &
         UINT64_C(0x8080808080808080)) != 0) return 0;
    const unsigned bytes = (64 - r->available) / 8;
    if (r->available == 0) r->accumulator = word;
    else r->accumulator = (r->accumulator << (8 * bytes)) |
                          (word >> (64 - 8 * bytes));
    r->available += 8 * bytes;
    r->byte_offset += bytes;
    return 1;
}

static inline __attribute__((always_inline)) void fill(const uint8_t *input, size_t count, SJLIACState *r) {
    if (r->available < 8 && bulk(input, count, r)) return;
    while (r->available < 8) {
        if (r->byte_offset == count) return;
        const uint8_t byte = input[r->byte_offset];
        if (byte == 0xff) {
            if (count - r->byte_offset < 2 || input[r->byte_offset + 1] != 0) return;
            r->byte_offset += 2;
        } else r->byte_offset += 1;
        r->accumulator = (r->accumulator << 8) | byte;
        r->available += 8;
    }
}

// These hot helpers preserve the original call-free AC leaf. Release
// C size optimisation otherwise outlines the shared bodies after adding the
// DC+AC entrypoint, adding calls and state traffic inside the coefficient loop.
static inline __attribute__((always_inline)) SJLIACStatus read_bits(const uint8_t *input, size_t count,
                                    SJLIACState *r, unsigned width, uint32_t *value) {
    // All callers prove width <= 16. A zero category consumes no bits; avoid
    // shifting by 64 when the accumulator is full.
    if (width == 0) { *value = 0; return SJLI_AC_OK; }
    while (r->available < width) {
        if (bulk(input, count, r)) break;
        if (r->byte_offset == count) return SJLI_AC_END;
        const uint8_t byte = input[r->byte_offset++];
        if (byte == 0xff) {
            if (r->byte_offset == count) return SJLI_AC_END_AFTER_FF;
            const uint8_t next = input[r->byte_offset];
            if (next != 0) { r->marker = next; return SJLI_AC_MARKER; }
            r->byte_offset += 1;
        }
        r->accumulator = (r->accumulator << 8) | byte;
        r->available += 8;
    }
    r->available -= width;
    *value = (uint32_t)((r->accumulator >> r->available) & ((UINT64_C(1) << width) - 1));
    return SJLI_AC_OK;
}

static inline __attribute__((always_inline)) SJLIACStatus symbol(const uint8_t *input, size_t count,
                                 SJLIACState *r, const SJLIACHuffman *table,
                                 uint8_t *value) {
    if (r->available < 8) fill(input, count, r);
    if (r->available >= 8) {
        const unsigned prefix = (unsigned)((r->accumulator >> (r->available - 8)) & 255);
        const unsigned length = table->lengths[prefix];
        if (length != 0) {
            r->available -= length;
            *value = table->symbols[prefix];
            return SJLI_AC_OK;
        }
    }
    uint32_t code = 0;
    for (unsigned length = 1; length <= 16; ++length) {
        uint32_t bit;
        SJLIACStatus status = read_bits(input, count, r, 1, &bit);
        if (status != SJLI_AC_OK) return status;
        code = (code << 1) | bit;
        if (table->maximum[length] >= 0 && (int64_t)code <= table->maximum[length]) {
            const int64_t index = table->value_offsets[length] +
                                  (int64_t)code - table->minimum[length];
            if (index < 0 || (uint64_t)index >= table->value_count) return SJLI_AC_CODE_INDEX;
            *value = table->values[index];
            return SJLI_AC_OK;
        }
    }
    return SJLI_AC_INVALID_CODE;
}

#endif
