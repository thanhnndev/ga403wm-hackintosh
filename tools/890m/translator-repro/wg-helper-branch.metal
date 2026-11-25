#include <metal_stdlib>
using namespace metal;
struct WG { half4 e[128]; };
struct S5 { WG m; };
__attribute__((noinline)) void h(uint li, device half4* o, threadgroup WG* wg) { if (li < 128u) { wg->e[li] = half4(0.0h); } threadgroup_barrier(mem_flags::mem_threadgroup); o[li] = wg->e[li]; }
kernel void k(device half4* o [[buffer(0)]], uint li [[thread_index_in_threadgroup]], threadgroup S5* t [[threadgroup(0)]]) { h(li, o, &t->m); }
