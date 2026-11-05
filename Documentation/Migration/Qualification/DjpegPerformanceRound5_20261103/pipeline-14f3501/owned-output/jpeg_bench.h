#ifndef SWIFTJLI_JPEG_BENCH_H
#define SWIFTJLI_JPEG_BENCH_H
#include <stddef.h>
#include <stdint.h>

/* Development-only comparator; not a SwiftJLI dependency or implementation. */
typedef struct {
    void *pixels;
    size_t byte_count;
    size_t row_bytes;
    uint32_t width;
    uint32_t height;
    int components;
    int precision;
    int storage_bits;
} jpeg_bench_image;

/* The compressed input is borrowed synchronously and never retained. A successful
 * result owns the complete zero-initialised output; the caller frees it below.
 * Every longjmp remains wholly within this C call. Failure leaves a zero result. */
int jpeg_bench_decode(const unsigned char *input, size_t input_size,
                      jpeg_bench_image *result, char *error, size_t error_capacity);
void jpeg_bench_free(jpeg_bench_image *image);
#endif
