// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step97b: the CS -EPERM crash loop (2026-11-03 23:45, "NMX cs-trace: p1_bo_handles -> -1", then RADV device lost in
// four WindowServers in a row). amdgpu_bo_list_create refuses a userptr BO whose saved task's mm is not current->mm.
// In xkpi one mm_struct is shared per process through the process record (p_lkpi_mm, proc+0x28), but:
//   - linux_mm_dtor clears p_lkpi_mm only if the freeing thread belongs to that process; the last reference to a
//     process's mm is often dropped by a kernel worker (TTM delayed delete of a userptr BO), which leaves p_lkpi_mm
//     pointing at freed memory that the next mm allocation (any process) can reuse;
//   - process records are keyed by the xnu proc_t pointer and never dropped, so a new process that gets a recycled
//     proc_t inherits the old record (and its p_lkpi_mm).
// Fixes here (the source fix belongs in the fork's xkpi):
//   1. linux_mm_dtor no longer frees the mm (its tail call to uma_zfree_arg becomes ret): p_lkpi_mm can then only
//      point at a live mm or a dead one with mm_users 0, which find_other_mm refuses. ~100 bytes leak per mm.
//   2. The CS check logs a mismatch instead of failing. The pages of a userptr BO are pinned on the creating task when
//      the BO is made (Step92 model); the CS does not use the mm. Handles are per DRM file, so per process.
typedef unsigned long u64; typedef unsigned int u32;
#pragma GCC visibility push(hidden)
extern int SNPRINTF(char *buf, u64 n, const char *fmt, ...);
extern int PRINTF(const char *fmt, ...);
extern const char FMT_S[];
extern u32 BUDGET;                       // ci_init_smc_table.__ratelimited.13 (CI dpm only, never runs on Strix)
extern char *LKPI_CURRENT(void);         // __lkpi_current: task_struct, mm at +8
extern char *NMX_CURTHREAD(void);        // nmx_curthread: struct thread, td_proc at +8
#pragma GCC visibility pop

// Called in place of __lkpi_current at the check (0xeb04); usermm comes in rdi (the glue moves r14). The patched site
// no longer compares or branches to the -EPERM path: it continues at 0xeb13 with rax = the task, as before.
char *mm_check(char *usermm)
{
    char *t = LKPI_CURRENT();
    char *cur = *(char **)(t + 8);
    if (cur == usermm)
        return t;
    if (BUDGET < 64) {
        BUDGET++;
        char *td = NMX_CURTHREAD();
        char *p = td ? *(char **)(td + 8) : 0;
        char b[200];
        SNPRINTF(b, sizeof b, "NMX mmfix: CS userptr BO mm %llx != current mm %llx (pid %d %s, p_lkpi_mm %llx) - allowed",
                 (u64)usermm, (u64)cur, p ? *(int *)p : -1, p ? p + 4 : "?", p ? *(u64 *)(p + 0x28) : 0);
        PRINTF(FMT_S, b);
    }
    return t;
}
__asm__(
    "  .section .text.entry,\"ax\",@progbits\n"
    "  .globl entry\n"
    "entry:\n"
    // the site (0xeb04..0xeb13, was: call __lkpi_current; cmpq 0x8(%rax), %r14; jne fail) becomes
    // call entry; jmp 0xeb13 (short); 8 x nop
    "  movq %r14, %rdi\n"
    "  jmp mm_check\n"
);
