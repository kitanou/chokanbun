# 暫定アセンブリ・C 依存の一覧と置換結果

[roadmap.md](roadmap.md) F1 の「暫定アセンブリ依存を一覧化し、置換順序を定める」の成果物。2026-10-26 に作り、同日に段階 A〜G を実施し、2026-10-27 に型付き機械命令（段階 H）を追加して更新した。

## 1. 結論

- リポジトリに **`.S` ファイルは残っていない**。核・民・Phase 0 スタブのアセンブリは、機械漢文の `組譯`（インライン asm）と**型付き機械命令**に置き換えた。
- 型付き機械命令（`系統讀`・`系統寫`・`記憶障壁`・`命令障壁`・`臺無效`・`資清`・`令清`・`待事象`・`漢令`・`異常令`）はコンパイラが命令を生成する。
  レジスタ名・バリア領域・TLB 操作はコンパイラが検査するため、これらの操作は**ソースからアセンブリ文が消えている**（[language-spec.md](language-spec.md) §6）。
- 残る `組譯` は 13 か所。内訳は例外ベクタと入口の呼出し・分岐（`kernel/entry.mkn` の 9）、裸の入口（`kernel/boot.mkn`・`user/lib.mkn` の 3、`boot/boot.mkn` の 1）である（§4）。レジスタ退避の框は型付き機械命令（`框存`・`框復`・`例外歸`）へ移した。
  「機械漢文で書かれた」ことと「アセンブリ文を含まない」ことは別で、後者は未達成である。
- 置換でコンパイラ（言語）に足したもの: `組譯`・`裸`・`齊`・`取址(術名)`、型付き機械命令（[language-spec.md](language-spec.md) §6・§7）。
- 検証: `make test` 全件 PASS（QEMU 試験を含む）。`enable_mmu` の `dsb`/`isb` の順、`SCTLR_EL1` の PAN/M/C/I の操作、`dc cvau` の 64 バイト走査、`svc #0` のレジスタ配置、ベクタ表の 2 KiB 整列と 0x80 間隔、各入口の分岐先、漢像ヘッダの 40 バイトを逆アセンブルなどで元と照合した。

## 2. 置換前の一覧と置換先

| 区分 | 旧ファイル（行） | 置換先 | 使った機能 |
|---|---|---|---|
| 核 | `kernel/boot.S`（42） | `kernel/boot.mkn`: 裸の `_start`（SP 設定）→ `早起動`（`.bss` 零化は `寫揮發`、`VBAR_EL1` 設定は `系統寫`、`核主` へ） | `裸` `節` `組譯` `系統寫` `命令障壁` `待事象` `取址` |
| 核 | `kernel/vectors.S`（147） | `kernel/entry.mkn`: 裸の `向量`（`_vectors`、2 KiB 整列。表・`exception_handler`・`irq_handler`） | `裸` `齊` `節` `組譯` |
| 核 | `kernel/el0.S`（224） | `kernel/entry.mkn`: `enter_el0`、`lower_sync_handler`、`lower_irq_handler`（`el0_resume`・`el0_park` を含む）、復帰スタブ 2 つ、各入口アドレスは `取址` | `裸`（引数付き）`組譯` `取址` |
| 核 | `kernel/sysreg.S`（139） | `kernel/proc/sysreg.mkn`: 13 関数（MMU・TTBR0・タイマー・DAIF・FAR・TLB・キャッシュ）。`組譯` は 0 | `系統讀` `系統寫` `記憶障壁` `命令障壁` `臺無效` `資清` `令清` `待事象` |
| 核 | `svc_call`・`trigger_exception` | `kernel/kernel.mkn` の `奏令`・`試異常`。`組譯` は 0 | `漢令` `異常令` |
| 民 | `user/crt0.S`（53） | `user/lib.mkn`: 裸の `_start`・`__task_exit_stub`、`奏令`（`漢令`）。`KBN1` ヘッダは `user/user.lds` の `BYTE`/`LONG`/`QUAD` | `裸` `漢令` `組譯` + リンカスクリプト |
| 民（像別） | `user/btron_msg_hdr_aux.S`・`btron_task_aux.S`・`btron_exc_aux.S` | 各 `.mkn` の `取址(術名)`、`副入口`、`例割`（`異常令`）、`八置`（`exc_store`） | `取址` `異常令` `寫揮發` |
| 試 | `boot/boot.S`（21） | `boot/boot.mkn`（`uart`・`uart_mmio` 試験の起動スタブ） | `裸` `組譯` |

`tools/mkimage.sh` の `crt0.S`・`_aux.S` のリンク、`tests/run_tests.sh` の `.S` コンパイルは削除した。

## 3. 言語機能（置換のために追加）

| 記号 | 機能 | 実装 |
|---|---|---|
| L1・L3・L4 | システムレジスタ・バリア・TLB・キャッシュ・`svc`・`brk`・`wfi` | **型付き機械命令**（`系統讀`・`系統寫`・`記憶障壁`・`命令障壁`・`臺無效`・`資清`・`令清`・`待事象`・`漢令`・`異常令`）。コンパイラが固定の命令列を生成する |
| L2 | 関数のアドレス | `取址(術名)`（`ptrtoint`、PC 相対）。`外術` ならリンカ記号 |
| L5 | 前後奏なし・整列・セクション | `裸`（`naked noinline nounwind`）、`齊 N`、既存の `節` |
| L6 | `eret`・全レジスタ退避 | **型付き機械命令** `框存〈『el1』『el1irq』『el0』〉`・`框復`・`例外歸`。ベクタ表と `bl`/`cbz` は汎用 `組譯` |
| L7 | `KBN1` ヘッダ | 言語機能は不要。リンカスクリプトのデータ命令で出す |

外部宣言と `公開` 関数を `dso_local` にしたのは、`取址` が GOT を経由しないようにするため。

## 4. 残っているもの（アセンブリ文の数）

`組譯` の呼び出し（= アセンブリ文字列）の数:

| ファイル | 数 | 内容 |
|---|---|---|
| `kernel/entry.mkn` | 9 | ベクタ表 1、`bl`/`cbz`/`b` の呼出し・分岐 5（例外・核割込・下位同期・下位割込・待機）、`enter_el0`・`例戻`・`信戻` 各 1。退避・復帰・`eret` は `框存`・`框復`・`例外歸` |
| `kernel/boot.mkn` | 1 | 裸の `_start`（SP 設定・`kernel_early` 呼出・停止ループ） |
| `user/lib.mkn` | 2 | 裸の `_start`（`user_main` 呼出・`終行程`）と `__task_exit_stub`（`ext_tsk`） |
| `boot/boot.mkn` | 1 | Phase 0 スタブ（SP 設定・`main` 呼出・停止ループ） |
| `kernel/proc/sysreg.mkn` | 0 | 型付き機械命令へ置換済み |
| `kernel/kernel.mkn` | 0 | `漢令`・`異常令` へ置換済み |
| `user/btron_exc.mkn` | 0 | `異常令` へ置換済み |

- C の残り: `boot/uart.c`（参照用。`uart` 試験が使う）。アセンブリではないが、F9 の「手書き C の残存依存」で扱う。
- 次に進めるなら、ベクタ表の 16 項（`.p2align 7` と `b`）と `bl`/`cbz` の呼出し・分岐を型付きにする。裸の入口は `置棧`・`記號址` のような組込みを足せば縮められる。
- `組譯` はコンパイラが中身を検査しない。誤りはアセンブル時または実行時にしか分からない（逆アセンブルでの照合と QEMU 試験で補っている）。
  型付き機械命令は、引数の型・レジスタ名の文字種・バリア領域・TLB 操作・即値の範囲をコンパイラが検査する。

## 5. 実施の記録

段階 A（`exc_store` → `八置`）、B（`取址` と `*_addr` の置換）、C（`sysreg.S`）、D（`svc_call`・`trigger_exception`）、E（`boot.S`）、G（`crt0.S` とヘッダ）、F（`vectors.S`・`el0.S`）の順で、各段階を `make test` 全件 PASS でコミットした。
当初の計画は B → C → D → E → F → G だったが、最難の F を最後にして、途中で止まっても G までの成果が残るようにした。

段階 H（2026-10-27）: 型付き機械命令をコンパイラへ追加し、`kernel/proc/sysreg.mkn`（13 文）、`kernel/kernel.mkn`（2 文）、`user/btron_exc.mkn`（1 文）、`kernel/boot.mkn`（2 文）、`user/lib.mkn`（1 文）を置換した。
`make test` 全件 PASS。`tests/lang/ok/machine.mkn` が生成命令（`mrs`/`msr`/`dsb`/`isb`/`tlbi`/`dc`/`ic`/`wfi`/`svc`/`brk`）を逆アセンブルで照合する。
