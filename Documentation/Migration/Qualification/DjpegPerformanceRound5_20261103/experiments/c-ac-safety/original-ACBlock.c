// SPDX-License-Identifier: Apache-2.0
// Original SwiftJLI implementation of the retained Swift AC reader semantics.
#include "SwiftJLIEntropyC.h"
#include <string.h>

static inline int bulk(const uint8_t *input, size_t count, SJLIACState *r) {
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

static inline void fill(const uint8_t *input, size_t count, SJLIACState *r) {
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

static inline SJLIACStatus read_bits(const uint8_t *input, size_t count,
                                    SJLIACState *r, unsigned width, uint32_t *value) {
    // All callers prove width <= 15. A zero category consumes no bits; avoid
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

static inline SJLIACStatus symbol(const uint8_t *input, size_t count,
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

SJLIACStatus sjli_ac_decode_block(const uint8_t *restrict input, size_t input_count,
    SJLIACState *restrict state, const SJLIACHuffman *restrict table,
    const uint32_t *restrict lookup, size_t lookup_count,
    int32_t *restrict output, size_t output_count) {
    if ((!input && input_count != 0) || !state || !table || !lookup || !output ||
        output_count != 64 || lookup_count != 8192 || table->value_count > 256 ||
        state->byte_offset > input_count || state->available > 64) return SJLI_AC_INVALID_ARGUMENT;
    SJLIACState reader = *state;
    memset(output, 0, 64 * sizeof(*output));
    SJLIACStatus status = SJLI_AC_OK;
    unsigned index = 1;
    while (index < 64) {
        if (reader.available < 13 && !bulk(input, input_count, &reader)) fill(input, input_count, &reader);
        if (reader.available >= 13) {
            const unsigned prefix = (unsigned)((reader.accumulator >> (reader.available - 13)) & 8191);
            const uint32_t entry = lookup[prefix];
            const unsigned advance = (entry >> 16) & 255;
            if (entry != 0 && advance <= 64 - index) {
                reader.available -= entry >> 24;
                if (advance == 0) break;
                index += advance;
                const uint32_t low = entry & 65535;
                output[index - 1] = low < 32768 ? (int32_t)low : (int32_t)low - 65536;
                continue;
            }
        }
        uint8_t value;
        status = symbol(input, input_count, &reader, table, &value);
        if (status != SJLI_AC_OK || value == 0) break;
        if (value == 0xf0) { index += 16; continue; }
        index += value >> 4;
        if (index >= 64) break;
        const unsigned category = value & 15;
        uint32_t magnitude;
        status = read_bits(input, input_count, &reader, category, &magnitude);
        if (status != SJLI_AC_OK) break;
        int32_t coefficient = (int32_t)magnitude;
        if (category != 0 && magnitude < (UINT32_C(1) << (category - 1)))
            coefficient -= (int32_t)((UINT32_C(1) << category) - 1);
        output[index++] = coefficient;
    }
    *state = reader;
    return status;
}
