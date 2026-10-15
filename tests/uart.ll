; ModuleID = 'chokanbun'
target triple = "aarch64-none-elf"
target datalayout = "e-m:e-i64:64-i128:128-n32:64-S128"

declare void @核外輸出(
ptr %址, i64 %長)

define void @核主(
) external {
entry:
call void @核外輸出(ptr ptr @ptr @str.0, i64 i64 12)
ret void
}

