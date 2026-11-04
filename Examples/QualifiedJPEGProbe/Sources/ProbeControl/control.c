// SPDX-License-Identifier: Apache-2.0
#include <stdlib.h>
#include "ProbeControl.h"
void *qjp_allocate(size_t count) { return malloc(count); }
void qjp_free(void *pointer) { free(pointer); }
