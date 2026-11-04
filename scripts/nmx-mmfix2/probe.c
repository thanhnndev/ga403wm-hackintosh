// SPDX-License-Identifier: BSD-3-Clause-Clear
// Offsets for the Step100 mm-lifetime cave (struct thread/proc are the fork's bsdcompat ones; the two record
// structs repeat nmx_kernel.c's private definitions).
#include <linux/compat.h>
#include <linux/mm.h>
#include <linux/sched.h>
#include <sys/proc.h>
struct nmx_thread_rec { struct thread td; struct nmx_thread_rec *next; int transient; };
struct nmx_proc_rec { struct proc p; void *xnu; struct nmx_proc_rec *next; };
#define O(n, v) __asm__ volatile(".ascii \"@@" #n " %c0@@\"" :: "i"(v))
void probe(void)
{
    O(td_xnu, offsetof(struct thread, td_xnu));
    O(td_proc, offsetof(struct thread, td_proc));
    O(td_lkpi_task, offsetof(struct thread, td_lkpi_task));
    O(td_tid, offsetof(struct thread, td_tid));
    O(td_critnest, offsetof(struct thread, td_critnest));
    O(td_fpop, offsetof(struct thread, td_fpop));
    O(td_nmx_open, offsetof(struct thread, td_nmx_open));
    O(td_name, offsetof(struct thread, td_name));
    O(trec_next, offsetof(struct nmx_thread_rec, next));
    O(trec_size, sizeof(struct nmx_thread_rec));
    O(p_pid, offsetof(struct proc, p_pid));
    O(p_comm, offsetof(struct proc, p_comm));
    O(p_comm_size, sizeof(((struct proc *)0)->p_comm));
    O(p_lkpi_mm, offsetof(struct proc, p_lkpi_mm));
    O(p_nmx_xnu, offsetof(struct proc, nmx_xnu));
    O(prec_xnu, offsetof(struct nmx_proc_rec, xnu));
    O(prec_next, offsetof(struct nmx_proc_rec, next));
    O(prec_size, sizeof(struct nmx_proc_rec));
    O(ts_task_thread, offsetof(struct task_struct, task_thread));
    O(ts_mm, offsetof(struct task_struct, mm));
    O(ts_usage, offsetof(struct task_struct, usage));
    O(ts_comm, offsetof(struct task_struct, comm));
    O(ts_pid, offsetof(struct task_struct, pid));
    O(ts_group_leader, offsetof(struct task_struct, group_leader));
    O(mm_count, offsetof(struct mm_struct, mm_count));
    O(mm_users, offsetof(struct mm_struct, mm_users));
    O(mm_mmap_sem, offsetof(struct mm_struct, mmap_sem));
    O(mm_size, sizeof(struct mm_struct));
}
