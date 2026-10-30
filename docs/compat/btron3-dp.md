# BTRON3 第2編 第2章 ディスプレイプリミティブ（要求と実装）

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) / 関数の一覧: [btron3-api-inventory.md](btron3-api-inventory.md)
> 基準: BTRON3仕様書 Ver. 3.20.00 第2編 `os_spec/dp/`（`intro`・`basic_concept`・`basic_func`・`figure_func`・`character_func`・`pointer_func`）
> 原文は `charset=iso-2022-jp` で配信され、取得した HTML を `iconv -f ISO-2022-JP -t UTF-8` に通すと読める（共有データ編と同じ）。要約は独自の言い回し。仕様書本文は転載しない。
> 実装: `user/btron/dp.mkn`（EL0 ライブラリ）、試験: 外部命令 `描試`（`user/btron_dp.mkn`、33 項目。引数 `G` は表示装置の試験用）。更新: 2026-10-29。

## 2.1・2.2 の要求（要約）

- 座標系は 16 ビット符号付き整数の平面で、水平は右、垂直は下へ増える。点 `PNT`（H x・y）、長方形 `RECT`（left・top・right・bottom。右と下は含まない＝半開）、`top ≥ bottom` か `left ≥ right` は空。
- ビットマップ `BMP`: UW planes（1〜28）・UH pixbits（上位バイト＝境界ビット数 1〜32、下位バイト＝有効ビット数 1〜28、planes × 有効 ≤ 28）・UH rowbytes（偶数）・RECT bounds（原点は任意。横のピクセル数は 16 の倍数）・baseaddr[planes]。MSB が左上のピクセル。ピクセル値 `PIXVAL` は W で、下位の深さぶんが有効。
- 色 `COLOR`（UW）: 最上位ビット＝透明、crep（ビット 28〜30）＝カラー表現（0＝ピクセル値、1＝RGB 各 8 ビット）、cval（下位 28 ビット）。カラー情報の無い環境では、絶対色も「深さでマスクした値」がピクセル値になる。
- 描画環境 `GID`（W）: 対象デバイス・ビットマップ・カラー情報・マスクピクセル値・フレーム長方形・表示長方形・前置長方形リスト・クリッピング領域・文字属性などを持つ。描画できる領域は bounds ∩ フレーム ∩ 表示 ∩ クリッピング領域から前置リストを除いたもの。種類はデバイス描画環境・メモリ描画環境・汎用メモリ描画環境（`dev = NULL`）。
- 描画モード `DCM`: 下位 8 ビットが演算（STORE・XOR・OR・AND・CPYN・XORN・ORN・ANDN・NOP）、`G_CVFORM` 0x100・`G_CVCOLOR` 0x200・`G_MASK` 0x400・`G_MASKN` 0x800。
- 描画パターン `PAT`: kind 0（spat: 前景・背景・1 ビットのマスク）・1（mpat: ビットマップ）・2（ipat: 内部形式）。標準パターン（`WHITE0` ほか 1〜7 のポインタ値）と標準マスク（`FILL0`〜`FILL100`）。マスクのビット配置は原文では図のみ。
- 関数値は W。エラーは負で、`EG_ADR` ((-64)<<16)・`EG_PAR` (-65)・`EG_NOSPT` (-66)・`EG_NOSPC` (-67)・`EG_GID` (-68)・`EG_LOCK` (-69)・`EG_LIMIT` (-70)・`EG_NOEXS` (-71)・`EG_DEV` (-72)・`EG_ERDEV` (-73)・`EG_FORM` (-80)・`EG_ENV` (-81)。**数値は原文が規定している**（第1章の `ER_*` と違い、実装依存の選択ではない）。

## 実装の方針と選択の記録

- 描画環境は EL0 ライブラリの表（民の窓 `0x407F2000`、256 B × 16 件）。GID は 1〜16。環境を作った行程だけが扱える（他の行程は `EG_GID`）。
- 値渡しの `PNT`・`RECT` は、メモリ上の並びをそのまま 64 ビットの整数にした値（`PNT値`・`RECT値`）。
- 第 1 段階は、プレーン数 1・境界ビット数 1/2/4/8/16/32 の、(a) デバイスなし・カラー情報なしの汎用メモリ描画環境と、(b) デバイス描画環境 `SCREEN`（320×240、32 ビット境界・24 ビット有効の RGB。F7）。ほかは `EG_NOSPT`。

## 関数ごとの状態

| 節 | 関数 | 状態 |
|---|---|---|
| 2.3.1 | `gini_dsp` `gfin_dsp` | 実装済（何もしない） |
| | `gopn_mem` | 実装済（汎用メモリ描画環境のみ。`dev`≠NULL は `EG_NOEXS`、`par`≠NULL は `EG_NOSPT`） |
| | `gcls_env` `gnew_env` `gini_env` | 実装済 |
| | `gopn_dev` `gget_spc` | 実装済（デバイス名 `SCREEN` だけ。`MSGPNL` は `EG_NOEXS`。F7 の表示装置。[../design-display.md](../design-display.md)） |
| | `gfls_dev`（原文に無い、この実装の追加） | 実装済（画面を表示装置へ出す） |
| | `gget_dev` `gget_dsp` `gget_csp` | 実装済（汎用メモリ描画環境は空の名前・`EG_DEV`、`SCREEN` は DEV_SPEC と RGB の CSPEC） |
| | `gloc_env` | 未実装 |
| 2.3.2 | `gcnv_col` | `SCREEN` は RGB 固定カラー方式（近似度 0）、汎用メモリ描画環境は `EG_ENV`。`gset_col` `gget_col` `gset_bcs` `gget_bcs` は未実装 |
| 2.3.3 | `gset_msk` `gget_msk` `gget_fra` `gset_fra` `gget_vis` `gset_vis` `gget_bmp` `gget_bnd` `gmov_bnd` `gmov_cor` | 実装済 |
| | `gget_clp` `gset_clp` | 部分（クリッピング領域は常に未定義。非 NULL の設定は `EG_NOSPT`） |
| | `gget_for` `gset_for` `gsiz_pat` `gcre_pat` `gset_lmk` `gget_lmk` | 未実装 |
| 2.3.4 | `gcnv_abs` `gcnv_rel` | 実装済 |
| 2.4 | `gdra_pnt` `gtst_pnt` | 実装済（全描画モード、マスクピクセル指定） |
| | `gfil_rec` `gfil_pnt` | 部分（回転なし。パターンは `WHITE0`・`BLACK100` と、`FILL0`・`FILL100` を使う spat だけ） |
| | `gfra_rec` | 部分（回転なし。線属性は実線のみ＝線種 T が 0 以外は `EG_NOSPT`。太さは内側へ、はみ出す太さは全面、0 は描かない） |
| | `gcop_bmp` | 部分（拡大縮小と mask は `EG_NOSPT`。形式違いは `EG_FORM`、`G_CVFORM` があれば小さいほうの深さの下位ビットを写す。重なる転送は向きを選ぶ。カラー変換は未対応＝カラー情報なし） |
| | 上記以外の 2.4 の関数（約 36） | 未実装 |
| 2.5 | 文字（列）描画 20 関数 | **一部済 18 関数**（`user/btron/dpchr.mkn`）: `gset_chp`・`gget_chp`・`gset_chc`・`gget_chc`・`gget_chw`・`gget_chh`・`gget_stw`・`gget_sth`・`gdra_chr`・`gdra_chp`・`gdra_str`・`gdra_stp`・`gset_chd`・`gget_chd`・`gset_scr`・`gget_scr`・`gget_str`・`gcop_chr`。フォントは自作の固定幅 8×8 の ASCII（`tools/gen-font5x7.py` が生成。外部のフォントは使わない）。全角（A ゾーンなど）は幅 16 の枠線だけ。制御コードと言語指定コード（0xFE00 以上）は幅 0。文字描画方向は横書き・文字間隔 0 だけで、`gap` は NULL だけ（指定すると `EG_NOSPT`）。`gset_chd` は横書き (0) だけ、`gget_chd` の gap は `EG_NOSPT`。SCRIPT は 0〜0xFFFF を保持するだけ。`gcop_chr` の SIZE は値渡しで h | v<<16、左上を文字描画位置に最近傍で拡大縮小。未実装: `gset_fon`・`gget_fon` (FSSPEC・FNTINFO の構造が未確認) |
| 2.6 | ポインタ制御 6 関数 | 未実装 |

## 未了と次の段階

- 回転角を持つ長方形・角丸・楕円・弧・多角形・曲線・ビットマップ操作（`gcop_bmp` ほか）。線属性・線種・線パターン。
- パターンマスクのビット配置（原文は図 29 のみ）を図で確認し、標準パターン 12.5%〜87.5% と利用者のマスク・mpat を実装する。
- カラー情報つきの汎用メモリ描画環境（CSPEC）、カラーマップ、`gcnv_col`。
- クリッピング領域（任意領域 `GRGN`）と前置長方形リスト。複数プレーン。
- 実際の画面（virtio-gpu・ramfb）への出力とデバイス描画環境（`SCREEN`・`MSGPNL`）は F7。
