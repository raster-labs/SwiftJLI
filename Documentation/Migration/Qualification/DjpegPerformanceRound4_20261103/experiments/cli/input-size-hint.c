// Diagnostic only: emulate a file that changes after its regular-file size hint.
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
static void apply_hint(const char *path, struct stat *info) {
    const char *target = getenv("SWIFTJLI_SIZE_HINT_PATH");
    const char *hint = getenv("SWIFTJLI_SIZE_HINT_BYTES");
    if (target && hint && strcmp(target, path) == 0) info->st_size = strtoll(hint, 0, 10);
}
static int hint_stat(const char *path, struct stat *info) {
    int result = stat(path, info);
    if (result == 0) apply_hint(path, info);
    return result;
}
static int hint_fstat(int fd, struct stat *info) {
    int result = fstat(fd, info);
    char path[PATH_MAX];
    if (result == 0 && fcntl(fd, F_GETPATH, path) == 0) apply_hint(path, info);
    return result;
}
#define INTERPOSE(replacement, original) \
__attribute__((used)) static struct { const void *new_function; const void *original_function; } \
interpose_##original __attribute__((section("__DATA,__interpose"))) = { (const void *)&replacement, (const void *)&original };
INTERPOSE(hint_stat, stat)
INTERPOSE(hint_fstat, fstat)
