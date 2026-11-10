// SPDX-License-Identifier: MIT
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
    SJLI_AC_INVALID_ARGUMENT,
    SJLI_AC_INVALID_WIDTH,
    SJLI_AC_DC_RANGE
} SJLIACStatus;

// Synchronous, allocation-free leaf. The caller retains every owner and borrow
// until return. Input, state, metadata, lookup and output must not overlap.
// Metadata comes from a validated Swift HuffmanTable: offsets 0...256, short
// lengths 0...8. Lookup is the existing 8192-entry Swift ACLookahead. No pointer
// is saved, captured, returned or given to a worker. Every entropy-error return
// publishes the consumed cursor and partial output. Invalid arguments write
// nothing. No caller-visible DC value is installed here.
SJLIACStatus sjli_ac_decode_block(const void *raw_input, size_t input_count,
    SJLIACState *state, const SJLIACHuffman *table,
    const uint32_t *lookup, size_t lookup_count,
    int32_t *output, size_t output_count);

// Same borrow/non-alias obligations as the AC entrypoint, including previous_dc.
// DC metadata is another scan-local value. On a DC error, output is untouched
// and previous_dc is unchanged. A valid reconstructed DC updates previous_dc
// before AC decoding; AC failure leaves its partial coefficients and zero DC
// slot. Only full success installs output[0]. For INVALID_WIDTH, state.marker
// carries the offending DC category; for MARKER it carries the marker byte.
// Precision is 8 or 12; restart scanning/cancellation remains with the caller.
SJLIACStatus sjli_dct_decode_block(const void *raw_input, size_t input_count,
    SJLIACState *state, const SJLIACHuffman *dc_table, const SJLIACHuffman *ac_table,
    const uint32_t *lookup, size_t lookup_count, int32_t *previous_dc,
    unsigned precision, int32_t *output, size_t output_count);
typedef struct {
    uint16_t first;
    uint16_t last;
    uint32_t written;
} SJLILosslessRowResult;

// Original synchronous left-predictor/Pt0 row leaf. There is no heap, I/O,
// callback or worker. The caller retains input and output owners until return;
// output is a raw byte borrow (unaligned is allowed). State, metadata and result
// must be disjoint from each other and from the input/output buffers. No
// restrict assumption is made about caller output versus compressed input.
// Metadata has the same validated invariants as the AC leaf above.
// count is 1...65535 and seed is a reconstructed value in 0...65535. The result
// and state are published on entropy failure, with only the complete sample
// prefix written. Categories >16 fail after their symbol, before any magnitude
// read (state.marker carries that width); category16 means -32768 with no
// extra bits. All arithmetic is modulo
// 65536 regardless of JPEG precision, matching the retained Swift reference.
// Invalid arguments leave state, result and output unchanged.
SJLIACStatus sjli_lossless_left_u16_row(const void *raw_input, size_t input_count,
    SJLIACState *state, const SJLIACHuffman *table, uint32_t seed,
    size_t count, void *output, size_t output_count,
    SJLILosslessRowResult *result);

// Optional scalar row for a canonical one-bit code0 carrying category1...7.
// Bounds/borrows/publication match the generic row. Width, sign threshold and
// mask are fixed once per row; leading1/short input uses the generic C row for
// one sample without consuming bits first. No extra lookup or allocation.
SJLIACStatus sjli_lossless_left_u16_code0_row(const void *raw_input, size_t input_count,
    SJLIACState *state, const SJLIACHuffman *table, uint32_t seed,
    size_t count, void *output, size_t output_count,
    SJLILosslessRowResult *result);
#endif
