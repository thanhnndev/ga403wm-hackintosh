target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32"
target triple = "air64_v28-apple-macosx26.0.0"

%union.Everything = type { <4 x i32> }

define internal i32 @pick(ptr noundef readonly %u, i32 %o) noinline {
entry:
  %l = getelementptr inbounds %union.Everything, ptr %u, i64 0, i32 0, i64 2
  %lv = load i32, ptr %l, align 8
  %c = icmp ult i32 %o, 8
  br i1 %c, label %a, label %b
a:
  %al = bitcast ptr %u to ptr
  %z = zext i32 %o to i64
  %p = getelementptr inbounds i8, ptr %al, i64 %z
  %bb = load i8, ptr %p, align 1
  %w0 = zext i8 %bb to i32
  br label %b
b:
  %w1 = phi i32 [ %w0, %a ], [ 0, %entry ]
  %w = add i32 %w1, %lv
  ret i32 %w
}

define void @k(ptr addrspace(1) noundef readonly %in, ptr addrspace(1) noundef %out, <2 x i32> noundef %gid) {
  %u = alloca %union.Everything, align 16
  %v = load <4 x i32>, ptr addrspace(1) %in, align 16
  store <4 x i32> %v, ptr %u, align 16
  %x = extractelement <2 x i32> %gid, i64 0
  %o = and i32 %x, 15
  %r = call i32 @pick(ptr %u, i32 %o)
  %q = zext i32 %x to i64
  %dst = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %q
  store i32 %r, ptr addrspace(1) %dst, align 4
  ret void
}

!air.kernel = !{!0}
!air.version = !{!5}
!air.language_version = !{!6}
!0 = !{ptr @k, !1, !2}
!1 = !{}
!2 = !{!3, !4, !7}
!3 = !{i32 0, !"air.buffer", !"air.location_index", i32 0, i32 1, !"air.read", !"air.address_space", i32 1, !"air.arg_type_size", i32 16, !"air.arg_type_align_size", i32 16, !"air.arg_type_name", !"uint4", !"air.arg_name", !"input"}
!4 = !{i32 1, !"air.buffer", !"air.location_index", i32 1, i32 1, !"air.read_write", !"air.address_space", i32 1, !"air.arg_type_size", i32 4, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"uint", !"air.arg_name", !"out"}
!7 = !{i32 2, !"air.thread_position_in_grid", !"air.arg_type_name", !"uint2", !"air.arg_name", !"gid"}
!5 = !{i32 2, i32 8, i32 0}
!6 = !{!"Metal", i32 4, i32 0, i32 0}
