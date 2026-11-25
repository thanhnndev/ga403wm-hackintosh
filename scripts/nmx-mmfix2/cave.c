// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step100: retire stale xkpi thread and process records (root cause behind the Step97b CS -EPERM loop).
// xkpi keys its thread records (nmx_threads, 256 buckets) by the xnu thread_t pointer and its process records
// (nmx_procs, 64 buckets) by the proc_t pointer, and never drops either. xnu reuses both pointers, so a new
// WindowServer thread could pick up a dead thread's record (its Linux task, and through it another process's mm),
// and a new process a dead process's record (its p_lkpi_mm). The record already stores the thread id (td_tid, +0x18,
// thread_tid & 0x7fffffff) and the pid (+0x0); nothing compared them. Now the lookups do:
//   nmx_thread_get 0x6d7530: a key match whose td_tid is not the current thread's tid is unkeyed (key = 0) and the
//     walk goes on, so the slow path builds a fresh record;
//   nmx_proc_for 0x6d73c0: same with the pid, unkeying the proc pointer at +0x38.
// The kernel calls reuse the call instructions the kext linker already filled in (thread_tid at 0x6d757e, proc_pid
// at 0x6d73fc): the cave reads their rel32 at run time. Unkeyed records stay allocated (a leak of a few hundred bytes
// per retired record, as before); after CAP retirements of a kind the old behaviour comes back, so a wrong td_tid can
// never turn into a record per call. The counts are logged from the two slow paths (outside the spin lock).
// Source fix: nmx-src fork, branch mm-lifetime, commit 163d117.
typedef unsigned long u64; typedef unsigned int u32;
#pragma GCC visibility push(hidden)
extern int SNPRINTF(char *buf, u64 n, const char *fmt, ...);
extern int PRINTF(const char *fmt, ...);
extern const char FMT_S[];
extern u32 CNT[4];                       // ci_update_sclk_threshold.__ratelimited (CI dpm only, never runs on Strix)
extern const unsigned char TID_CALL[];   // 0x6d757e: call thread_tid (linked)
extern const unsigned char PID_CALL[];   // 0x6d73fc: call proc_pid (linked)
#pragma GCC visibility pop

#define CAP 4096u

static u64 call_target(const unsigned char *c)
{
    return (u64)(c + 5) + (u64)(long)*(const int *)(c + 1);
}

// r: a thread record whose key matched thread. 1 = valid, 0 = retired.
int t_ok(char *r, u64 thread)
{
    u64 (*tid)(u64) = (u64 (*)(u64))call_target(TID_CALL);
    u32 t = (u32)tid(thread) & 0x7fffffffu;
    if (t == *(u32 *)(r + 0x18) || CNT[0] >= CAP)
        return 1;
    CNT[0]++;
    *(u64 *)r = 0;
    return 0;
}

// r: a process record whose key (+0x38) matched proc. 1 = valid, 0 = retired.
int p_ok(char *r, u64 proc)
{
    int (*pid)(u64) = (int (*)(u64))call_target(PID_CALL);
    if (pid(proc) == *(int *)r || CNT[1] >= CAP)
        return 1;
    CNT[1]++;
    *(u64 *)(r + 0x38) = 0;
    return 0;
}

void flush(void)
{
    u32 t = CNT[0], p = CNT[1];
    if (t == CNT[2] && p == CNT[3])
        return;
    CNT[2] = t; CNT[3] = p;
    char b[160];
    SNPRINTF(b, sizeof b, "NMX mmfix2: stale xkpi records retired: threads %u, procs %u (cap %u)", t, p, CAP);
    PRINTF(FMT_S, b);
}

__asm__(
    "  .section .text.entry,\"ax\",@progbits\n"
    // nmx_thread_get 0x6d7530 (was: cmpq %r15,(%r14); je 0x6d75ea) -> jmp t_entry; 4 x nop
    "  .globl t_entry\n"
    "t_entry:\n"
    "  cmpq %r15, (%r14)\n"
    "  jne 1f\n"
    "  pushq %rax\n pushq %rcx\n pushq %rdx\n pushq %rsi\n pushq %rdi\n"
    "  pushq %r8\n pushq %r9\n pushq %r10\n pushq %r11\n pushq %r11\n"
    "  movq %r14, %rdi\n"
    "  movq %r15, %rsi\n"
    "  call t_ok\n"
    "  testl %eax, %eax\n"
    "  popq %r11\n popq %r11\n popq %r10\n popq %r9\n popq %r8\n"
    "  popq %rdi\n popq %rsi\n popq %rdx\n popq %rcx\n popq %rax\n"
    "  jnz T_FOUND\n"
    "1:\n"
    "  jmp T_NEXT\n"
    // nmx_proc_for 0x6d73c0 (was: cmpq %r14,0x38(%rbx); je 0x6d7447) -> jmp p_entry; 5 x nop
    "  .globl p_entry\n"
    "p_entry:\n"
    "  cmpq %r14, 0x38(%rbx)\n"
    "  jne 2f\n"
    "  pushq %rax\n pushq %rcx\n pushq %rdx\n pushq %rsi\n pushq %rdi\n"
    "  pushq %r8\n pushq %r9\n pushq %r10\n pushq %r11\n pushq %r11\n"
    "  movq %rbx, %rdi\n"
    "  movq %r14, %rsi\n"
    "  call p_ok\n"
    "  testl %eax, %eax\n"
    "  popq %r11\n popq %r11\n popq %r10\n popq %r9\n popq %r8\n"
    "  popq %rdi\n popq %rsi\n popq %rdx\n popq %rcx\n popq %rax\n"
    "  jnz P_FOUND\n"
    "2:\n"
    "  jmp P_NEXT\n"
    // slow paths, after the spin lock is dropped: 0x6d7551 (movl $0xf0,%edi) / 0x6d73df (movl $0x48,%edi) -> call
    "  .globl t_log\n"
    "t_log:\n"
    "  pushq %rbp\n movq %rsp, %rbp\n call flush\n popq %rbp\n"
    "  movl $0xf0, %edi\n"
    "  ret\n"
    "  .globl p_log\n"
    "p_log:\n"
    "  pushq %rbp\n movq %rsp, %rbp\n call flush\n popq %rbp\n"
    "  movl $0x48, %edi\n"
    "  ret\n"
);
