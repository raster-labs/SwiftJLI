// SPDX-License-Identifier: Apache-2.0
/* Original source-only sanitizer support. Codec logic is not duplicated here. */
#ifndef SJLI_SAFETY_SUPPORT_H
#define SJLI_SAFETY_SUPPORT_H
#include "SwiftJLIEntropyC.h"
#include <sanitizer/asan_interface.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
enum { TABLES=8, DC_MODELS=21, RANDOM_CASES=1048576, INPUT_MAX=512, LARGE_INPUT=524288, BIT_CAPACITY=2097152 };
typedef struct {
    SJLIACHuffman table;
    uint32_t lookup[8192];
    uint16_t codes[256];
    uint8_t widths[256];
} Model;
static Model models[TABLES], dc_models[DC_MODELS];
static uint64_t random_state, cases;
static uint64_t status_counts[16], available_counts[65], category_counts[256];
static uint64_t random_cases, boundary_cases, known_cases, alias_cases, guard_cases;
static const uint64_t canary=UINT64_C(0x91af6305dceb7248);
static uint8_t input_small[INPUT_MAX+64];
static uint32_t input_words[(INPUT_MAX+64)/4];
static uint8_t logical_bits[BIT_CAPACITY];
static uint32_t delivered_bits[LARGE_INPUT+1];
static size_t logical_count;
static inline void fail(const char *reason) {
 fprintf(stderr,"FAIL case=%" PRIu64 " prng=%016" PRIx64 " reason=%s\n",cases,random_state,reason); exit(1);
}
static inline void require(int condition,const char *reason) { if(!condition) fail(reason); }
static inline uint64_t random64(void) {
 uint64_t x=random_state; x^=x>>12; x^=x<<25; x^=x>>27; random_state=x;
 return x*UINT64_C(2685821657736338717);
}
static inline void build(Model *m, const unsigned counts[17], const uint8_t *symbols) {
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
static inline void make_models(void) {
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


/* Twenty-one canonical models: category1...7 has code0/length1; the
   remaining valid and invalid lossless categories use length6,9 or16.
   The canonical encoder leaves the all-one code unused independently of
   production table-building code. */
static inline void make_dc_models(void) {
 const uint8_t symbols[]={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,31,32,63,64,127,255};
 const unsigned widths[]={6,9,16};
 for(unsigned category=1;category<=7;++category)for(unsigned shape=0;shape<3;++shape){
  unsigned counts[17]={0};uint8_t ordered[sizeof(symbols)];size_t n=1;
  ordered[0]=(uint8_t)category;
  for(size_t i=0;i<sizeof(symbols);++i)if(symbols[i]!=category)ordered[n++]=symbols[i];
  require(n==sizeof(symbols),"code-zero model symbols");
  counts[1]=1;counts[widths[shape]]=(unsigned)sizeof(symbols)-1;
  build(&dc_models[(category-1)*3+shape],counts,ordered);
 }
}
static inline void record_status(SJLIACStatus status,unsigned available) {
 require((unsigned)status<16,"status outside harness counters"); ++cases; ++status_counts[(unsigned)status];
 if(available<=64) ++available_counts[available];
}
static inline void put(unsigned value,unsigned width) {
 require(width<=16 && logical_count+width<=BIT_CAPACITY,"encoder bit bounds");
 for(unsigned i=width;i>0;--i) logical_bits[logical_count++]=(uint8_t)((value>>(i-1))&1);
}
static inline void put_symbol(const Model *model,unsigned value) {
 require(value<256 && model->widths[value],"encoder missing symbol"); put(model->codes[value],model->widths[value]);
}
static inline void pad_bits(void) { for(unsigned i=0;i<4;++i) put(65535,16); }
static inline uint64_t bits_at(size_t start,unsigned width) {
 require(width<=64,"bit extraction width"); uint64_t value=0;
 for(unsigned i=0;i<width;++i) value=(value<<1)|(start+i<logical_count?logical_bits[start+i]:1);
 return value;
}
static inline void map_bytes(const uint8_t *bytes,size_t count) {
 require(count<=LARGE_INPUT,"map capacity"); uint32_t delivered=0; size_t i=0; delivered_bits[0]=0;
 while(i<count) {
  if(bytes[i]!=255) { delivered+=8; delivered_bits[++i]=delivered; }
  else if(i+1<count && bytes[i+1]==0) { delivered_bits[++i]=delivered; delivered+=8; delivered_bits[++i]=delivered; }
  else { while(i<count) delivered_bits[++i]=delivered; }
 }
}
static inline size_t pack(uint8_t *bytes,size_t capacity,unsigned available) {
 require(available<=64 && logical_count>=available,"initial encoded accumulator"); size_t count=0;
 for(size_t bit=available;bit<logical_count;bit+=8) {
  unsigned value=(unsigned)bits_at(bit,8); require(count+2<=capacity,"encoder byte capacity");
  bytes[count++]=(uint8_t)value; if(value==255) bytes[count++]=0;
 }
 map_bytes(bytes,count); return count;
}
static inline void poison_input(uint8_t *storage,size_t capacity,uint8_t *input,size_t count) {
 size_t start=(size_t)(input-storage); require(start+count<capacity,"input poison extent");
 __asan_poison_memory_region(storage,start);
 __asan_poison_memory_region(input+count,capacity-start-count);
 require(__asan_address_is_poisoned(input+count),"logical input tail was not poisoned");
 if(count) require(!__asan_address_is_poisoned(input+count-1),"last valid input byte was poisoned");
}
static inline void check_state(const SJLIACState *state,size_t start,size_t count) {
 require(state->byte_offset>=start && state->byte_offset<=count,"published byte offset bounds");
 require(state->available<=64,"published bit count bounds");
}
static inline void check_ledger(const SJLIACState *state,unsigned initial,size_t expected) {
 const uint64_t total=(uint64_t)initial+delivered_bits[state->byte_offset];
 require(total>=state->available,"negative logical consumption");
 require(total-state->available==expected,"logical symbol/magnitude consumption");
 uint64_t mask=state->available==64?UINT64_MAX:((UINT64_C(1)<<state->available)-1);
 require((state->accumulator&mask)==bits_at(expected,state->available),"buffered suffix differs from encoder ledger");
}
static inline void pattern(uint8_t *bytes,size_t count,unsigned kind) {
 const uint8_t markers[]={0xd0,0xd1,0xd7,0xd9,0xc0,0xff,1,0xfe};
 for(size_t i=0;i<count;++i) { uint8_t r=(uint8_t)random64();
  switch(kind%8) {
   case 0:bytes[i]=r;break; case 1:bytes[i]=r==255?254:r;break;
   case 2:bytes[i]=(i&1)?0:255;break;case 3:bytes[i]=(i&1)?markers[(i/2)%8]:255;break;
   case 4:bytes[i]=255;break;case 5:bytes[i]=0;break;case 6:bytes[i]=(i&1)?0x5a:0xa5;break;
   default:bytes[i]=(i%8==7)?255:r;break;
  }
 }
}
static inline int same_state(const SJLIACState *a,const SJLIACState *b) {
 return a->byte_offset==b->byte_offset && a->accumulator==b->accumulator && a->available==b->available && a->marker==b->marker;
}
static inline void print_counters(const char *kind,const char *seed,unsigned statuses) {
 printf("{\n  \"kind\": \"%s\",\n  \"seed\": \"%s\",\n",kind,seed);
 printf("  \"cases\": %" PRIu64 ",\n  \"randomCases\": %" PRIu64 ",\n  \"boundaryCases\": %" PRIu64 ",\n",cases,random_cases,boundary_cases);
 printf("  \"knownCases\": %" PRIu64 ",\n  \"aliasCases\": %" PRIu64 ",\n  \"invalidArgumentCases\": %" PRIu64 ",\n",known_cases,alias_cases,guard_cases);
 printf("  \"statusCounts\": ["); for(unsigned i=0;i<statuses;++i) printf("%s%" PRIu64,i?", ":"",status_counts[i]); puts("],");
 printf("  \"availableBitCounts\": ["); for(unsigned i=0;i<=64;++i) printf("%s%" PRIu64,i?", ":"",available_counts[i]); puts("],");
 printf("  \"categoryCounts\": ["); for(unsigned i=0;i<256;++i) printf("%s%" PRIu64,i?", ":"",category_counts[i]); puts("],");
 puts("  \"allChecksPassed\": true\n}");
}
#endif
