# Step86 ibprobe: runs inside amdgpu_coredump right after the "NullMoth ringdump hw rptr" printf (0x17a8c), i.e. on a GFX
# ring timeout. It reads the hung IB1 (CP_IB1_BASE) twice -- through the BO's kernel vmap (WC/UC, what the GPU sees in
# memory) and through each page's write-back physmap alias (what the CPU cache holds) -- parses both as PM4, counts the
# dwords where they differ and prints the dwords around the parse stop and around the CP's fetch position.
# It only reads: no flush, no kmap, no lock but the pasid xarray mutex.
# Step89: every line goes through pr(): snprintf into a stack buffer, then printf("%s\n") with NMXGPU's own "%s\n"
# (0x7001ed). logd resolves formats only from the kext's __cstring, so the Step86 lines that used formats from this
# cave read "<compose failure>". The head lines now also print pasid, vm, mapping and bo, so a zero limit says which
# lookup failed.
# Linked at 0x5aa5a0 (si_initialize_smc_cac_tables, SI dpm only, no external relocations inside).
# rbx = adev, r13 = job, rbp = amdgpu_coredump's frame. 0(%rsp) = IB1_BASE_LO, 8(%rsp) = IB1_BUFSZ (still pushed).
        .text
        .globl _start
_start:
        movl    (%rsp), %eax
        movl    8(%rsp), %ecx
        addq    $0x20, %rsp
        testq   %r13, %r13
        je      JE_TARGET
        pushq   %r12
        pushq   %r13
        pushq   %r14
        pushq   %r15
        subq    $0x40, %rsp
        # 0 va, 8 left, 0x10 cmd, 0x18 bo, 0x20 vm, 0x28 mapping, 0x30 mem_type, 0x38 pasid
        movl    %ecx, 8(%rsp)
        movl    -0x38(%rbp), %edx
        shlq    $32, %rdx
        orq     %rax, %rdx
        movabsq $0xffffffffffff, %rcx
        andq    %rcx, %rdx
        movq    %rdx, (%rsp)
        movq    0x55608(%rbx), %rax
        movl    $0x20c0, %esi
        addl    4(%rax), %esi
        movq    %rbx, %rdi
        xorl    %edx, %edx
        call    RREG
        movl    %eax, 0x10(%rsp)
        movq    $0, 0x18(%rsp)
        movq    $0, 0x28(%rsp)
        movq    $-1, 0x30(%rsp)
        movq    $0, 0x38(%rsp)
        xorl    %r12d, %r12d
        xorl    %r14d, %r14d
        xorl    %r15d, %r15d
        leaq    0xf1a8(%rbx), %rdi
        call    MTX_LOCK
        leaq    0xf180(%rbx), %rdi
        movl    0x1f4(%r13), %esi
        movl    %esi, 0x38(%rsp)
        call    XA_LOAD
        movq    %rax, 0x20(%rsp)
        leaq    0xf1a8(%rbx), %rdi
        call    MTX_UNLOCK
        xorl    %r13d, %r13d                    # r13 = limit (dwords) from here on
        movq    0x20(%rsp), %rdi
        testq   %rdi, %rdi
        je      .Lhead
        movq    (%rsp), %rsi
        shrq    $12, %rsi
        call    LOOKUP
        movq    %rax, 0x28(%rsp)
        testq   %rax, %rax
        je      .Lhead
        movq    (%rax), %rcx
        testq   %rcx, %rcx
        je      .Lhead
        movq    8(%rcx), %rcx
        testq   %rcx, %rcx
        je      .Lhead
        movq    %rcx, 0x18(%rsp)
        # r15 = byte offset of the IB in the bo = mapping->offset + va - mapping->start * 4096
        movq    0x30(%rax), %rdx
        shlq    $12, %rdx
        movq    (%rsp), %r15
        subq    %rdx, %r15
        addq    0x48(%rax), %r15
        # bytes left in the mapping: (last + 1) * 4096 - va
        movq    0x38(%rax), %rdx
        incq    %rdx
        shlq    $12, %rdx
        subq    (%rsp), %rdx
        # and in the bo: size - offset
        movq    0x148(%rcx), %rsi
        subq    %r15, %rsi
        jbe     .Lhead
        cmpq    %rsi, %rdx
        cmovaq  %rsi, %rdx
        shrq    $2, %rdx
        movl    0x10(%rsp), %esi
        cmpq    %rsi, %rdx
        cmovaq  %rsi, %rdx
        movq    %rdx, %r13
        movq    0x218(%rcx), %rax
        testq   %rax, %rax
        je      1f
        movl    0x10(%rax), %eax
        movq    %rax, 0x30(%rsp)
1:      movq    0x280(%rcx), %r12
        testq   %r12, %r12
        je      2f
        addq    %r15, %r12
2:      cmpq    $1, 0x30(%rsp)                  # pages are only the bo's backing store in TT
        jne     .Lhead
        movq    0x220(%rcx), %r14
        testq   %r14, %r14
        je      .Lhead
        movq    (%r14), %r14
.Lhead:
        leaq    F_HEAD(%rip), %rdi
        movq    (%rsp), %rsi
        movl    0x10(%rsp), %edx
        movl    8(%rsp), %ecx
        movl    0x38(%rsp), %r8d
        movq    0x20(%rsp), %r9
        call    pr
        leaq    F_BO(%rip), %rdi
        movq    0x28(%rsp), %rsi
        movq    0x18(%rsp), %rdx
        movq    0x30(%rsp), %rcx
        movq    %r15, %r8
        movq    %r13, %r9
        call    pr
        leaq    F_MAP(%rip), %rdi
        movq    %r12, %rsi
        movq    %r14, %rdx
        call    pr
        testq   %r13, %r13
        je      .Lout
        # parse both views
        leaq    rdA(%rip), %rsi
        call    parse
        movl    %eax, 0x20(%rsp)
        movl    %edx, 0x24(%rsp)
        leaq    rdB(%rip), %rsi
        call    parse
        movl    %eax, 0x28(%rsp)
        movl    %edx, 0x2c(%rsp)
        call    diff
        movl    %eax, 0x30(%rsp)
        movl    %edx, 0x34(%rsp)
        leaq    F_PARSE(%rip), %rdi
        movl    0x20(%rsp), %esi
        movl    0x24(%rsp), %edx
        movl    0x28(%rsp), %ecx
        movl    0x2c(%rsp), %r8d
        movl    0x30(%rsp), %r9d
        call    pr
        leaq    F_DIFF(%rip), %rdi
        movl    0x34(%rsp), %esi
        call    pr
        # around the A parse stop
        movl    0x20(%rsp), %edi
        call    dump2
        # around the first differing dword
        movl    0x34(%rsp), %edi
        cmpl    $-1, %edi
        je      3f
        call    dump2
        # around the CP fetch position: cmd - left
3:      movl    0x10(%rsp), %edi
        subl    8(%rsp), %edi
        call    dump2
.Lout:
        addq    $0x40, %rsp
        popq    %r15
        popq    %r14
        popq    %r13
        popq    %r12
        jmp     CONT

# pr(rdi = format, rsi, rdx, rcx, r8, r9): snprintf(buf, 256, format, ...) then printf("%s\n", buf).
# SNPRINTF is a "jmp _snprintf" tail call (0x8789e, amdgpu_reset_get_desc), PRINTF a "jmp _printf" (0xbc46e): both
# carry the external relocation, so calling them reaches the real function.
pr:
        pushq   %rbp
        movq    %rsp, %rbp
        subq    $0x110, %rsp
        movq    %r8, (%rsp)
        movq    %r9, 8(%rsp)
        movq    %rcx, %r9
        movq    %rdx, %r8
        movq    %rsi, %rcx
        movq    %rdi, %rdx
        leaq    0x10(%rsp), %rdi
        movl    $0x100, %esi
        xorl    %eax, %eax
        call    SNPRINTF
        leaq    FMT_S(%rip), %rdi
        leaq    0x10(%rsp), %rsi
        xorl    %eax, %eax
        call    PRINTF
        leave
        ret

# dump2(edi = index): 16 dwords from index - 8, view A then view B
dump2:
        pushq   %rbp
        movq    %rsp, %rbp
        subl    $8, %edi
        jae     1f
        xorl    %edi, %edi
1:      pushq   %rdi
        pushq   %rdi
        leaq    rdA(%rip), %rsi
        leaq    F_A(%rip), %rdx
        call    dump
        movl    (%rsp), %edi
        leaq    rdB(%rip), %rsi
        leaq    F_B(%rip), %rdx
        call    dump
        leave
        ret

# dump(edi = start, rsi = reader, rdx = format): 4 lines of 4 dwords
dump:
        pushq   %rbp
        movq    %rsp, %rbp
        subq    $0x30, %rsp
        movq    %rsi, -8(%rbp)
        movq    %rdx, -0x10(%rbp)
        movl    %edi, -0x14(%rbp)
        movl    $4, -0x18(%rbp)
1:      movl    -0x14(%rbp), %edi
        call    *-8(%rbp)
        movl    %eax, -0x28(%rbp)
        movl    -0x14(%rbp), %edi
        incl    %edi
        call    *-8(%rbp)
        movl    %eax, -0x24(%rbp)
        movl    -0x14(%rbp), %edi
        addl    $2, %edi
        call    *-8(%rbp)
        movl    %eax, -0x20(%rbp)
        movl    -0x14(%rbp), %edi
        addl    $3, %edi
        call    *-8(%rbp)
        movl    %eax, %r9d
        movq    -0x10(%rbp), %rdi
        movl    -0x14(%rbp), %esi
        movl    -0x28(%rbp), %edx
        movl    -0x24(%rbp), %ecx
        movl    -0x20(%rbp), %r8d
        call    pr
        addl    $4, -0x14(%rbp)
        decl    -0x18(%rbp)
        jnz     1b
        leave
        ret

# parse(rsi = reader) -> eax = index where PM4 parsing stopped, edx = header there (0 if it ran to the limit)
parse:
        pushq   %rbp
        movq    %rsp, %rbp
        movq    %rsi, %r9
        xorl    %r8d, %r8d
1:      cmpl    %r13d, %r8d
        jae     4f
        movl    %r8d, %edi
        call    *%r9
        movl    %eax, %r10d
        cmpl    $0xffff1000, %eax
        je      2f
        movl    %eax, %ecx
        shrl    $30, %ecx
        cmpl    $2, %ecx
        je      2f
        cmpl    $3, %ecx
        jne     3f
        shrl    $16, %eax
        andl    $0x3fff, %eax
        leal    2(%r8,%rax), %r8d
        jmp     1b
2:      incl    %r8d
        jmp     1b
3:      movl    %r8d, %eax
        movl    %r10d, %edx
        leave
        ret
4:      movl    %r8d, %eax
        xorl    %edx, %edx
        leave
        ret

# diff() -> eax = dwords where A != B, edx = first such index (-1 if none)
diff:
        pushq   %rbp
        movq    %rsp, %rbp
        xorl    %r8d, %r8d
        xorl    %r10d, %r10d
        movl    $-1, %r11d
1:      cmpl    %r13d, %r8d
        jae     3f
        movl    %r8d, %edi
        call    rdA
        movl    %eax, %r9d
        movl    %r8d, %edi
        call    rdB
        cmpl    %eax, %r9d
        je      2f
        incl    %r10d
        cmpl    $-1, %r11d
        jne     2f
        movl    %r8d, %r11d
2:      incl    %r8d
        jmp     1b
3:      movl    %r10d, %eax
        movl    %r11d, %edx
        leave
        ret

# readers: edi = dword index -> eax; clobber rax, rcx, rdx, rdi only
rdA:
        testq   %r12, %r12
        je      9f
        cmpl    %r13d, %edi
        jae     9f
        movl    %edi, %edi
        movl    (%r12,%rdi,4), %eax
        ret
9:      movl    $0xdeadbeef, %eax
        ret

rdB:
        testq   %r14, %r14
        je      9f
        cmpl    %r13d, %edi
        jae     9f
        movl    %edi, %edi
        leaq    (%r15,%rdi,4), %rax
        movq    %rax, %rcx
        shrq    $12, %rcx
        movq    (%r14,%rcx,8), %rcx
        testq   %rcx, %rcx
        je      9f
        movq    8(%rcx), %rcx
        testq   %rcx, %rcx
        je      9f
        andl    $0xfff, %eax
        movl    (%rcx,%rax), %eax
        ret
9:      movl    $0xdeadbeef, %eax
        ret

F_HEAD:  .asciz "NullMoth ibprobe: va=%llx cmd_bufsz=%x left=%x pasid=%x vm=%p"
F_BO:    .asciz "NullMoth ibprobe: mapping=%p bo=%p mem_type=%lld off=%llx limit=%llx"
F_MAP:   .asciz "NullMoth ibprobe: vmapA=%p pagesB=%p"
F_PARSE: .asciz "NullMoth ibprobe: pm4 A stops at %x (hdr %08x), B stops at %x (hdr %08x); A!=B in %x dwords"
F_DIFF:  .asciz "NullMoth ibprobe: first A!=B at %x"
F_A:     .asciz "NullMoth ibprobe A[%05x]: %08x %08x %08x %08x"
F_B:     .asciz "NullMoth ibprobe B[%05x]: %08x %08x %08x %08x"
