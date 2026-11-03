// SPDX-License-Identifier: Apache-2.0
// Original SwiftJLI kernel; no external codec source or runtime dependency.
#ifndef SWIFTJLI_ENTROPY_C_H
#define SWIFTJLI_ENTROPY_C_H
#include <stddef.h>
#include <stdint.h>

typedef struct {
    int32_t minimum[17];
    int32_t maximum[17];
    int64_t value_offsets[17];
    uint8_t values[256];
    uint8_t lengths[256];
    uint8_t symbols[256];
    uint32_t value_count;
} SJLIACHuffman;

typedef struct {
    size_t byte_offset;
    uint64_t accumulator;
    uint32_t available;
    uint8_t marker;
} SJLIACState;

typedef enum {
    SJLI_AC_OK = 0,
    SJLI_AC_END,
    SJLI_AC_END_AFTER_FF,
    SJLI_AC_MARKER,
    SJLI_AC_CODE_INDEX,
    SJLI_AC_INVALID_CODE,
    SJLI_AC_INVALID_ARGUMENT
} SJLIACStatus;

// Synchronous, allocation-free leaf. The caller retains every owner and borrow
// until return. Input, state, metadata, lookup and output must not overlap.
// Metadata comes from a validated Swift HuffmanTable: offsets 0...256, short
// lengths 0...8. Lookup is the existing 8192-entry Swift ACLookahead. No pointer
// is saved, captured, returned or given to a worker. Every entropy-error return
// publishes the consumed cursor and partial output. Invalid arguments write
// nothing. No caller-visible DC value is installed here.
SJLIACStatus sjli_ac_decode_block(const uint8_t *input, size_t input_count,
    SJLIACState *state, const SJLIACHuffman *table,
    const uint32_t *lookup, size_t lookup_count,
    int32_t *output, size_t output_count);
#endif
