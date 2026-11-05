// SPDX-License-Identifier: Apache-2.0
// Original SwiftJLI one-bit category row; separate translation unit preserves
// the generic row's own inline context for long-magnitude tables.
#include "EntropyReader.h"

SJLIACStatus sjli_lossless_left_u16_code0_row(const void *raw_input, size_t input_count,
    SJLIACState *restrict state, const SJLIACHuffman *restrict table, uint32_t seed,
    size_t count, void *output, size_t output_count,
    SJLILosslessRowResult *restrict result) {
    const uint8_t *input = (const uint8_t *)raw_input;
    if ((!input && input_count != 0) || !state || !table || !output || !result ||
        count == 0 || count > 65535 || seed > 65535 || output_count < count * 2 ||
        table->value_count > 256 || state->byte_offset > input_count ||
        state->available > 64 || table->lengths[0] != 1 ||
        table->symbols[0] < 1 || table->symbols[0] > 7) return SJLI_AC_INVALID_ARGUMENT;
    // All shifts are bounded before evaluation. The first canonical one-bit
    // code is zero; every remaining code begins with one and keeps fallback.
    const unsigned category = table->symbols[0];
    const unsigned consumed = category + 1;
    const uint32_t magnitude_mask = (UINT32_C(1) << category) - 1;
    const uint32_t sign_threshold = UINT32_C(1) << (category - 1);
    uint8_t *bytes = (uint8_t *)output;
    SJLIACState reader = *state;
    SJLILosslessRowResult decoded = {0};
    SJLIACStatus status = SJLI_AC_OK;
    uint32_t value = seed;
    for (size_t index = 0; index < count; ++index) {
        if (reader.available < 8) fill(input, input_count, &reader);
        if (reader.available >= 8 && ((reader.accumulator >> (reader.available - 1)) & 1) == 0) {
            reader.available -= consumed;
            const uint32_t magnitude = (uint32_t)(reader.accumulator >> reader.available) & magnitude_mask;
            // Unsigned subtraction is defined modulo2^32; the final mask is
            // exactly the retained signed difference plus modulo65536 predictor.
            value = (value + magnitude - (magnitude < sign_threshold ? magnitude_mask : 0)) & 65535;
            bytes[index * 2] = (uint8_t)value;
            bytes[index * 2 + 1] = (uint8_t)(value >> 8);
        } else {
            SJLILosslessRowResult single;
            status = sjli_lossless_left_u16_row(input, input_count, &reader, table,
                value, 1, bytes + index * 2, 2, &single);
            if (status != SJLI_AC_OK) break;
            value = single.last;
        }
        if (index == 0) decoded.first = (uint16_t)value;
        decoded.last = (uint16_t)value;
        decoded.written += 1;
    }
    *result = decoded;
    *state = reader;
    return status;
}
