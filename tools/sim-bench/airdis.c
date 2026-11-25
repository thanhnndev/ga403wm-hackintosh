// SPDX-License-Identifier: BSD-3-Clause-Clear
/* airdis in.air out.ll - bitcode to text with the plugin's own libLLVM (no llvm-dis on this Mac) */
#include <stdio.h>
typedef void *R;
R LLVMContextCreate(void);
int LLVMCreateMemoryBufferWithContentsOfFile(const char *, R *, char **);
int LLVMParseBitcodeInContext2(R, R, R *);
int LLVMPrintModuleToFile(R, const char *, char **);
int main(int c, char **v) {
    R buf, mod; char *err = 0;
    if (c < 3 || LLVMCreateMemoryBufferWithContentsOfFile(v[1], &buf, &err)) { fprintf(stderr, "read: %s\n", err); return 1; }
    if (LLVMParseBitcodeInContext2(LLVMContextCreate(), buf, &mod)) { fprintf(stderr, "parse failed\n"); return 1; }
    if (LLVMPrintModuleToFile(mod, v[2], &err)) { fprintf(stderr, "print: %s\n", err); return 1; }
    return 0;
}
