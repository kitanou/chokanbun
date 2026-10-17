; ModuleID = 'chokanbun'
target triple = "aarch64-none-elf"
target datalayout = "e-m:e-i64:64-i128:128-n32:64-S128"

declare void @"核外輸出"(ptr, i64)

define external void @main(
) {
entry:
call void @"核外輸出"(ptr @str.0, i64 12)
ret void
}

@str.0 = private unnamed_addr constant [12 x i8] c"\E4\B8\96\E7\95\8C\E5\AE\89\E5\AF\A7", align 1

