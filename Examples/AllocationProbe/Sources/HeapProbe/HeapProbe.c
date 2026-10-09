// SPDX-License-Identifier: Apache-2.0
// Test-only glibc interposition. This is never linked into the shipping library.
#include "HeapProbe.h"
#include <features.h>
#ifndef __GLIBC__
#error AllocationProbe requires Linux with glibc
#endif
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdatomic.h>

extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void __libc_free(void *);
extern void *__libc_memalign(size_t, size_t);

#define CAPACITY 262144u
#define BUCKETS 4096u
typedef struct { void *pointer; size_t size; unsigned char state; } Slot;
static Slot slots[CAPACITY];
static HPBucket buckets[BUCKETS];
static size_t bucket_count;
static HPStats stats;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static _Atomic int enabled;

static size_t hash(void *p) { return (((uintptr_t)p >> 4) * 11400714819323198485ull) & (CAPACITY - 1); }
static void add(void *p, size_t size) {
    if (!p) return;
    size_t first = CAPACITY, i = hash(p);
    for (size_t n = 0; n < CAPACITY; ++n, i = (i + 1) & (CAPACITY - 1)) {
        if (slots[i].state == 2 && first == CAPACITY) first = i;
        if (slots[i].state == 0) { if (first == CAPACITY) first = i; break; }
    }
    if (first == CAPACITY) { ++stats.overflow; return; }
    slots[first] = (Slot){ p, size, 1 };
    ++stats.allocations; ++stats.live_blocks;
    stats.requested_bytes += size; stats.live_bytes += size;
    if (stats.live_bytes > stats.peak_bytes) stats.peak_bytes = stats.live_bytes;
    if (stats.live_blocks > stats.peak_blocks) stats.peak_blocks = stats.live_blocks;
    for (i = 0; i < bucket_count; ++i) if (buckets[i].size == size) { ++buckets[i].count; return; }
    if (bucket_count == BUCKETS) { ++stats.overflow; return; }
    buckets[bucket_count++] = (HPBucket){ size, 1 };
}
static void remove_pointer(void *p) {
    if (!p) return;
    size_t i = hash(p);
    for (size_t n = 0; n < CAPACITY; ++n, i = (i + 1) & (CAPACITY - 1)) {
        if (slots[i].state == 0) return;
        if (slots[i].state == 1 && slots[i].pointer == p) {
            stats.live_bytes -= slots[i].size; --stats.live_blocks; ++stats.frees;
            slots[i].state = 2; return;
        }
    }
}
static void record(void *p, size_t size) {
    if (!atomic_load(&enabled)) return;
    pthread_mutex_lock(&lock);
    if (atomic_load(&enabled)) add(p, size);
    pthread_mutex_unlock(&lock);
}
void *malloc(size_t n) { void *p = __libc_malloc(n); record(p, n); return p; }
void *calloc(size_t n, size_t s) {
    void *p = __libc_calloc(n, s); if (p) record(p, n * s); return p;
}
void free(void *p) {
    int saved_errno = errno;
    if (atomic_load(&enabled)) {
        pthread_mutex_lock(&lock);
        if (atomic_load(&enabled)) remove_pointer(p);
        pthread_mutex_unlock(&lock);
    }
    __libc_free(p); errno = saved_errno;
}
void *realloc(void *old, size_t n) {
    // Serialize with free/alloc accounting: the allocator may reuse old's address.
    if (!atomic_load(&enabled)) return __libc_realloc(old, n);
    pthread_mutex_lock(&lock);
    void *p = __libc_realloc(old, n);
    if (atomic_load(&enabled) && (p || n == 0)) {
        remove_pointer(old); add(p, n);
    }
    pthread_mutex_unlock(&lock); return p;
}
void *memalign(size_t a, size_t n) { void *p = __libc_memalign(a, n); record(p, n); return p; }
void *aligned_alloc(size_t a, size_t n) { return memalign(a, n); }
int posix_memalign(void **out, size_t a, size_t n) {
    if (a < sizeof(void *) || (a & (a - 1)) || a % sizeof(void *)) return EINVAL;
    int saved_errno = errno;
    void *p = __libc_memalign(a, n);
    errno = saved_errno;
    if (!p) return ENOMEM;
    *out = p; record(p, n); return 0;
}
void hp_begin(void) {
    pthread_mutex_lock(&lock); atomic_store(&enabled, 0);
    memset(slots, 0, sizeof(slots)); memset(buckets, 0, sizeof(buckets));
    memset(&stats, 0, sizeof(stats)); bucket_count = 0;
    atomic_store(&enabled, 1); pthread_mutex_unlock(&lock);
}
HPStats hp_end(void) {
    pthread_mutex_lock(&lock); atomic_store(&enabled, 0);
    HPStats value = stats; pthread_mutex_unlock(&lock); return value;
}
size_t hp_bucket_count(void) { return bucket_count; }
HPBucket hp_bucket(size_t i) { return i < bucket_count ? buckets[i] : (HPBucket){0, 0}; }
int hp_calibrate(void) {
    hp_begin();
    void *p = malloc(1000), *q = calloc(20, 100), *r = NULL;
    int result = posix_memalign(&r, 64, 3000);
    p = realloc(p, 4000);
    free(p); free(q); free(r);
    HPStats s = hp_end();
    return result == 0 && s.allocations == 4 && s.frees == 4 &&
        s.requested_bytes == 10000 && s.peak_bytes == 9000 &&
        s.live_bytes == 0 && s.live_blocks == 0 && s.overflow == 0;
}
