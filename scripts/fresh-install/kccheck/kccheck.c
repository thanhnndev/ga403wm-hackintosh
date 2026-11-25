// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// kccheck: check a kernel collection without python or otool (a fresh macOS has neither until the Command Line Tools
// are installed). Prototype for docs/FRESH-INSTALL.md section 4.4. Read-only.
//
//   kccheck KC KEXT...                        every kext's LC_UUID must be in KC
//   kccheck KC --probes FILE BINARY KEXT...   also: each "offset length" window of BINARY must occur in KC exactly once
//                                             (the format of /Library/StrixGraphicsFix/nmx-relink.probes, Step100c)
// KEXT is a .kext folder or a Mach-O file. Exit 0 = every check passed.
//
// Build: clang -O2 -Wall -Wextra -o kccheck kccheck.c
#include <fcntl.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <libkern/OSByteOrder.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

struct map { const unsigned char *p; size_t n; };

static int map_file(const char *path, struct map *m) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size == 0) { close(fd); return -1; }
    void *p = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (p == MAP_FAILED) return -1;
    m->p = p; m->n = (size_t)st.st_size;
    return 0;
}

// count occurrences of needle in hay (stops at 2: callers only need 0, 1 or "more than one")
static int count(const struct map *hay, const unsigned char *needle, size_t len) {
    int c = 0;
    const unsigned char *p = hay->p, *end = hay->p + hay->n;
    while (p < end && c < 2) {
        const unsigned char *q = memmem(p, (size_t)(end - p), needle, len);
        if (!q) break;
        c++;
        p = q + 1;
    }
    return c;
}

// LC_UUID of a thin x86_64 Mach-O, or of the x86_64 slice of a fat file
static int lc_uuid(const struct map *m, unsigned char out[16]) {
    const unsigned char *base = m->p;
    size_t n = m->n;
    if (n < sizeof(struct fat_header)) return -1;
    uint32_t magic = *(const uint32_t *)base;
    if (magic == FAT_CIGAM || magic == FAT_MAGIC) {
        const struct fat_header *fh = (const void *)base;
        uint32_t k = OSSwapBigToHostInt32(fh->nfat_arch);
        const struct fat_arch *fa = (const void *)(fh + 1);
        for (uint32_t i = 0; i < k && (const unsigned char *)(fa + i + 1) <= base + n; i++) {
            if ((cpu_type_t)OSSwapBigToHostInt32((uint32_t)fa[i].cputype) == CPU_TYPE_X86_64) {
                uint32_t off = OSSwapBigToHostInt32(fa[i].offset);
                if (off >= n) return -1;
                struct map s = { base + off, n - off };
                return lc_uuid(&s, out);
            }
        }
        return -1;
    }
    if (magic != MH_MAGIC_64 || n < sizeof(struct mach_header_64)) return -1;
    const struct mach_header_64 *h = (const void *)base;
    const unsigned char *lc = base + sizeof(*h), *end = lc + h->sizeofcmds;
    if (end > base + n) return -1;
    for (uint32_t i = 0; i < h->ncmds && lc + sizeof(struct load_command) <= end; i++) {
        const struct load_command *c = (const void *)lc;
        if (c->cmdsize < sizeof(*c) || lc + c->cmdsize > end) return -1;
        if (c->cmd == LC_UUID && c->cmdsize >= sizeof(struct uuid_command)) {
            memcpy(out, ((const struct uuid_command *)c)->uuid, 16);
            return 0;
        }
        lc += c->cmdsize;
    }
    return -1;
}

// a .kext folder -> Contents/MacOS/<folder name without .kext> (our kexts all use that executable name)
static void exe_path(const char *k, char *out, size_t n) {
    size_t l = strlen(k);
    while (l > 1 && k[l - 1] == '/') l--;
    if (l > 5 && strncmp(k + l - 5, ".kext", 5) == 0) {
        const char *s = k + l - 5;
        while (s > k && s[-1] != '/') s--;
        snprintf(out, n, "%.*s/Contents/MacOS/%.*s", (int)l, k, (int)(k + l - 5 - s), s);
    } else {
        snprintf(out, n, "%s", k);
    }
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: kccheck KC [--probes FILE BINARY] KEXT...\n");
        return 2;
    }
    struct map kc;
    if (map_file(argv[1], &kc) != 0) { printf("FAIL cannot read collection %s\n", argv[1]); return 1; }
    int bad = 0, i = 2;
    if (i + 2 < argc && strcmp(argv[i], "--probes") == 0) {
        const char *pf = argv[i + 1], *bin = argv[i + 2];
        i += 3;
        struct map b;
        FILE *f = fopen(pf, "r");
        if (!f || map_file(bin, &b) != 0) { printf("FAIL cannot read %s or %s\n", pf, bin); return 1; }
        char line[256];
        while (fgets(line, sizeof line, f)) {
            char *e;
            unsigned long off = strtoul(line, &e, 0), len = strtoul(e, NULL, 0);
            if (len == 0) continue;
            if (off + len > b.n) { printf("FAIL probe %#lx+%#lx is past the end of %s\n", off, len, bin); bad = 1; continue; }
            int c = count(&kc, b.p + off, len);
            printf("%s probe %#lx+%#lx found %s\n", c == 1 ? "ok  " : "FAIL", off, len, c == 0 ? "0x" : c == 1 ? "1x" : ">1x");
            if (c != 1) bad = 1;
        }
        fclose(f);
    }
    for (; i < argc; i++) {
        char exe[1024];
        exe_path(argv[i], exe, sizeof exe);
        struct map m;
        unsigned char u[16];
        if (map_file(exe, &m) != 0 || lc_uuid(&m, u) != 0) { printf("FAIL %s: no Mach-O / LC_UUID\n", exe); bad = 1; continue; }
        int c = count(&kc, u, 16);
        printf("%s %s uuid ", c ? "ok  " : "FAIL", exe);
        for (int j = 0; j < 16; j++) printf("%02X%s", u[j], (j == 3 || j == 5 || j == 7 || j == 9) ? "-" : "");
        printf(" %s\n", c ? "in collection" : "MISSING");
        if (!c) bad = 1;
        munmap((void *)m.p, m.n);
    }
    return bad;
}
