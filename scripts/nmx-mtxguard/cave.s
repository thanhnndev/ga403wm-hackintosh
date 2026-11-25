# nmx_mtx_unlock (NMXGPU 0x6d8850) moved into the never-run DCE6 crtc_disable (0x156ef0, SI display only; ga403wm Step78).
# On x86 xnu, lck_mtx_unlock of a free mutex is taken for a spin-mode release and calls enable_preemption: the CPU's
# preemption level goes to -1 and the next thread_block panics far from the culprit ("preemption_level -1, possible
# cause: unlocking an unlocked mutex", WindowServer in amdgpu_cs_ioctl, 2026-11-03). A FreeBSD mutex records its owner;
# an unlock with no owner is now logged with the mutex name and the caller, and dropped.
        .intel_syntax noprefix
        .text
        .globl _start
_start:
        push rbp
        mov rbp, rsp
        push rbx
        push rax
        mov rax, [rdi+0x18]
        test rax, rax
        jz COLD
        mov ecx, [rdi+0x28]
        test ecx, ecx
        jle 1f
        dec ecx
        mov [rdi+0x28], ecx
        pop rcx
        pop rbx
        pop rbp
        ret
1:      cmp qword ptr [rdi+0x20], 0
        je 2f
        and qword ptr [rdi+0x20], 0
        cmp dword ptr [rdi+0xc], 2
        jne MTX_TAIL
        mov ebx, [rdi+0x2c]
        mov rdi, rax
        jmp SPIN_CALL
2:      mov rdx, rdi
        mov rsi, [rdi]
        mov rcx, [rbp+8]
        lea rdi, [rip+3f]
        xor eax, eax
        pop r8
        pop rbx
        pop rbp
        jmp PRINTF_TAIL
3:      .asciz "NullMoth xkpi: unlock of unlocked mutex %s (%p) from %p\n"
end:
        .fill 0x240 - (end - _start), 1, 0xcc
