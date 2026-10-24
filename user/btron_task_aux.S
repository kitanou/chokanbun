// Auxiliary assembly for the 副試 image (user/btron_task.mkn).
//
// 機械漢文には関数のアドレスを取る式が無いので、副タスクの入口のアドレスは
// このファイルから ELF 記號で取り出す。mkimage.sh は user/<name>_aux.S が
// あれば自動でリンクする (この像だけの補助)。
//
// subtask_entry は cre_tsk に渡す入口。本体 (btron_subtask_body) から return
// すると ext_tsk (漢令 186) を発行する。主タスクの ext_tsk と違い、副タスクの
// ext_tsk はプロセスを終えず、その枠だけを片付ける。

    .text

    .globl subtask_entry_addr
subtask_entry_addr:
    adrp x0, subtask_entry
    add  x0, x0, :lo12:subtask_entry
    ret

    .globl subtask_entry
subtask_entry:
    // x0 = 引 (cre_tsk の第 3 引数)。
    bl btron_subtask_body
    mov x8, #186
    svc #0
1:  b 1b
