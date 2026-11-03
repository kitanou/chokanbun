# BTRON3 OS 仕様編 3.6 データマネージャ

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) / 基準: os_spec/shell/data.html（原文は一部が文字化けで、DBOX_HDR・npos の属性ビットの細部は未確認）
> 実装: `user/btron/data.mkn`。試験: `描試` の `描試二十二`（5 項目）。

## 1. 概要

データボックスは、HMI やアプリが使う静的なデータ（ポインタ・パターン・文字列・パーツ定義・メニュー・パネルなど）を、(データタイプ ID, データ番号) の組で引ける形にまとめたもの。システムデータボックス（OS に 1 つ）とアプリのデータボックス（複数）があり、参照は開いた順、最後にシステムの順で探す。

データタイプ ID: PTR 1・PICT 2・PAT 3・BMAP 4・FIG 5・TEXT 6・PARTS 7・MENU 8・GMENU 9・PANEL 10・USER 64 以降。データ番号 0〜99 はシステム予約。

## 2. 関数（7/7）

| 関数 | 実装 | 誤り |
|---|---|---|
| `dopn_dat(lnk)` | `lnk` が NULL なら 0。ファイルは未対応 | `EX_ADR` `EX_DATA` |
| `dcls_dat(fid)` | `fid` = 0 で登録を全て捨てる | `EX_FD` |
| `dget_dtp(type, dnum, datap)` | 本体の番地を `*datap`（8 B）へ | `EX_ADR` `EX_DNUM` `EX_PAR` |
| `dget_siz(addr)` | 項目のサイズ | `EX_AKEY` |
| `dget_num(addr, type)` | データ番号を返し、`type` が NULL でなければタイプ ID も | `EX_ADR` `EX_AKEY` |
| `ddef_dat(type, dnum, ptr, size)` | 既に登録された項目の置換 | `EX_ADR` `EX_DNUM` `EX_PAR` |
| `ddef_ldt(type, dnum, ptr, size)` | 項目の登録 | `EX_ADR` `EX_PAR` |

`er.mkn` に `EX_DATA`(0x13)・`EX_DFMT`(0x14)・`EX_SDATA`(0x15)・`EX_FD`(0x16)・`EX_AKEY`(0x17) を足した（`EX_DFMT` は `copn_par` が使う。`EX_SDATA` は未使用）。

## 3. 選んだ設計（原文に無い所）

- 登録表は共有画面の塊の後ろ 0x63F80000（+0 項目数、+8 置き場の使用量、+0x100 から 32 B × 255 項目）、本体は 0x63F90000 からの 448 KiB に写す。全行程で共有し、行程の区別は無い。
- 同じ (type, dnum) は新しい登録が先に見つかる。古い本体の番地も有効なまま。置き場が尽きる・255 項目を超えると `EX_NOSPC`（原文に無い誤り）。
- `ptr` と `datap` と `type` の番地は作業領域の窓内を検査（`EX_ADR`）。`type` ≦ 0・`dnum` < 0・`size` ≦ 0 は `EX_PAR`。
- システムデータボックスのファイルが無いので `ddef_dat` が置換できるのは `ddef_ldt` で登録した項目だけ。それ以外は `EX_DNUM`。
- 返った番地は共有メモリなので書き換えない（原文どおり）。

## 4. 利用側

- `copn_par(wid, dnum, pos)`: `PARTS_DATA` の dnum 番（`ccre_par` の PARTS と同じ 32 B 以上、SB は 40 B）から登録する。`pos` が NULL でなければ長方形の左上をそこへ動かす。無ければ `EX_DNUM`、32 B 未満は `EX_DFMT`。
- `mopn_men`・`mopn_gmn`・`popn_pnl`・`pact_err` は **まだ `EX_DNUM`**。`MENU_DATA`・`GMENU_DATA`・`PANEL_DATA` の中身の形式が原文から確認できていないため、登録表は用意したが読む処理は無い。

## 5. 未対応

- ファイルのデータボックス（DBOX_HDR・DNUM_INX・索引・プリロード）、アプリごとのボックスと検索順、システムデータボックスの標準項目（ポインタ・ピクトグラムなど）。
- 行程ごとのローカル項目、プロセス終了での自動クローズ、`PAT_DATA`・`BMAP_DATA` のオフセット→ポインタ変換。
- 標準データ形式（PTR_DATA の構造など）の検査。`EX_DFMT` は `copn_par` の寸法だけ。
