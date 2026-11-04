# BTRON3 OS 仕様編 3.9 フォントマネージャ

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) / 基準: os_spec/shell/font_mgr.html
> 実装: `user/btron/font.mkn`。試験: `描試` の `描試二十五`（10 項目）。

## 1. 概要

メモリ上のフォントデータ（FDEF）を登録し、アプリが開く「フォントセット」（書体名・クラス・属性・大きさ・角度）に合うフォントから文字情報と字像を引く。原文の取得結果は ISO-2022-JP のため説明文を読み切れず、関数の原型・定数・構造体の欄名から実装した。

## 2. 関数（14/14）

| 関数 | 実装 | 誤り |
|---|---|---|
| `fdef_fnt(loc, spec)` | メモリ上の FDEF を登録して ID（0 始まり）を返す。同じ番地・同じ書体は同じ ID。最大 16 個 | `EX_PAR` `EX_FONT`（`FT_FILE`）`EX_ADR` `EX_FTFMT` `EX_LIMIT` |
| `fdel_fnt(fid)` | 削除。`fid` < 0 でシステムフォント以外を全部削除。システムフォントは消えない | `EX_FTID` |
| `fdel_loc(loc, spec)` | 番地で登録したものを削除し、削除件数を返す | `EX_PAR` `EX_ADR` |
| `fget_def(fid, def)` | FDEF を写す（`offimage`・`offwidth`・`offnote` は 0） | `EX_FTID` `EX_ADR` |
| `fget_not(fid, buff, len)` | 注を TC で写し、注の長さを返す（`buff` = NULL か `len` = 0 は長さだけ） | `EX_FTID` `EX_PAR` `EX_ADR` |
| `flst_fon(fid, mode, buff, len)` | `FT_FONT` `FT_SCALL` `FT_SCFAMILY` `FT_LOC` `FT_ALL` `FT_FAMILY` の件数を返し、`len` 件まで FLIST を書く | `EX_FTID` `EX_PAR` `EX_ADR` |
| `fopn_fon()` / `fcls_fon(fdesc)` | フォントセットを 8 個まで開く／閉じる。既定は書体名なし・`FTC_DEFAULT`・16×16・角度 0 | `EX_NOMEM` / `EX_FTD` |
| `fset_fon` / `fget_fon` | FSSPEC を設定／取得。大きさが 0 以下は `EX_PAR` | `EX_FTD` `EX_ADR` `EX_PAR` |
| `fset_ang` / `fget_ang` | 角度 0〜359 | `EX_FTD` `EX_PAR` |
| `fget_fam(fdesc, script, inf)` | 文字セットに合うフォントの情報を、フォントセットの大きさに拡縮して返す（関数値はフォント ID）。無ければ `EX_FTID` だが `inf` は有効な値で埋める | `EX_FTD` `EX_ADR` `EX_FTID` |
| `fget_img(fdesc, cimg, size, script, ch, mode)` | 字の幅・高さと、`FT_IMAGE` なら字像。常に 1 を返す。定義外の字・文字セットなしはエラーにせず未定義字像（family = 0xFFFF） | `EX_FTD` `EX_PAR` `EX_ADR` `EX_NOSPC` |

`er.mkn` に `EX_FONT`(0x1D)・`EX_FTFMT`(0x1E)・`EX_FTID`(0x1F)・`EX_FTD`(0x20)・`EX_NOMEM`(0x21) を足した。

## 3. 選んだ設計（原文に無い所）

- 値が原文に無い定数: `FT_MEM`=1・`FT_FILE`=2・`FT_RES`=0x100・`FT_SYSTEM`=0x200（`fdef_fnt` の spec）、`FT_IMAGE`=1・`FT_SYS`=2（`fget_img` の mode）。
- FDEF は原文 3.9.1.3 の版で 136 B（欄の位置は `font.mkn` 冒頭）。字像は `imgform`=0（固定イメージサイズのドット）、幅は `widform`=0（H の表、`offwidth`=0 なら最大幅）だけ。他は `EX_FTFMT`。FLIST 48 B、FSSPEC 36 B、FDATA 40 B、FNTINFO 16 B と定めた。
- 書体の選び方は、名称が同じなら 3 点・クラスが同じなら 2 点・文字セットだけ同じなら 1 点で、最高点（同点なら先に登録した方）。原文の 12 段階の探索は実装していない。
- 字像は拡縮しない（`fget_fam` の寸法だけ `sheight`・`swidth` を基準に拡縮する）。`FT_SYS` なしでは字像を `cimg` の直後（`cimg` + 40）に写す（窓内に収まらなければ `EX_NOSPC`）。`FT_SYS` なら本体の字像を直接指す。
- 表は共有画面の塊の後ろ 0x63FFD000（フォント 16 個、フォントセット 8 個）。フォント ID は全行程で共有、フォントセットはオープンした行程だけ有効。

## 4. 未対応

- ファイルのフォント（`FT_FILE`）、可変イメージサイズ・アウトライン・TrueType、グレースケール、ベクトル字像、`widform` 1・2、12 段階の書体探索、角度による字像の回転、`gset_fon`/`gget_fon`（2.5）との接続。
- `fget_not` / `fget_def` / `fget_fam` の戻り値は原文の該当行が読めなかった（コピー誤りらしい記述を含む）ので、上記は推定。
