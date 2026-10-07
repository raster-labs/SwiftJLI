// SPDX-License-Identifier: Apache-2.0
#include <stddef.h>
#include <stdint.h>
typedef struct {
    uint64_t allocations, frees, requested_bytes, live_bytes, peak_bytes;
    uint64_t live_blocks, peak_blocks, overflow;
} HPStats;
typedef struct { uint64_t size, count; } HPBucket;
void hp_begin(void);
HPStats hp_end(void);
size_t hp_bucket_count(void);
HPBucket hp_bucket(size_t index);
int hp_calibrate(void);
