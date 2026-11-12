// SPDX-License-Identifier: Apache-2.0
// Original scalar lossless row; independent of the qualified AC/DC leaf.
#include "EntropyReader.h"

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

SJLIACStatus sjli_lossless_left_u16_lookup_row(const void *raw_input, size_t input_count,
    SJLIACState *restrict state, const SJLIACHuffman *restrict table,
    const uint32_t *restrict lookup, size_t lookup_count, uint32_t seed,
    size_t count, void *output, size_t output_count,
    SJLILosslessRowResult *restrict result) {
    const uint8_t *input = (const uint8_t *)raw_input;
    if ((!input && input_count != 0) || !state || !table || !lookup || !output || !result ||
        lookup_count != 8192 || count == 0 || count > 65535 || seed > 65535 ||
        output_count < count * 2 || table->value_count > 256 ||
        state->byte_offset > input_count || state->available > 64) {
        return SJLI_AC_INVALID_ARGUMENT;
    }
    uint8_t *bytes = (uint8_t *)output;
    SJLIACState reader = *state;
    SJLILosslessRowResult decoded = {0};
    SJLIACStatus status = SJLI_AC_OK;
    uint32_t value = seed;
    for (size_t index = 0; index < count; ++index) {
        if (reader.available < 13 && !bulk(input, input_count, &reader)) {
            fill(input, input_count, &reader);
        }
        if (reader.available >= 13) {
            const unsigned prefix = (unsigned)((reader.accumulator >> (reader.available - 13)) & 8191);
            const uint32_t entry = lookup[prefix];
            if (entry != 0) {
                reader.available -= entry >> 16;
                value = (value + entry) & 65535;
                bytes[index * 2] = (uint8_t)value;
                bytes[index * 2 + 1] = (uint8_t)(value >> 8);
                if (index == 0) decoded.first = (uint16_t)value;
                while (index + 1 < count && reader.available >= 13) {
                    const unsigned next_prefix = (unsigned)((reader.accumulator >> (reader.available - 13)) & 8191);
                    const uint32_t next_entry = lookup[next_prefix];
                    if (next_entry == 0) break;
                    ++index;
                    reader.available -= next_entry >> 16;
                    value = (value + next_entry) & 65535;
                    bytes[index * 2] = (uint8_t)value;
                    bytes[index * 2 + 1] = (uint8_t)(value >> 8);
                }
                decoded.last = (uint16_t)value;
                decoded.written = (uint32_t)(index + 1);
                continue;
            }
        }
        int32_t difference;
        status = lossless_difference(input, input_count, &reader, table, &difference);
        if (status != SJLI_AC_OK) break;
        value = (value + (uint32_t)difference) & 65535;
        bytes[index * 2] = (uint8_t)value;
        bytes[index * 2 + 1] = (uint8_t)(value >> 8);
        if (index == 0) decoded.first = (uint16_t)value;
        decoded.last = (uint16_t)value;
        decoded.written = (uint32_t)(index + 1);
    }
    *result = decoded;
    *state = reader;
    return status;
}
