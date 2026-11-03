#include "jpeg_bench.h"
#include <limits.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jpeglib.h>

struct bench_error {
    struct jpeg_error_mgr jpeg;
    jmp_buf jump;
    char text[JMSG_LENGTH_MAX];
};

/* Mutable state lives on the heap so no changed automatic variable is read
 * after longjmp. The state pointer itself is initialised before setjmp. */
struct bench_state {
    struct jpeg_decompress_struct jpeg;
    struct bench_error error;
    int created;
    void *pixels;
};

static void fail_jpeg(j_common_ptr jpeg) {
    struct bench_error *error = (struct bench_error *)jpeg->err;
    (*jpeg->err->format_message)(jpeg, error->text);
    longjmp(error->jump, 1);
}

static void jpeg_message(j_common_ptr jpeg, int level) {
    /* A corrupt/truncated comparator input must not silently receive a repaired
     * output. Suppress informational trace messages, promote warnings to error. */
    if (level < 0) fail_jpeg(jpeg);
}

static void fail_probe(struct bench_state *state, const char *text) {
    snprintf(state->error.text, sizeof(state->error.text), "%s", text);
    longjmp(state->error.jump, 1);
}

void jpeg_bench_free(jpeg_bench_image *image) {
    if (image) {
        free(image->pixels);
        memset(image, 0, sizeof(*image));
    }
}

int jpeg_bench_decode(const unsigned char *input, size_t input_size,
                      jpeg_bench_image *result, char *error, size_t error_capacity) {
    if (!result) return 1;
    memset(result, 0, sizeof(*result));
    if (error && error_capacity) error[0] = 0;
    if (!input || !input_size || input_size > ULONG_MAX) {
        if (error && error_capacity) snprintf(error, error_capacity, "Invalid compressed input");
        return 1;
    }
    struct bench_state *const state = calloc(1, sizeof(*state));
    if (!state) {
        if (error && error_capacity) snprintf(error, error_capacity, "Comparator state allocation failed");
        return 1;
    }
    state->jpeg.err = jpeg_std_error(&state->error.jpeg);
    state->error.jpeg.error_exit = fail_jpeg;
    state->error.jpeg.emit_message = jpeg_message;
    if (setjmp(state->error.jump)) {
        if (error && error_capacity) snprintf(error, error_capacity, "%s", state->error.text);
        if (state->created) jpeg_destroy_decompress(&state->jpeg);
        free(state->pixels);
        free(state);
        return 1;
    }
    /* Setting the cleanup flag before create is safe: the struct is zeroed and
     * jpeg_destroy_decompress accepts a NULL memory manager after failed create. */
    state->created = 1;
    jpeg_create_decompress(&state->jpeg);
    /* Keep the fixture-sized virtual arrays resident; no backing-store pressure
     * at the same explicit 8 GiB workspace envelope used by the Swift probe. */
    state->jpeg.mem->max_memory_to_use = 8L * 1024L * 1024L * 1024L;
    jpeg_mem_src(&state->jpeg, input, (unsigned long)input_size);
    if (jpeg_read_header(&state->jpeg, TRUE) != JPEG_HEADER_OK)
        fail_probe(state, "Incomplete JPEG header");
    if (state->jpeg.data_precision != 8 && state->jpeg.data_precision != 12 && state->jpeg.data_precision != 16)
        fail_probe(state, "Probe supports declared 8/12/16-bit fixture precisions only");
    if (state->jpeg.num_components == 1) state->jpeg.out_color_space = JCS_GRAYSCALE;
    else if (state->jpeg.num_components == 3) state->jpeg.out_color_space = JCS_RGB;
    else fail_probe(state, "Unsupported comparator colour components");
    /* Fixed full-resolution accurate integer IDCT, matching ordinary djpeg.
     * No quantisation, display scaling, reduced precision or fast-IDCT switch. */
    state->jpeg.dct_method = JDCT_ISLOW;
    state->jpeg.scale_num = 1;
    state->jpeg.scale_denom = 1;
    state->jpeg.quantize_colors = FALSE;
    state->jpeg.do_fancy_upsampling = TRUE;
    jpeg_calc_output_dimensions(&state->jpeg);
    size_t width = state->jpeg.output_width, height = state->jpeg.output_height;
    size_t components = state->jpeg.out_color_components;
    size_t bytes_per_sample = state->jpeg.data_precision <= 8 ? 1 : 2;
    /* Development corpus admission only: all requested fixtures are <=2048².
     * Checked arithmetic precedes every output allocation and row offset. */
    if (!width || !height || width > 8192 || height > 8192 ||
        (components != 1 && components != 3) || width > SIZE_MAX / components ||
        width * components > SIZE_MAX / bytes_per_sample)
        fail_probe(state, "Comparator dimensions exceed its fixture limits");
    size_t row_bytes = width * components * bytes_per_sample;
    if (height > SIZE_MAX / row_bytes || row_bytes * height > 512U * 1024U * 1024U)
        fail_probe(state, "Comparator output size overflow or limit");
    size_t byte_count = row_bytes * height;
    if (!jpeg_start_decompress(&state->jpeg)) fail_probe(state, "Suspended JPEG start");
    if (state->jpeg.output_components != (int)components)
        fail_probe(state, "Unexpected comparator output layout");
    state->pixels = calloc(1, byte_count);
    if (!state->pixels) fail_probe(state, "Full output allocation failed");
    while (state->jpeg.output_scanline < state->jpeg.output_height) {
        JDIMENSION remaining = state->jpeg.output_height - state->jpeg.output_scanline;
        JDIMENSION count = remaining < 16 ? remaining : 16;
        unsigned char *first = (unsigned char *)state->pixels + (size_t)state->jpeg.output_scanline * row_bytes;
        JDIMENSION read_count;
        if (state->jpeg.data_precision <= 8) {
            JSAMPROW rows[16];
            for (JDIMENSION row = 0; row < count; ++row) rows[row] = first + row * row_bytes;
            read_count = jpeg_read_scanlines(&state->jpeg, rows, count);
        } else if (state->jpeg.data_precision <= 12) {
            J12SAMPROW rows[16];
            for (JDIMENSION row = 0; row < count; ++row) rows[row] = (J12SAMPROW)(first + row * row_bytes);
            read_count = jpeg12_read_scanlines(&state->jpeg, rows, count);
        } else {
            J16SAMPROW rows[16];
            for (JDIMENSION row = 0; row < count; ++row) rows[row] = (J16SAMPROW)(first + row * row_bytes);
            read_count = jpeg16_read_scanlines(&state->jpeg, rows, count);
        }
        if (!read_count) fail_probe(state, "Suspended JPEG scanline read");
    }
    int precision = state->jpeg.data_precision;
    if (!jpeg_finish_decompress(&state->jpeg)) fail_probe(state, "Suspended JPEG finish");
    jpeg_destroy_decompress(&state->jpeg);
    result->pixels = state->pixels;
    result->byte_count = byte_count;
    result->row_bytes = row_bytes;
    result->width = (uint32_t)width;
    result->height = (uint32_t)height;
    result->components = (int)components;
    result->precision = precision;
    result->storage_bits = (int)bytes_per_sample * 8;
    free(state);
    return 0;
}
