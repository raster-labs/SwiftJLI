// SPDX-License-Identifier: Apache-2.0
// Original scalar lossless row; independent of the qualified AC/DC leaf.
#include "EntropyReader.h"

static inline SJLIACStatus lossless_difference(const uint8_t *input, size_t count,
    SJLIACState *r, const SJLIACHuffman *table, int32_t *difference) {
    if (r->available < 8) fill(input, count, r);
    if (r->available >= 8) {
        const unsigned prefix = (unsigned)((r->accumulator >> (r->available - 8)) & 255);
        const unsigned length = table->lengths[prefix];
        if (length != 0) {
            const unsigned category = table->symbols[prefix];
            if (category == 0 || category == 16) {
                r->available -= length;
                *difference = category == 0 ? 0 : -32768;
                return SJLI_AC_OK;
            }
            if (category < 16 && r->available >= length + category) {
                r->available -= length + category;
                const uint32_t magnitude = (uint32_t)((r->accumulator >> r->available) &
                                                     ((UINT64_C(1) << category) - 1));
                *difference = (int32_t)magnitude;
                if (magnitude < (UINT32_C(1) << (category - 1)))
                    *difference -= (int32_t)((UINT32_C(1) << category) - 1);
                return SJLI_AC_OK;
            }
        }
    }
    uint8_t category;
    SJLIACStatus status = symbol(input, count, r, table, &category);
    if (status != SJLI_AC_OK) return status;
    if (category == 0 || category == 16) {
        *difference = category == 0 ? 0 : -32768;
        return SJLI_AC_OK;
    }
    // This lossless path reads only widths1...15 here. Mirror Swift's checked
    // readBits failure before attempting any oversized shift or refill.
    if (category > 16) {
        r->marker = category;
        return SJLI_AC_INVALID_WIDTH;
    }
    uint32_t magnitude;
    status = read_bits(input, count, r, category, &magnitude);
    if (status != SJLI_AC_OK) return status;
    *difference = (int32_t)magnitude;
    if (magnitude < (UINT32_C(1) << (category - 1)))
        *difference -= (int32_t)((UINT32_C(1) << category) - 1);
    return SJLI_AC_OK;
}

SJLIACStatus sjli_lossless_left_u16_row(const void *raw_input, size_t input_count,
    SJLIACState *restrict state, const SJLIACHuffman *restrict table, uint32_t seed,
    size_t count, void *output, size_t output_count,
    SJLILosslessRowResult *restrict result) {
    const uint8_t *input = (const uint8_t *)raw_input;
    if ((!input && input_count != 0) || !state || !table || !output || !result ||
        count == 0 || count > 65535 || seed > 65535 || output_count < count * 2 ||
        table->value_count > 256 || state->byte_offset > input_count ||
        state->available > 64) return SJLI_AC_INVALID_ARGUMENT;
    // Character accesses may write the representation of caller storage bound
    // to any sample type; no Swift UInt8 binding or alignment is assumed.
    uint8_t *bytes = (uint8_t *)output;
    SJLIACState reader = *state;
    SJLILosslessRowResult decoded = {0};
    SJLIACStatus status = SJLI_AC_OK;
    uint32_t value = seed;
    for (size_t index = 0; index < count; ++index) {
        int32_t difference;
        status = lossless_difference(input, input_count, &reader, table, &difference);
        if (status != SJLI_AC_OK) break;
        // Conversion of a negative signed value to uint32_t is defined modulo
        // 2^32; the final mask gives the exact Swift modulo-65536 result.
        value = (value + (uint32_t)difference) & 65535;
        bytes[index * 2] = (uint8_t)value;
        bytes[index * 2 + 1] = (uint8_t)(value >> 8);
        if (index == 0) decoded.first = (uint16_t)value;
        decoded.last = (uint16_t)value;
        decoded.written += 1;
    }
    *result = decoded;
    *state = reader;
    return status;
}
