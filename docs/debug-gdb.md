# GDB・LLDB による起動・例外の調査

状態: **手順を確認済み（2026-10-26、macOS 14 arm64 / LLDB）**。QEMU の GDB スタブに接続し、起動直後の停止、関数の breakpoint、例外のレジスタ（`ESR_EL1`・`ELR_EL1`・`SPSR_EL1`）、スタックの読み出しまでを実際に確認した。GDB の節は同じ GDB リモートプロトコルを使う Linux・ARM ツールチェーン向けの手順である。

関連: [AArch64 ABI・ブート設計](abi-aarch64.md)、[実装メモ](implementation-notes.md)、[開発ロードマップ](roadmap.md) の F0。

## 1. 準備

```sh
make test     # tests/output/kernel.elf（記号つき）を作る
```

- `tests/output/kernel.elf` には関数のシンボル（`_start`・`_vectors`・`exception_dispatch`・`irq_dispatch`・`svc_dispatch` など）が残る。DWARF の行情報・局所変数は無い（コンパイラが IR にデバッグ情報を出さない）ため、停止位置は関数単位、値はレジスタとメモリから読む。
- 機械漢文の関数名はそのままシンボルになる。`kernel_all.mkn` を展開した `tests/output/kernel.ll`、`kernel.dis`（逆アセンブル）も参照できる。

## 2. QEMU を GDB スタブ付きで起動する

```sh
qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic \
  -global virtio-mmio.force-legacy=false \
  -kernel tests/output/kernel.elf \
  -serial file:tests/output/debug_serial.log \
  -s -S
```

| 指定 | 意味 |
|---|---|
| `-s` | `-gdb tcp::1234` と同じ。TCP 1234 番で GDB リモート接続を待つ |
| `-S` | 起動時に CPU を止める。接続して `continue`（または `stepi`）するまで 1 命令も実行しない |
| `-serial file:...` | ゲストの UART 出力をファイルへ書く。`mon:stdio` のままだと GDB と QEMU の端末入力が競合するため、起動調査ではファイルへ逃がす |

- 起動時の PC は `_start`（`0x40000000`）で止まる。
- ゲストの出力は別端末で `tail -f tests/output/debug_serial.log` とすれば追える。
- 殻と対話したいときは `-serial mon:stdio` にして QEMU の端末をそのまま使い、GDB は別端末から接続する（この場合 `-S` を外し、必要なら `-s` だけで起動する）。
- QEMU を終えるときは `Ctrl-A` のあと `X`（`-nographic` の monitor）。

## 3. LLDB で接続する（macOS）

macOS 標準の `/usr/bin/lldb` が AArch64 の ELF と QEMU の GDB スタブを扱える。Homebrew の `gdb` は Apple Silicon で動かないため、macOS では LLDB を使う。

```sh
lldb tests/output/kernel.elf
```

```text
(lldb) gdb-remote 1234
(lldb) breakpoint set -n exception_dispatch
(lldb) continue
(lldb) register read pc x0 x1 x2 x3
(lldb) register read esr_el1 elr_el1 spsr_el1 far_el1
(lldb) memory read --size 8 --format x --count 8 $sp
(lldb) bt
(lldb) detach
```

`-b` を付けるとバッチ実行になる。起動から `exception_dispatch` までを非対話で調べる例:

```sh
lldb -b tests/output/kernel.elf \
  -o "breakpoint set -n exception_dispatch" \
  -o "gdb-remote 1234" \
  -o "continue" \
  -o "register read pc x0 x1 x2 x3" \
  -o "register read esr_el1 elr_el1 spsr_el1" \
  -o "detach"
```

確認した出力（起動時の `BRK` を捕まえたところ。番地はビルドで変わる）:

```text
(lldb) breakpoint set -n exception_dispatch
Breakpoint 1: where = kernel.elf`exception_dispatch, address = 0x00000000400017d8
(lldb) gdb-remote 1234
Process 1 stopped
* thread #1, stop reason = signal SIGTRAP
    frame #0: 0x0000000040000000 kernel.elf`_start
(lldb) continue
Process 1 stopped
* thread #1, stop reason = breakpoint 1.1
    frame #0: 0x00000000400017d8 kernel.elf`exception_dispatch
(lldb) register read pc x0 x1
      pc = 0x00000000400017d8 kernel.elf`exception_dispatch
      x0 = 0x00000000f2000000
      x1 = 0x00000000400010c0 kernel.elf`trigger_exception
(lldb) register read esr_el1 elr_el1 spsr_el1
 ESR_EL1 = 0x00000000f2000000
 ELR_EL1 = 0x00000000400010c0 kernel.elf`trigger_exception
SPSR_EL1 = 0x00000000600003c5
```

- `exception_dispatch` の入口では、`x0` に `ESR_EL1` の値、`x1` に `ELR_EL1` の値がベクタから渡されている（[abi-aarch64.md](abi-aarch64.md) の例外の節）。上の `0xf2000000` は `BRK`（EC = `0x3C`）である。
- 例外を起こした命令の番地は `ELR_EL1`、戻り先の状態は `SPSR_EL1`、データ・命令のアクセス先は `FAR_EL1` で見る。
- `bt` は保存された `x30` をたどる。機械漢文の関数はフレームポインタを保証しないので、`frame #1` 以降が `kernel.elf`` のまま（名前なし）になることがある。その場合は `register read x29 x30` と `memory read` で戻り先を手でたどる。

### 主な breakpoint

| シンボル | 用途 |
|---|---|
| `_start` | ブートの最初（`0x40000000`） |
| `_vectors` | 例外ベクタ表の先頭。2 KiB 整列の確認にも使える |
| `exception_dispatch` | 同期例外・SError の漢文ハンドラ。`ESR_EL1`・`ELR_EL1` を見る |
| `irq_dispatch` | EL1 の IRQ（タイマー・UART） |
| `lower_sync_handler` / `lower_irq_handler` | EL0 からの SVC・IRQ の入口（`kernel/entry.mkn`） |
| `svc_dispatch` | 漢令の分岐。`x8` が漢令番号、`x0`〜`x5` が引数 |
| `main` | カーネルの初期化が一通り終わったあと |

### よく使う操作

```text
(lldb) stepi                 # 1 命令実行
(lldb) nexti                 # 次の命令まで（分岐をまたぐ）
(lldb) breakpoint set -n svc_dispatch
(lldb) breakpoint disable 1  # 一度止まった breakpoint を外す
(lldb) register read --all   # 汎用・システムレジスタをまとめて表示
(lldb) memory read --size 4 --format x --count 16 0x403E0880
(lldb) process interrupt     # 走っているゲストを止める
(lldb) continue
(lldb) detach                # ゲストを走らせたまま QEMU から離れる
```

- 固定番地の表（優先表 `0x403E0880`、メッセージの槽 `0x403E1000` など）は [abi-aarch64.md](abi-aarch64.md) の「核の固定表」に一覧がある。
- 装置のレジスタ（PL011・GIC・virtio-mmio）も `memory read` で読める。読み書きが副作用を持つので、停止中に気軽に書かない。

## 4. GDB で接続する（Linux・ARM ツールチェーン）

Debian/Ubuntu では `gdb-multiarch` を入れる。macOS で GDB を使いたい場合は Docker の Linux コンテナで `gdb-multiarch` を動かす（QEMU をホストで動かし、`--network host` で 1234 番に接続する）。

```sh
sudo apt install gdb-multiarch qemu-system-arm
gdb-multiarch tests/output/kernel.elf
```

```text
(gdb) set architecture aarch64
(gdb) target remote :1234
(gdb) break exception_dispatch
(gdb) continue
(gdb) info registers pc x0 x1
(gdb) p/x $esr_el1
(gdb) p/x $elr_el1
(gdb) x/8gx $sp
(gdb) bt
(gdb) detach
```

- `target remote localhost:1234` でもよい。`-S` 付きで起動していれば、接続直後は `_start` で止まっている。
- システムレジスタの名前は GDB の版によって `$esr_el1` と `$ESR_EL1` のどちらでも通る。通らないときは `monitor info registers`（QEMU monitor 経由）で生の値を見る。
- ARM の配布ツールチェーンでは `aarch64-none-elf-gdb` を使う。`gdb-multiarch` と同じコマンドでよい。

## 5. 例外を調べる

1. `exception_dispatch` に breakpoint を置いて `continue` する。
2. `ESR_EL1` の上位 6 ビット（`ESR_EL1 >> 26`）で例外の種類を見る。

| EC | 意味 | 主に見るもの |
|---|---|---|
| `0x15` | AArch64 の `SVC` | `ELR_EL1` の次の命令、`x8`（漢令番号） |
| `0x20` / `0x21` | 命令のアクセス異常（下位 EL / 同じ EL） | `FAR_EL1`・`ELR_EL1`・頁表 |
| `0x24` / `0x25` | データのアクセス異常（下位 EL / 同じ EL） | `FAR_EL1`・`ELR_EL1`・頁表 |
| `0x3C` | `BRK` | `ELR_EL1`（`BRK` の番地） |

3. `ELR_EL1` の番地を `kernel.dis` と突き合わせ、どの関数・どの命令で起きたかを見る。

```sh
grep -n "400017d8" tests/output/kernel.dis     # 例: 停止した番地を逆アセンブルから探す
```

4. EL0 の行程が原因なら、`lower_sync_handler` か `svc_dispatch` で止め、`ELR_EL1`（民の番地）と保存フレーム（`kernel/entry.mkn` が作る 288 バイト）を読む。民の像は `0x40610000` から始まるので、`memory read` と `objdump` で照合できる。
5. 割込がらみなら `irq_dispatch` と `GICC_IAR`（`0x0801000C`）を見る。タイマーは `CNTP_CTL_EL0`・`CNTP_TVAL_EL0` を `register read` で確認できる。

## 6. 後片付け

```text
(lldb) detach
```

QEMU の端末で `Ctrl-A` のあと `X`。バックグラウンドで起動した場合は `kill %1` などで止める。`tests/output/debug_serial.log` は次の起動で上書きされるので、必要なら別名で保存する。

## 7. 既知の制限

- 行情報・局所変数が無いため、ソース行単位の停止や `frame variable` はできない。関数の入口とレジスタ・メモリで調べる。
- `-s -S` は単一 CPU 前提。SMP にした場合は `info threads` で CPU ごとに切り替える（現行の核は 1 CPU）。
- GDB スタブは QEMU の版によって一部のシステムレジスタ名が異なる。読めないときは QEMU monitor の `info registers` を使う。
