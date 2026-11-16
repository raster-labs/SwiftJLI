// SPDX-License-Identifier: MIT
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

static inline __attribute__((always_inline)) SJLIACStatus lossless_rgb_difference(
    const uint8_t *input, size_t count, SJLIACState *r,
    const SJLIACHuffman *table, int32_t *difference
) {
    if (r->available < 24 && !bulk(input, count, r)) {
        if (r->available < 8) fill(input, count, r);
    }
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

SJLIACStatus sjli_lossless_left_rgb_u8_row(const void *raw_input, size_t input_count,
    SJLIACState *restrict state,
    const SJLIACHuffman *table0, const SJLIACHuffman *table1, const SJLIACHuffman *table2,
    uint32_t seed_r, uint32_t seed_g, uint32_t seed_b,
    size_t count, void *output, size_t output_count,
    SJLILosslessRGBRowResult *restrict result) {
    const uint8_t *input = (const uint8_t *)raw_input;
    if ((!input && input_count != 0) || !state || !table0 || !table1 || !table2 ||
        !output || !result || count == 0 || count > 65535 ||
        seed_r > 65535 || seed_g > 65535 || seed_b > 65535 ||
        output_count < count * 3 ||
        table0->value_count > 256 || table1->value_count > 256 || table2->value_count > 256 ||
        state->byte_offset > input_count || state->available > 64) {
        return SJLI_AC_INVALID_ARGUMENT;
    }
    uint8_t *bytes = (uint8_t *)output;
    SJLIACState reader = *state;
    SJLILosslessRGBRowResult decoded = {0};
    SJLIACStatus status = SJLI_AC_OK;
    uint32_t vr = seed_r, vg = seed_g, vb = seed_b;
    for (size_t index = 0; index < count; ++index) {
        int32_t dr, dg, db;
        status = lossless_rgb_difference(input, input_count, &reader, table0, &dr);
        if (status != SJLI_AC_OK) break;
        status = lossless_rgb_difference(input, input_count, &reader, table1, &dg);
        if (status != SJLI_AC_OK) break;
        status = lossless_rgb_difference(input, input_count, &reader, table2, &db);
        if (status != SJLI_AC_OK) break;
        vr = (vr + (uint32_t)dr) & 65535;
        vg = (vg + (uint32_t)dg) & 65535;
        vb = (vb + (uint32_t)db) & 65535;
        bytes[index * 3]     = vr > 255 ? 255 : (uint8_t)vr;
        bytes[index * 3 + 1] = vg > 255 ? 255 : (uint8_t)vg;
        bytes[index * 3 + 2] = vb > 255 ? 255 : (uint8_t)vb;
        if (index == 0) {
            decoded.first_r = (uint16_t)vr;
            decoded.first_g = (uint16_t)vg;
            decoded.first_b = (uint16_t)vb;
        }
        decoded.written += 1;
    }
    *result = decoded;
    *state = reader;
    return status;
}
