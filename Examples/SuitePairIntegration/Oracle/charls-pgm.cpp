// SPDX-License-Identifier: Apache-2.0
// Development oracle only; link against independent CharLS, never a shipping codec.
#include <charls/charls.h>
#include <fstream>
#include <iterator>
#include <vector>
#include <stdexcept>
#include <iostream>
int main(int argc, char** argv) {
    try {
        if (argc != 3) throw std::runtime_error("usage: charls-pgm input.jls output.pgm");
        std::ifstream input(argv[1], std::ios::binary);
        if (!input) throw std::runtime_error("cannot open input");
        std::vector<unsigned char> encoded{std::istreambuf_iterator<char>(input), {}};
        charls::jpegls_decoder decoder(encoded, true);
        const auto info = decoder.frame_info();
        if (info.component_count != 1 || info.bits_per_sample < 8 || info.bits_per_sample > 16)
            throw std::runtime_error("oracle requires unsigned greyscale 8-16 bits");
        std::vector<unsigned char> pixels(decoder.destination_size());
        decoder.decode(pixels);
        std::ofstream output(argv[2], std::ios::binary);
        output << "P5\n" << info.width << ' ' << info.height << '\n' << ((1U << info.bits_per_sample) - 1) << '\n';
        // Oracle image is Linux little-endian; PGM requires big-endian UInt16.
        if (info.bits_per_sample > 8) {
            for (size_t p = 0; p < pixels.size(); p += 2) { output.put(pixels.at(p+1)); output.put(pixels[p]); }
        } else output.write(reinterpret_cast<const char*>(pixels.data()), pixels.size());
        if (!output) throw std::runtime_error("cannot write output");
    } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
