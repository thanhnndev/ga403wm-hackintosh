# linux_rcu_read_lock/unlock for NMXGPU (ga403wm Step77). sched_pin does not pin on xnu, so a reader that migrated
# between lock and unlock ended the epoch on another CPU's record and left its own active forever: synchronize_rcu
# never returned. Every reader now uses the CPU-0 record of its type (ck_epoch sections give shared records forward
# progress, as FreeBSD's per-CPU record shared by preempted readers), and a spinlock in record 0's padding (0xf8,
# past type at 0xd4) serializes the record updates across CPUs; interrupts are off (critical section) while it is held.
        .intel_syntax noprefix
        .text
        .globl _start
_start:
lock_fn:
        push rbp
        mov rbp, rsp
        push r15
        push r14
        push rbx
        push rax
        mov r14d, edi
        call LKPI_CURRENT
        mov rbx, rax
        mov r15d, r14d
        mov eax, [rax+r15*4+0x78]
        lea ecx, [rax+1]
        mov [rbx+r15*4+0x78], ecx
        test eax, eax
        je 1f
        add rsp, 8
        pop rbx
        pop r14
        pop r15
        pop rbp
        ret
1:      call SCHED_PIN
        mov rax, r15
        shl rax, 16
        lea r14, [rip+EPOCH_RECORD]
        add r14, rax
        call CRIT_ENTER
2:      lock bts dword ptr [rip+RCU_LOCK], 0
        jnc 4f
3:      pause
        test byte ptr [rip+RCU_LOCK], 1
        jnz 3b
        jmp 2b
4:      lea rsi, [rbx+r15*4+0x98]
        mov eax, [r14+0x18]
        test eax, eax
        je 5f
        inc eax
        mov [r14+0x18], eax
        jmp 6f
5:      mov rax, [r14+8]
        mov ecx, 1
        xchg [r14+0x18], ecx
        mov eax, [rax]
        mov [r14+0x14], eax
6:      mov rdi, r14
        call CK_ADDREF
        shl r15, 4
        lea rax, [rbx+r15+0x58]
        mov qword ptr [rbx+r15+0x58], 0
        mov rcx, [r14+0xc8]
        mov [rbx+r15+0x60], rcx
        mov [rcx], rbx
        mov [r14+0xc8], rax
        mov dword ptr [rip+RCU_LOCK], 0
        add rsp, 8
        pop rbx
        pop r14
        pop r15
        pop rbp
        jmp CRIT_EXIT
lock_end:
        .fill 0xe0 - (lock_end - lock_fn), 1, 0xcc

unlock_fn:
        push rbp
        mov rbp, rsp
        push r15
        push r14
        push r13
        push r12
        push rbx
        push rax
        mov r14d, edi
        call LKPI_CURRENT
        mov r15d, r14d
        dec dword ptr [rax+r15*4+0x78]
        je 1f
        add rsp, 8
        pop rbx
        pop r12
        pop r13
        pop r14
        pop r15
        pop rbp
        ret
1:      mov rbx, rax
        mov rax, r15
        shl rax, 16
        lea r14, [rip+EPOCH_RECORD]
        add r14, rax
        call CRIT_ENTER
2:      lock bts dword ptr [rip+RCU_LOCK], 0
        jnc 4f
3:      pause
        test byte ptr [rip+RCU_LOCK], 1
        jnz 3b
        jmp 2b
4:      lea rsi, [rbx+r15*4+0x98]
        dec dword ptr [r14+0x18]
        mov rdi, r14
        call CK_DELREF
        shl r15, 4
        mov rdx, [rbx+r15+0x58]
        mov rcx, [rbx+r15+0x60]
        test rdx, rdx
        je 5f
        mov [rdx+r15+0x60], rcx
        jmp 6f
5:      mov [r14+0xc8], rcx
6:      mov [rcx], rdx
        mov dword ptr [rip+RCU_LOCK], 0
        call CRIT_EXIT
        add rsp, 8
        pop rbx
        pop r12
        pop r13
        pop r14
        pop r15
        pop rbp
        jmp SCHED_UNPIN
unlock_end:
        .fill 0xc0 - (unlock_end - unlock_fn), 1, 0xcc

