; ModuleID = 'chokanbun'
target triple = "aarch64-none-elf"
target datalayout = "e-m:e-i64:64-i128:128-n32:64-S128"

define internal void @"核外輸出"(
ptr %arg0, i64 %arg1) {
entry:
%p0 = alloca ptr, align 8
store ptr %arg0, ptr %p0
%p1 = alloca i64, align 8
store i64 %arg1, ptr %p1
%x2 = alloca i64, align 8
store i64 150994944, ptr %x2
%x3 = alloca i64, align 8
store i64 150994968, ptr %x3
%x4 = alloca i64, align 8
store i64 0, ptr %x4
br label %while.cond.0
while.cond.0:
%v5 = load i64, ptr %x4
%v6 = load i64, ptr %p1
%cmp7 = icmp ult i64 %v5, %v6
br i1 %cmp7, label %while.body.0, label %while.end.0
while.body.0:
%x8 = alloca ptr, align 8
%v9 = load i64, ptr %x2
%cast10 = inttoptr i64 %v9 to ptr
store ptr %cast10, ptr %x8
%x11 = alloca ptr, align 8
%v12 = load i64, ptr %x3
%cast13 = inttoptr i64 %v12 to ptr
store ptr %cast13, ptr %x11
br label %while.cond.1
while.cond.1:
%v14 = load ptr, ptr %x11
%vol15 = load volatile i32, ptr %v14
%r16 = and i32 %vol15, 32
%cmp17 = icmp ne i32 %r16, 0
br i1 %cmp17, label %while.body.1, label %while.end.1
while.body.1:
br label %while.cond.1
while.end.1:
%v18 = load ptr, ptr %x8
%v19 = load ptr, ptr %p0
%v20 = load i64, ptr %x4
%elemptr21 = getelementptr i8, ptr %v19, i64 %v20
%elem22 = load i8, ptr %elemptr21
%cast23 = zext i8 %elem22 to i32
store volatile i32 %cast23, ptr %v18
%v24 = load i64, ptr %x4
%r25 = add i64 %v24, 1
store i64 %r25, ptr %x4
br label %while.cond.0
while.end.0:
ret void
}

define external void @main(
) {
entry:
call void @"核外輸出"(ptr @str.0, i64 12)
ret void
}

@str.0 = private unnamed_addr constant [12 x i8] c"\E4\B8\96\E7\95\8C\E5\AE\89\E5\AF\A7", align 1

