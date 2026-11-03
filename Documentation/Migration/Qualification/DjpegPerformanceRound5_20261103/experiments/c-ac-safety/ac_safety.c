/* Original diagnostic harness, not shipping codec code or a performance test. */
#include "SwiftJLIEntropyC.h"
#include <sanitizer/asan_interface.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { TABLES = 8, INPUT_MAX = 512, RANDOM_CASES = 1048576 };
typedef struct {
    SJLIACHuffman table;
    uint32_t lookup[8192];
    uint16_t codes[256];
    uint8_t widths[256];
} Model;
static Model models[TABLES];
static uint8_t input_storage[INPUT_MAX + 32];
static struct { uint64_t before[2]; int32_t values[64]; uint64_t after[2]; } output;
static uint64_t random_state = UINT64_C(0x8ef16ab47c205d93);
static uint64_t cases, random_cases, boundary_cases, known_cases, guard_cases;
static uint64_t status_counts[7], available_counts[65], table_counts[TABLES];
static uint64_t pattern_counts[8];
static const uint64_t canary = UINT64_C(0x91af6305dceb7248);

static void fail(const char *reason) {
    fprintf(stderr, "FAIL case=%" PRIu64 " random_state=%016" PRIx64 " reason=%s\n",
            cases, random_state, reason);
    exit(1);
}
static void require(int condition, const char *reason) { if (!condition) fail(reason); }
static uint64_t random64(void) {
    uint64_t x = random_state;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27; random_state = x;
    return x * UINT64_C(2685821657736338717);
}

/* Independent canonical encoder model. Expand each code/magnitude interval
   directly, instead of reproducing the production prefix-walking builder. */
static void build(Model *m, const unsigned counts[17], const uint8_t *symbols) {
    memset(m, 0, sizeof(*m));
    for (unsigned i = 0; i <= 16; ++i) m->table.minimum[i] = m->table.maximum[i] = -1;
    unsigned code = 0, value_index = 0;
    for (unsigned width = 1; width <= 16; ++width) {
        if (counts[width]) {
            m->table.minimum[width] = (int32_t)code;
            m->table.value_offsets[width] = value_index;
        }
        for (unsigned i = 0; i < counts[width]; ++i, ++code, ++value_index) {
            require(code < (1u << width) - 1u, "canonical code must leave all-ones unused");
            require(value_index < 256, "canonical value capacity");
            const unsigned symbol = symbols[value_index];
            require(m->widths[symbol] == 0, "duplicate symbol in model");
            m->codes[symbol] = (uint16_t)code; m->widths[symbol] = (uint8_t)width;
            m->table.values[value_index] = (uint8_t)symbol;
            if (width <= 8) {
                const unsigned start = code << (8 - width), extent = 1u << (8 - width);
                for (unsigned j = start; j < start + extent; ++j) {
                    m->table.lengths[j] = (uint8_t)width;
                    m->table.symbols[j] = (uint8_t)symbol;
                }
                const unsigned category = symbol & 15u, consumed = width + category;
                if (consumed <= 13) {
                    for (unsigned magnitude = 0; magnitude < (1u << category); ++magnitude) {
                        int32_t coefficient = (int32_t)magnitude;
                        if (category && magnitude < (1u << (category - 1)))
                            coefficient -= (int32_t)((1u << category) - 1u);
                        const unsigned advance = symbol ? (symbol >> 4) + 1 : 0;
                        const uint32_t entry = (consumed << 24) | (advance << 16) |
                                               (uint16_t)coefficient;
                        const unsigned start13 = ((code << category) | magnitude) << (13 - consumed);
                        const unsigned extent13 = 1u << (13 - consumed);
                        for (unsigned j = start13; j < start13 + extent13; ++j) m->lookup[j] = entry;
                    }
                }
            }
        }
        if (counts[width]) m->table.maximum[width] = (int32_t)code - 1;
        code <<= 1;
    }
    m->table.value_count = value_index;
}
static void make_models(void) {
    unsigned counts[17]; uint8_t values[256];
    memset(counts, 0, sizeof(counts)); counts[5] = 16;
    for (unsigned i = 0; i < 16; ++i) values[i] = (uint8_t)i;
    build(&models[0], counts, values);
    memset(counts, 0, sizeof(counts)); counts[8] = 128;
    for (unsigned i = 0; i < 128; ++i) values[i] = (uint8_t)i;
    build(&models[1], counts, values);
    memset(counts, 0, sizeof(counts)); counts[16] = 32;
    for (unsigned i = 0; i < 16; ++i) values[i] = (uint8_t)i;
    for (unsigned i = 0; i < 15; ++i) values[16+i] = (uint8_t)((i+1) << 4);
    values[31] = 0x11; build(&models[2], counts, values);
    memset(counts, 0, sizeof(counts));
    counts[1] = counts[2] = counts[3] = counts[4] = 1; counts[8] = 4; counts[16] = 16;
    const uint8_t initial[] = { 1, 0, 0xf0, 0x11, 2, 3, 4, 5 };
    memcpy(values, initial, sizeof(initial));
    for (unsigned i = 0; i < 16; ++i) values[8+i] = (uint8_t)(0xa0+i);
    build(&models[3], counts, values);
    memset(counts, 0, sizeof(counts));
    for (unsigned i = 1; i <= 16; ++i) { counts[i] = 1; values[i-1] = (uint8_t)(i-1); }
    build(&models[4], counts, values);
    memset(counts, 0, sizeof(counts)); counts[5] = 16;
    values[0] = 0; values[1] = 0xf0;
    for (unsigned i = 0; i < 14; ++i) values[i+2] = (uint8_t)((i << 4) | 1);
    build(&models[5], counts, values);
    memset(counts, 0, sizeof(counts)); counts[8] = 255;
    for (unsigned i = 0; i < 255; ++i) values[i] = (uint8_t)i;
    build(&models[6], counts, values);
    memset(counts, 0, sizeof(counts)); counts[1] = 1; counts[16] = 255;
    for (unsigned i = 0; i < 256; ++i) values[i] = (uint8_t)i;
    build(&models[7], counts, values);
}

static void initialise_output(void) {
    __asan_unpoison_memory_region(&output, sizeof(output));
    output.before[0] = output.before[1] = output.after[0] = output.after[1] = canary;
    for (unsigned i = 0; i < 64; ++i) output.values[i] = INT32_C(0x12345678);
    __asan_poison_memory_region(output.before, sizeof(output.before));
    __asan_poison_memory_region(output.after, sizeof(output.after));
}
static void check_canaries(void) {
    __asan_unpoison_memory_region(&output, sizeof(output));
    require(output.before[0] == canary && output.before[1] == canary &&
            output.after[0] == canary && output.after[1] == canary, "output canary");
}
static SJLIACStatus run_case(unsigned model, size_t count, size_t offset, unsigned available,
                             uint64_t accumulator, unsigned alignment, const int32_t *expected) {
    require(count <= INPUT_MAX && offset <= count && available <= 64 && alignment < 8, "harness bounds");
    uint8_t *input = input_storage + 8 + alignment;
    SJLIACState state = { offset, accumulator, available, 0xa9 };
    initialise_output();
    /* Poison the logical tail, including sub-eight-byte tails. The active
       input is a fixed buffer; no per-case allocation hides an over-read. */
    __asan_poison_memory_region(input + count, sizeof(input_storage) - (size_t)(input-input_storage) - count);
    const SJLIACStatus status = sjli_ac_decode_block(input, count, &state, &models[model].table,
                                                    models[model].lookup, 8192, output.values, 64);
    __asan_unpoison_memory_region(input_storage, sizeof(input_storage));
    check_canaries();
    require(status >= SJLI_AC_OK && status <= SJLI_AC_INVALID_ARGUMENT, "status range");
    require(status != SJLI_AC_INVALID_ARGUMENT && status != SJLI_AC_CODE_INDEX, "valid metadata/state rejected");
    require(state.byte_offset >= offset && state.byte_offset <= count, "published byte offset");
    require(state.available <= 64, "published bit count");
    require(output.values[0] == 0, "AC leaf changed zero DC slot");
    if (status == SJLI_AC_MARKER) require(state.marker != 0, "marker status requires nonzero marker");
    for (unsigned i = 0; i < 64; ++i) {
        require(output.values[i] >= -32767 && output.values[i] <= 32767, "coefficient category bound");
        if (expected) require(output.values[i] == expected[i], "independently encoded output");
    }
    if (expected) require(status == SJLI_AC_OK, "known valid block completion");
    ++cases; ++status_counts[status]; ++available_counts[available]; ++table_counts[model];
    return status;
}
static void pattern(unsigned kind, size_t count, unsigned alignment) {
    __asan_unpoison_memory_region(input_storage, sizeof(input_storage));
    memset(input_storage, 0x5a, sizeof(input_storage));
    uint8_t *bytes = input_storage + 8 + alignment;
    const uint8_t markers[] = { 0xd0,0xd1,0xd7,0xd9,0xc0,0xff,1,0xfe };
    for (size_t j = 0; j < count; ++j) {
        const uint8_t r = (uint8_t)random64();
        switch (kind) {
        case 0: bytes[j] = r; break;
        case 1: bytes[j] = r == 0xff ? 0xfe : r; break;
        case 2: bytes[j] = (j & 1) ? 0 : 0xff; break;
        case 3: bytes[j] = (j & 1) ? markers[(j/2)%8] : 0xff; break;
        case 4: bytes[j] = 0xff; break;
        case 5: bytes[j] = 0; break;
        case 6: bytes[j] = (j & 1) ? 0x5a : 0xa5; break;
        default: bytes[j] = r; if (j%8 == 7) bytes[j] = 0xff; break;
        }
    }
    ++pattern_counts[kind];
}
static void boundaries(void) {
    for (unsigned model = 0; model < TABLES; ++model)
        for (size_t count = 0; count <= 17; ++count)
            for (size_t offset = 0; offset <= count; ++offset)
                for (unsigned available = 0; available <= 64; ++available) {
                    const unsigned alignment = (unsigned)(cases % 8);
                    pattern((unsigned)((count+offset+available+model)%8), count, alignment);
                    run_case(model,count,offset,available,random64(),alignment,NULL); ++boundary_cases;
                }
}
static uint8_t logical_bits[4096];
static size_t logical_count;
static void put(unsigned value, unsigned width) {
    require(logical_count + width <= sizeof(logical_bits), "encoded bit capacity");
    for (unsigned i = width; i > 0; --i) logical_bits[logical_count++] = (uint8_t)((value >> (i-1)) & 1);
}
static void known_outputs(void) {
    const unsigned selected[] = {0,2,4,6};
    for (unsigned table_index = 0; table_index < 4; ++table_index) {
        const unsigned model = selected[table_index]; const Model *m = &models[model];
        for (unsigned category = 0; category <= 15; ++category)
            for (unsigned positive = 0; positive <= 1; ++positive) {
                logical_count = 0; int32_t expected[64] = {0};
                if (category) for (unsigned i = 1; i < 64; ++i) {
                    put(m->codes[category],m->widths[category]);
                    const unsigned magnitude = positive ? (1u << category)-1u : 0;
                    put(magnitude,category);
                    expected[i] = positive ? (int32_t)magnitude : -(int32_t)((1u << category)-1u);
                }
                put(m->codes[0],m->widths[0]); put(0xffff,16); put(0xffff,16); put(0xffff,16); put(0xffff,16);
                for (unsigned available = 0; available <= 64; ++available) {
                    const unsigned alignment = available%8;
                    __asan_unpoison_memory_region(input_storage,sizeof(input_storage));
                    memset(input_storage,0x5a,sizeof(input_storage));
                    uint8_t *bytes = input_storage+8+alignment;
                    uint64_t accumulator = 0;
                    for (unsigned i = 0; i < available; ++i) accumulator = (accumulator << 1) | logical_bits[i];
                    size_t count = 0;
                    for (size_t bit = available; bit < logical_count; bit += 8) {
                        unsigned byte = 0;
                        for (unsigned j = 0; j < 8; ++j) byte = (byte << 1) | (bit+j < logical_count ? logical_bits[bit+j] : 1);
                        require(count+2 <= INPUT_MAX,"stuffed encoded capacity"); bytes[count++] = (uint8_t)byte;
                        if (byte == 255) bytes[count++] = 0;
                    }
                    run_case(model,count,0,available,accumulator,alignment,expected); ++known_cases;
                }
            }
    }
}
static void invalid_arguments(void) {
    for (unsigned variant = 0; variant < 12; ++variant) {
        uint8_t byte = 0; SJLIACState state = {0,UINT64_C(0xabcdef),0,0xa9};
        SJLIACHuffman table = models[0].table;
        const uint8_t *input = &byte; size_t count = 1, lookup_count = 8192, output_count = 64;
        SJLIACState *state_pointer = &state; const SJLIACHuffman *table_pointer = &table;
        const uint32_t *lookup = models[0].lookup; int32_t *destination = output.values;
        switch (variant) {
        case 0: input = NULL; break;
        case 1: state_pointer = NULL; break;
        case 2: table_pointer = NULL; break;
        case 3: lookup = NULL; break;
        case 4: destination = NULL; break;
        case 5: output_count = 63; break;
        case 6: output_count = 65; break;
        case 7: lookup_count = 8191; break;
        case 8: table.value_count = 257; break;
        case 9: state.byte_offset = 2; break;
        case 10: state.available = 65; break;
        default: state.byte_offset = SIZE_MAX; break;
        }
        const SJLIACState original = state;
        initialise_output();
        const SJLIACStatus status = sjli_ac_decode_block(input,count,state_pointer,table_pointer,
                                                       lookup,lookup_count,destination,output_count);
        check_canaries(); require(status == SJLI_AC_INVALID_ARGUMENT,"invalid argument status");
        require(state.byte_offset == original.byte_offset && state.accumulator == original.accumulator &&
                state.available == original.available && state.marker == original.marker,"invalid argument changed state");
        for (unsigned i = 0; i < 64; ++i) require(output.values[i] == INT32_C(0x12345678),"invalid argument wrote output");
        ++cases; ++guard_cases; ++status_counts[status];
    }
}
static void print_array(const char *name, const uint64_t *values, unsigned count) {
    printf("  \"%s\": [",name);
    for (unsigned i = 0; i < count; ++i) printf("%s%" PRIu64,i?", ":"",values[i]);
    puts("],");
}
int main(void) {
    make_models(); invalid_arguments(); known_outputs(); boundaries();
    for (unsigned i = 0; i < RANDOM_CASES; ++i) {
        const unsigned model = i%TABLES, available = (i/TABLES)%65, alignment = (i/65)%8;
        const size_t count = (size_t)(random64()%(INPUT_MAX+1));
        const size_t offset = (size_t)(random64()%(count+1));
        const unsigned kind = (i/(TABLES*65))%8;
        pattern(kind,count,alignment);
        run_case(model,count,offset,available,random64(),alignment,NULL); ++random_cases;
    }
    require(status_counts[SJLI_AC_OK] && status_counts[SJLI_AC_END] &&
            status_counts[SJLI_AC_END_AFTER_FF] && status_counts[SJLI_AC_MARKER] &&
            status_counts[SJLI_AC_INVALID_CODE],"missing status coverage");
    for (unsigned i = 0; i < 65; ++i) require(available_counts[i] != 0,"missing reader width");
    puts("{");
    printf("  \"seed\": \"0x8ef16ab47c205d93\",\n  \"prng\": \"xorshift64star\",\n");
    printf("  \"cases\": %" PRIu64 ",\n  \"randomCases\": %" PRIu64 ",\n",cases,random_cases);
    printf("  \"boundaryCases\": %" PRIu64 ",\n  \"knownOutputCases\": %" PRIu64 ",\n  \"invalidArgumentCases\": %" PRIu64 ",\n",boundary_cases,known_cases,guard_cases);
    print_array("statusCounts",status_counts,7); print_array("availableBitCounts",available_counts,65);
    print_array("tableCounts",table_counts,TABLES); print_array("patternCounts",pattern_counts,8);
    printf("  \"inputMaxBytes\": %u,\n  \"tableCount\": %u,\n  \"allChecksPassed\": true\n}\n",INPUT_MAX,TABLES);
    return 0;
}
