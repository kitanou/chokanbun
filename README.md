# 超漢文 OS — ChoKanbun OS

**BTRON3仕様への完全準拠と、機械漢文による自己完結を目指す AArch64 ネイティブ OS。**

> 世界安寧

![起動から漢殻でファイルを読むまでのデモ](docs/demo/chokanbun-demo.gif)

超漢文は、機械漢文でカーネル内部まで記述する独立 OS の研究開発プロジェクトです。初期実行基盤は QEMU `virt` / AArch64。機械漢文は LLVM IR を経由して ARM64 機械語へコンパイルされ、カーネルとユーザー空間のプログラムに使われます。

長期目標は、BTRON3 仕様書 Ver. 3.20.00 への完全準拠を検証可能な形で進めること、そしてブートローダー・カーネル・ドライバ・ユーザー空間・コンパイラを段階的に機械漢文で記述することです。現時点で BTRON3 完全準拠やセルフホスティングを達成したという意味ではありません。

## プロジェクトの柱

- **BTRON3 互換性：** 規範仕様を棚卸しし、実装・テスト・適合状況を対応づけて検証する。
- **必須 UI「漢殻」：** GUI を導入した後も、基本操作・診断・保守・復旧に使えるシェルとして維持する。
- **実身・仮身と篇藏：** BTRON3 のデータモデルを基準に、超漢文独自のファイル体系を段階的に統合する。篇藏は LLM に依存しない決定的な仕組みとする。
- **機械漢文による自己完結：** 暫定アセンブリ等を記録しながら、ブートローダーからユーザー空間まで機械漢文化する。
- **独自 CPU 研究：** 機械漢文 CPU とエミュレータは、AArch64 版 OS の完成を妨げない独立トラックで進める。

## 現在の実装状況

現時点の基礎実装には、機械漢文コンパイラ、AArch64 コード生成、QEMU 起動、カーネルの例外・MMU・タイマー・割込の基礎、EL0 行程、行程切替、アドレス空間、漢令、篇藏（階層名前空間・権限）、最小版の漢殻、そして BTRON3 互換層（行程・メッセージ・同期・グローバル名・時計・ファイル管理の一部）があります。詳細な完了状況はテストと仕様照合に基づき更新します。

| 領域 | 現状 |
|---|---|
| コンパイラ | 字句解析・構文解析・型検査・LLVM IR 生成の基礎を実装 |
| カーネル | QEMU/AArch64 起動、例外処理、MMU、ページ管理、タイマー・割込の基礎を実装 |
| 行程・漢令 | EL0 実行、SVC ABI、スケジューラ、アドレス空間、プリエンプション等の基礎を実装 |
| 篇藏・漢殻 | 篇藏（篇ID・章とパス・権限・作時/改時）と機械漢文製の最小シェルを実装。殻の `時` が黄帝紀元を表示し、`同` で篇藏と録層を `vda` へ保存・再起動で復元する |
| BTRON3 適合 | 互換層（`user/btron/` → 漢令）で第2編 第1章の一部を実装し、QEMU 試験 16 種・670 項目で検証中。1.6 ファイル管理は作成・削除・開閉・レコード操作・ロック・属性・アクセス制御、`cre_prc`（SYS の像ファイル）まで。1.10 の `def_exc`/`ret_exc` は EL0 ハンドラへの同期例外の配送まで実装。適合確認済みの項目は 0 で、完全準拠ではない（[適合性マトリクス](docs/compat/btron3-conformance.md)・[`ER_*` 網羅表](docs/compat/btron3-error-coverage.md)） |
| 実身・仮身／篇藏 | 設計・統合を進める段階。永続化や GUI 統合は未完了 |
| GUI・実機対応 | 今後の段階 |
| 機械漢文ブートローダー・セルフホスティング | 未完了 |
| 独自機械漢文 CPU | AArch64 版とは別の研究トラック |

最新の優先順位・フェーズ・完了条件は [開発ロードマップ](docs/roadmap.md) を参照してください。

## クイックスタート

### 必要なもの

macOS と Homebrew を想定しています。

```sh
brew install llvm lld qemu
```

LLVM ツールは既定で `/opt/homebrew/opt/llvm/bin` と `/opt/homebrew/opt/lld/bin` を参照します。インストール先が異なる場合は `LLVM_BIN` / `LLD_BIN` で上書きしてください。

### ビルドとテスト

```sh
make          # コンパイラ (chokanbun) をビルド
make test     # テストを実行し、カーネル tests/output/kernel.elf も生成
make clean
```

### QEMU で起動

```sh
make test
qemu-system-aarch64 -M virt,gic-version=2 -cpu cortex-a57 -nographic \
  -serial mon:stdio -kernel tests/output/kernel.elf
```

- 起動ログのあと、まず 1 行（例：`KANBUN`）を入力して Enter を押してください。起動時の読込テストで使われます。
- 続いて `殻>` が表示されたら、漢殻の命令を入力できます。
- QEMU を終了するには `Ctrl-A` のあと `X` を押します。

例：

```text
殻> 響 超漢文起動
殻響:超漢文起動
殻> 讀 詩経
殻讀:關關雎鳩、在河之洲
殻> 目
殻目:史記
殻目:詩経
殻> 書 筆記 天地玄黄
殻書 0x000000000000000c
殻> 助
```

現在の漢殻コマンドには `響`・`讀`・`目`・`書`・`削`・`助`・`終` と、外部命令（`問安`・`數` など）があります。詳細は [漢殻コマンド一覧](docs/shell-commands.md) を参照してください。現在のファイル領域は RAM 上のため、再起動すると内容は消えます。

## ソース構成

| パス | 内容 |
|---|---|
| `src/` | 機械漢文コンパイラ（字句解析・構文解析・型検査・LLVM IR 生成） |
| `kernel/` | 漢極（カーネル）。本体 `kernel.mkn` は機械漢文。起動・例外処理などに暫定アセンブリを含む |
| `kernel/vfs/` | 篇藏（ファイル体系。旧称 典籍） |
| `kernel/file/` | BTRON3 ファイル管理の録層（1.6） |
| `kernel/proc/` | 行程の生成・終了、メッセージ、同期、グローバル名、時計、利用者情報 |
| `user/btron/` | BTRON3 互換層（EL0 の C 風 API → 漢令）。`user/btron_*.mkn` は QEMU 上の適合試験 |
| `user/` | 行程として起動する機械漢文製の外部命令と起動補助コード |
| `tools/` | ビルド補助スクリプト |
| `boot/` | 初期段階の起動スタブや参照用コード |
| `tests/` | テストスクリプトと機械漢文のサンプル |
| `docs/` | 言語仕様、ABI、OS設計、漢殻、篇藏、ロードマップ等の文書 |

## テスト

`make test` はコンパイラから AArch64 オブジェクト／ELF の生成、QEMU での実行、カーネルの統合テストを検証します。対象には型エラー診断、起動メッセージ、例外処理、MMU・ページ管理、タイマー割込、EL0 行程・漢令・境界検査、プリエンプション、待機と起床、デマンドページング、UART 入力、篇藏、漢殻の各命令、BTRON3 互換層の適合試験（識試・名試・時試・信試・利試・強試・同試・緩試・録試・貯試・件試・設試・系試・例試・信手試・実試）などが含まれます。適合試験と規範項目の対応は [適合試験計画](docs/compat/btron3-test-plan.md) を、`ER_*` の API 別対応は [`ER_*` 網羅表](docs/compat/btron3-error-coverage.md) を参照してください。

テスト数や PASS 数は実行時の結果を正とし、README に固定値を記載しません。失敗時はログと再現手順を確認してください。

## 設計文書

- [操作マニュアル（試作版）](docs/operation-manual.md)

- [全体構成](docs/architecture.md)
- [機械漢文言語仕様草案](docs/language-spec.md)
- [AArch64 ABI・ブート方針・漢令一覧](docs/abi-aarch64.md)
- [OS 詳細設計 v0.2](docs/detailed-design-v0.2.md)
- [POSIX 互換方針](docs/posix-compat.md)
- [行程・外部命令・パイプ・exec/fork の設計](docs/design-process-exec.md)
- [篇藏 v0.1（ファイル体系）の設計](docs/design-pianfs.md)
- [時刻体系の設計（黄帝紀元・壁時計・単調時計）](docs/design-time.md)
- [漢殻コマンド一覧](docs/shell-commands.md)
- [実装メモ](docs/implementation-notes.md)
- [開発ロードマップ](docs/roadmap.md)
- BTRON3 適合性: [適合性マトリクス](docs/compat/btron3-conformance.md)・[互換層の設計](docs/compat/btron3-compat-layer.md)・[OS 仕様編の照合](docs/compat/btron3-os.md)・[共有データ編](docs/compat/btron3-shared-data.md)・[第2章・第3章の API 棚卸し](docs/compat/btron3-api-inventory.md)・[ファイル管理の設計](docs/compat/btron3-file-design.md)・[適合試験計画](docs/compat/btron3-test-plan.md)・[`ER_*` 網羅表](docs/compat/btron3-error-coverage.md)・[原文の直接確認と食い違い](docs/compat/btron3-spec-verification.md)

## 開発上の約束

1. BTRON3 の規範仕様、超漢文の内部実装、独自拡張を区別する。「完全準拠」は対象仕様の照合とテストが完了してから宣言する。
2. 漢殻は必須 UI とし、GUI の有無にかかわらず診断・保守・基本操作の経路を残す。
3. OS の基本機能と篇藏は LLM に依存させず、決定的なコードと明示的な仕様で実装する。
4. 暫定アセンブリや既存言語によるブートストラップは移行対象として記録し、最終目標と現状を混同しない。
5. `machine-kanbun` とは独立して仕様・実装・Issue を管理する。
6. **機械漢文のソースの拡張子は `.mkn`** とする（カーネル、ユーザー命令、テスト、`@取込` で取り込む部品のすべて）。`.txt` は使わない。生成物（展開後のソース `*_all.mkn` など）も同じ。`make test` が `.txt` のソースの混入を検査する。

## 主な計画

- [Issue #10 — 完全機械漢文 OS 化](https://github.com/kitanou/chokanbun/issues/10)
- [Issue #42 — BTRON3 仕様書 Ver. 3.20.00 への完全準拠](https://github.com/kitanou/chokanbun/issues/42)
- [Issue #46 — 漢殻と実身・仮身モデル](https://github.com/kitanou/chokanbun/issues/46)
- [Issue #47 — 黄帝紀元](https://github.com/kitanou/chokanbun/issues/47)
- [Issue #26 — 独自機械漢文 CPU](https://github.com/kitanou/chokanbun/issues/26)
