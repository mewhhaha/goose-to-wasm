#include <stdio.h>
#include <sys/mman.h>

int main(void) {
    volatile unsigned char *bytes = mmap(NULL, 65536, PROT_READ | PROT_WRITE,
                                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if ((void *)bytes == MAP_FAILED) return 2;
    bytes[0] = 42;
    int status = mprotect((void *)bytes, 65536, PROT_NONE);
    printf("mprotect=%d\n", status);
    fflush(stdout);
    if (status) return 3;
    printf("read after PROT_NONE=%u\n", (unsigned)bytes[0]);
    return 0;
}
