// SPDX-License-Identifier: Apache-2.0
// Separate positive control for the exact injected mmap counter.
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    void *library = dlopen(argv[1], RTLD_NOW);
    if (!library) return 3;
    void (*arm)(void) = dlsym(library, "qj_arm");
    void (*disarm)(void) = dlsym(library, "qj_disarm");
    uint64_t (*mappings)(void) = dlsym(library, "qj_mappings");
    if (!arm || !disarm || !mappings) return 4;
    arm();
    void *pointer = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    disarm();
    uint64_t count = mappings();
    if (pointer == MAP_FAILED) return 5;
    munmap(pointer, 4096);
    printf("{\"mappingControlCalls\":%llu}\n", (unsigned long long)count);
    return count > 0 ? 0 : 1;
}
