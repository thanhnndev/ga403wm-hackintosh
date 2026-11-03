# Step90: map write-combined / uncached GPU memory one physically contiguous range at a time.
#
# nmx_xnu_map_user (user mmap ioctl) and nmx_xnu_map_pages (kernel vmap) wrap the page list in ONE multi-range
# kIOMemoryTypePhysical64 descriptor. For more than one range IOKit backs it with a non-contiguous device pager, and
# xnu enters every page as a private vm_page: vm_page_insert_internal calls pmap_set_cache_attributes() on the
# PHYSICAL page with the object's mode, which rewrites the cache bits of every existing PTE of that page, and
# vm_page_remove() resets the page to write-back (again across all of its mappings) when any such object dies. So
# the last mapping made or torn down decides the cache mode of every mapping of the page; a vunmap or a second
# process's munmap turns a live WC mapping write-back. With no self-snoop the GPU then reads stale memory and the
# CPU reads stale cache lines (RADV descriptors read as 0, the keep witness never seen; docs/890M-TRACE.md Step90).
# Step89's TTM order 0 makes every multi-page BO multi-range, which is why it broke right after Step89.
#
# A single-range descriptor gets a contiguous device pager: no vm_page, no physical attribute change, and the fault
# path block-maps it with the object's WC/UC mode (pmap_map_block passes the mode in the PTE flags). So a WC/UC page
# list with more than one range is mapped as: a reservation of the whole size, then one single-range descriptor per
# range mapped over it with kIOMapOverwrite. Cached page lists and single ranges keep the old single mapping.
# The reservation never inserts a vm_page of the BO:
#  - user task: a read-only map of one NMXGPU text page repeated (faulted lazily, and only public bytes if touched);
#  - kernel: IOKit prefaults kernel maps, and a repeated page would grow that page's pv list by one per page while
#    every insert walks it (O(n^2) TLB shootdowns), so it is ONE contiguous read-only uncached range of the size,
#    starting at the first range: no vm_page, no attribute change, UC is never read speculatively, and it is replaced
#    by the overwrite maps before anything can use it.
# The handle of a split mapping is (struct split *) | 1:
#   0 nbytes (IOFree size), 8 reservation IOMemoryMap, 16 count, 24 IOMemoryMap *subs[count]
# Releasing the reservation first deallocates the whole range (overwrite maps never deallocate), then the subs go.
#
# External calls go through stubs: call sites in the replaced function bodies keep their relocation and get a "ret"
# after them; a stub call is made with rsp = 8 mod 16 so the callee sees a normal frame.
# Entries (fixed offsets from the base): +0 map_user, +8 unmap_user, +16 map_pages, +24 unmap.
        .text
        .globl _start
_start:
        jmp     map_user
        .balign 8
        jmp     unmap_user
        .balign 8
        jmp     map_pages
        .balign 8
        jmp     release_handle
        .balign 8

        .macro  SCALL t
        subq    $8, %rsp
        call    \t
        addq    $8, %rsp
        .endm

# void release_handle(void *h): an IOMemoryMap, or a split mapping (low bit set)
release_handle:
        testq   %rdi, %rdi
        je      .Lr_ret
        testb   $1, %dil
        jne     .Lr_split
        movq    (%rdi), %rax
        jmp     *0x28(%rax)                     # map->release()
.Lr_split:
        pushq   %rbp
        movq    %rsp, %rbp
        pushq   %rbx
        pushq   %r12
        pushq   %r13
        pushq   %r14
        leaq    -1(%rdi), %rbx
        movq    8(%rbx), %rdi
        testq   %rdi, %rdi
        je      1f
        movq    (%rdi), %rax
        call    *0x28(%rax)
1:      movq    16(%rbx), %r12
        xorl    %r13d, %r13d
2:      cmpq    %r12, %r13
        jae     3f
        movq    24(%rbx,%r13,8), %rdi
        testq   %rdi, %rdi
        je      4f
        movq    (%rdi), %rax
        call    *0x28(%rax)
4:      incq    %r13
        jmp     2b
3:      movq    (%rbx), %rsi
        movq    %rbx, %rdi
        SCALL   S_IOFREE
        popq    %r14
        popq    %r13
        popq    %r12
        popq    %rbx
        popq    %rbp
.Lr_ret:
        ret

# void *core(task, const uint64_t *pages, size_t npages, IOOptionBits opts, uint64_t fixed, uint64_t *addr)
# opts = cache bits | kIOMapReadOnly. Returns the handle (0 on failure) and the address in *addr.
# 0 task, 8 pages, 16 npages, 24 opts, 32 fixed, 40 addr ptr, 48/56 one IOAddressRange, 64 md, 72 offset
# rbx ranges, r12 range count, r13 split, r14 base, r15 index
core:
        pushq   %rbp
        movq    %rsp, %rbp
        pushq   %rbx
        pushq   %r12
        pushq   %r13
        pushq   %r14
        pushq   %r15
        subq    $0x58, %rsp
        movq    %rdi, 0(%rsp)
        movq    %rsi, 8(%rsp)
        movq    %rdx, 16(%rsp)
        movl    %ecx, 24(%rsp)
        movq    %r8, 32(%rsp)
        movq    %r9, 40(%rsp)
        movq    %rdx, %rdi
        shlq    $4, %rdi
        SCALL   S_IOMALLOC
        testq   %rax, %rax
        je      .Lc_fail
        movq    %rax, %rbx
        # coalesce physically adjacent pages into one range each
        xorl    %r12d, %r12d
        xorl    %ecx, %ecx
        movq    8(%rsp), %rsi
.Lco:   cmpq    16(%rsp), %rcx
        jae     .Lco_done
        movq    (%rsi,%rcx,8), %rdi
        testq   %r12, %r12
        je      .Lco_new
        movq    %r12, %rax
        shlq    $4, %rax
        movq    -16(%rbx,%rax), %rdx
        addq    -8(%rbx,%rax), %rdx
        cmpq    %rdi, %rdx
        jne     .Lco_new
        addq    $0x1000, -8(%rbx,%rax)
        jmp     .Lco_next
.Lco_new:
        movq    %r12, %rax
        shlq    $4, %rax
        movq    %rdi, (%rbx,%rax)
        movq    $0x1000, 8(%rbx,%rax)
        incq    %r12
.Lco_next:
        incq    %rcx
        jmp     .Lco
.Lco_done:
        cmpq    $1, %r12
        je      .Lsingle
        testl   $0x700, 24(%rsp)                # kIOMapCacheMask: default cache keeps one mapping
        jne     .Lsplit

.Lsingle:
        movq    %rbx, %rdi
        movl    %r12d, %esi
        movl    $0x23, %edx                     # kIODirectionInOut | kIOMemoryTypePhysical64
        xorl    %ecx, %ecx
        SCALL   S_WITHRANGES
        movq    %rax, %r13
        movq    %rbx, %rdi
        movq    16(%rsp), %rsi
        shlq    $4, %rsi
        SCALL   S_IOFREE
        testq   %r13, %r13
        je      .Lc_fail
        movq    %r13, %rdi
        movq    0(%rsp), %rsi
        movq    32(%rsp), %rdx
        movl    24(%rsp), %ecx
        movl    $1, %eax                        # kIOMapAnywhere
        movl    $0x20000000, %r8d               # kIOMapOverwrite
        testq   %rdx, %rdx
        cmovnel %r8d, %eax
        orl     %eax, %ecx
        xorl    %r8d, %r8d
        xorl    %r9d, %r9d
        SCALL   S_CREATEMAP
        movq    %rax, %r14
        movq    (%r13), %rax
        movq    %r13, %rdi
        call    *0x28(%rax)                     # md->release()
        testq   %r14, %r14
        je      .Lc_fail
        movq    (%r14), %rax
        movq    %r14, %rdi
        call    *0x118(%rax)                    # map->getAddress()
        movq    40(%rsp), %rcx
        movq    %rax, (%rcx)
        movq    %r14, %rax
        jmp     .Lc_out

.Lsplit:
        leaq    24(,%r12,8), %rdi
        SCALL   S_IOMALLOC
        testq   %rax, %rax
        je      .Lc_free_ranges
        movq    %rax, %r13
        leaq    24(,%r12,8), %rcx
        movq    %rcx, (%r13)
        movq    $0, 8(%r13)
        movq    %r12, 16(%r13)
        xorl    %ecx, %ecx
1:      cmpq    %r12, %rcx
        jae     2f
        movq    $0, 24(%r13,%rcx,8)
        incq    %rcx
        jmp     1b
2:      movq    32(%rsp), %r14
        testq   %r14, %r14
        jne     .Lsubs
        movq    GOT_KTASK(%rip), %rax
        movq    (%rax), %rax
        cmpq    %rax, 0(%rsp)
        jne     .Lres_user
        # kernel reservation: one contiguous read-only uncached range of the whole size
        movq    (%rbx), %rax
        movq    %rax, 48(%rsp)
        movq    16(%rsp), %rax
        shlq    $12, %rax
        movq    %rax, 56(%rsp)
        leaq    48(%rsp), %rdi
        movl    $1, %esi
        movl    $0x23, %edx
        xorl    %ecx, %ecx
        SCALL   S_WITHRANGES
        movq    %rax, 64(%rsp)
        movl    $0x1101, %ecx                   # kIOMapAnywhere | kIOMapReadOnly | kIOMapInhibitCache
        jmp     .Lres_map
.Lres_user:
        # user reservation: npages ranges of one read-only text page
        leaq    G_ANCHOR(%rip), %rdi
        call    KVA_TO_PHYS
        testq   %rax, %rax
        je      .Lsplit_fail
        andq    $-4096, %rax
        movq    %rax, 56(%rsp)
        movq    16(%rsp), %rdi
        shlq    $4, %rdi
        SCALL   S_IOMALLOC
        testq   %rax, %rax
        je      .Lsplit_fail
        movq    %rax, %r15
        xorl    %ecx, %ecx
        movq    56(%rsp), %rdx
1:      cmpq    16(%rsp), %rcx
        jae     2f
        movq    %rcx, %rax
        shlq    $4, %rax
        movq    %rdx, (%r15,%rax)
        movq    $0x1000, 8(%r15,%rax)
        incq    %rcx
        jmp     1b
2:      movq    %r15, %rdi
        movl    16(%rsp), %esi
        movl    $0x23, %edx
        xorl    %ecx, %ecx
        SCALL   S_WITHRANGES
        movq    %rax, 64(%rsp)
        movq    %r15, %rdi
        movq    16(%rsp), %rsi
        shlq    $4, %rsi
        SCALL   S_IOFREE
        movl    $0x1001, %ecx                   # kIOMapAnywhere | kIOMapReadOnly, default cache
.Lres_map:
        movq    64(%rsp), %rdi
        testq   %rdi, %rdi
        je      .Lsplit_fail
        movq    0(%rsp), %rsi
        xorl    %edx, %edx
        xorl    %r8d, %r8d
        xorl    %r9d, %r9d
        SCALL   S_CREATEMAP
        movq    %rax, 8(%r13)
        movq    64(%rsp), %rdi
        movq    (%rdi), %rax
        call    *0x28(%rax)
        movq    8(%r13), %rdi
        testq   %rdi, %rdi
        je      .Lsplit_fail
        movq    (%rdi), %rax
        call    *0x118(%rax)
        movq    %rax, %r14
.Lsubs:
        xorl    %r15d, %r15d
        movq    $0, 72(%rsp)                    # offset of range r15
.Lsub_loop:
        cmpq    %r12, %r15
        jae     .Lsub_done
        movq    %r15, %rdi
        shlq    $4, %rdi
        addq    %rbx, %rdi
        movl    $1, %esi
        movl    $0x23, %edx
        xorl    %ecx, %ecx
        SCALL   S_WITHRANGES
        testq   %rax, %rax
        je      .Lsplit_fail
        movq    %rax, 64(%rsp)
        movq    %rax, %rdi
        movq    0(%rsp), %rsi
        movq    %r14, %rdx
        addq    72(%rsp), %rdx
        movl    24(%rsp), %ecx
        orl     $0x20000000, %ecx               # kIOMapOverwrite
        xorl    %r8d, %r8d
        xorl    %r9d, %r9d
        SCALL   S_CREATEMAP
        movq    %rax, 24(%r13,%r15,8)
        movq    64(%rsp), %rdi
        movq    (%rdi), %rax
        call    *0x28(%rax)
        cmpq    $0, 24(%r13,%r15,8)
        je      .Lsplit_fail
        movq    %r15, %rax
        shlq    $4, %rax
        movq    8(%rbx,%rax), %rax
        addq    %rax, 72(%rsp)
        incq    %r15
        jmp     .Lsub_loop
.Lsub_done:
        movq    %rbx, %rdi
        movq    16(%rsp), %rsi
        shlq    $4, %rsi
        SCALL   S_IOFREE
        movq    40(%rsp), %rcx
        movq    %r14, (%rcx)
        leaq    1(%r13), %rax
        jmp     .Lc_out
.Lsplit_fail:
        cmpq    $0, 32(%rsp)                    # fixed: drop what was already entered over the caller's range
        je      1f
        movq    0(%rsp), %rdi
        SCALL   S_GETTASKMAP
        movq    %rax, %rdi
        movq    32(%rsp), %rsi
        movq    16(%rsp), %rdx
        shlq    $12, %rdx
        SCALL   S_VMDEALLOC
1:      leaq    1(%r13), %rdi
        call    release_handle
.Lc_free_ranges:
        movq    %rbx, %rdi
        movq    16(%rsp), %rsi
        shlq    $4, %rsi
        SCALL   S_IOFREE
.Lc_fail:
        xorl    %eax, %eax
.Lc_out:
        addq    $0x58, %rsp
        popq    %r15
        popq    %r14
        popq    %r13
        popq    %r12
        popq    %rbx
        popq    %rbp
        ret

# int nmx_xnu_map_user(pages, npages, cache, writable, fixed, uint64_t *uaddr, void **handle)
# 0 task, 8 addr, 16 handle; rbx UserMap {map, task, addr, size}, r12 pages, r13 npages, r14 fixed, r15 uaddr
map_user:
        pushq   %rbp
        movq    %rsp, %rbp
        pushq   %rbx
        pushq   %r12
        pushq   %r13
        pushq   %r14
        pushq   %r15
        subq    $0x38, %rsp
        movq    16(%rbp), %rax
        movq    $0, (%rax)
        movq    $0, (%r9)
        movl    $22, %eax                       # EINVAL
        testq   %rsi, %rsi
        je      .Lmu_out
        testl   $0xfff, %r8d
        jne     .Lmu_out
        movq    %rdi, %r12
        movq    %rsi, %r13
        movq    %r8, %r14
        movq    %r9, %r15
        xorl    %ebx, %ebx
        cmpl    $4, %edx
        ja      1f
        movl    %edx, %edx
        leaq    CACHETAB(%rip), %rax
        movl    (%rax,%rdx,4), %ebx
1:      testl   %ecx, %ecx
        jne     2f
        orl     $0x1000, %ebx                   # kIOMapReadOnly
2:      movl    %ebx, 24(%rsp)
        movl    $0x20, %edi
        SCALL   S_IOMALLOC
        testq   %rax, %rax
        je      .Lmu_nomem
        movq    %rax, %rbx
        SCALL   S_CURTASK
        movq    %rax, 0(%rsp)
        movq    %rax, %rdi
        movq    %r12, %rsi
        movq    %r13, %rdx
        movl    24(%rsp), %ecx
        movq    %r14, %r8
        leaq    8(%rsp), %r9
        call    core
        testq   %rax, %rax
        je      .Lmu_mapfail
        movq    %rax, (%rbx)
        movq    $0, 8(%rbx)
        movq    8(%rsp), %rcx
        movq    %rcx, 16(%rbx)
        movq    %r13, %rcx
        shlq    $12, %rcx
        movq    %rcx, 24(%rbx)
        testq   %r14, %r14
        je      3f
        movq    0(%rsp), %rdi
        movq    %rdi, 8(%rbx)
        SCALL   S_TASKREF
3:      movq    8(%rsp), %rcx
        movq    %rcx, (%r15)
        movq    16(%rbp), %rax
        movq    %rbx, (%rax)
        xorl    %eax, %eax
        jmp     .Lmu_out
.Lmu_mapfail:
        movq    %rbx, %rdi
        movl    $0x20, %esi
        SCALL   S_IOFREE
        movl    $12, %eax
        movl    $22, %ecx
        testq   %r14, %r14
        cmovnel %ecx, %eax
        jmp     .Lmu_out
.Lmu_nomem:
        movl    $12, %eax                       # ENOMEM
.Lmu_out:
        addq    $0x38, %rsp
        popq    %r15
        popq    %r14
        popq    %r13
        popq    %r12
        popq    %rbx
        popq    %rbp
        ret

# void nmx_xnu_unmap_user(void *handle)
unmap_user:
        testq   %rdi, %rdi
        je      9f
        pushq   %rbp
        movq    %rsp, %rbp
        pushq   %rbx
        pushq   %r12
        movq    %rdi, %rbx
        movq    8(%rbx), %rdi
        testq   %rdi, %rdi
        je      1f
        SCALL   S_GETTASKMAP                    # the range goes first, while the map still holds the pages
        movq    %rax, %rdi
        movq    16(%rbx), %rsi
        movq    24(%rbx), %rdx
        SCALL   S_VMDEALLOC
        movq    8(%rbx), %rdi
        SCALL   S_TASKDEALLOC
1:      movq    (%rbx), %rdi
        call    release_handle
        movq    %rbx, %rdi
        movl    $0x20, %esi
        SCALL   S_IOFREE
        popq    %r12
        popq    %rbx
        popq    %rbp
9:      ret

# void *nmx_xnu_map_pages(const uint64_t *pages, size_t npages, int cache, void **handle)
map_pages:
        pushq   %rbp
        movq    %rsp, %rbp
        pushq   %rbx
        pushq   %r12
        subq    $0x10, %rsp
        movq    $0, (%rcx)
        xorl    %eax, %eax
        testq   %rsi, %rsi
        je      .Lmp_out
        movq    %rcx, %rbx
        xorl    %ecx, %ecx
        cmpl    $4, %edx
        ja      1f
        movl    %edx, %edx
        leaq    CACHETAB(%rip), %rax
        movl    (%rax,%rdx,4), %ecx
1:      movq    %rsi, %rdx
        movq    %rdi, %rsi
        movq    GOT_KTASK(%rip), %rax
        movq    (%rax), %rdi
        xorl    %r8d, %r8d
        movq    %rsp, %r9
        call    core
        testq   %rax, %rax
        je      .Lmp_out
        movq    %rax, (%rbx)
        movq    0(%rsp), %rax
.Lmp_out:
        addq    $0x10, %rsp
        popq    %r12
        popq    %rbx
        popq    %rbp
        ret

G_ANCHOR:
        .ascii  "NullMoth wcsplit"
