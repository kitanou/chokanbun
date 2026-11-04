# BTRON3 OS 仕様編 3.11 印刷マネージャ

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) / 基準: os_spec/shell/printmgr.html
> 実装: `user/btron/prn.mkn`。試験: `描試` の `描試二十七`（5 項目）。

## 関数（9/9）

| 関数 | 実装 | 誤り |
|---|---|---|
| `rset_cnf(prname, cnf)` | `cnf`=NULL で登録削除、=1 で先頭へ移動、他は構成の変更。`prname`=NULL なら末尾に追加。最大 8 | `EX_ADR` `EX_NOEXS` `EX_EXS`（印刷登録あり）`EX_PAR`（名前が空・重複）`EX_LIMIT` |
| `rget_cnf(prname, cnf)` | 構成を写す（`prname`=NULL は先頭のプリンタ）。関数値は原文どおり最大登録数（8） | `EX_ADR` `EX_NOEXS` |
| `rlst_prn(info, cnt)` | PR_INFO（120 B）を `cnt` 件まで書き、登録数を返す | `EX_ADR` `EX_PAR` |
| `rprn_fil(prname, lnk, prpar, mode)` | 印刷登録（最大 28）を `PR_WAIT` で積み、prid（1 から）を返す | `EX_ADR` `EX_NOEXS` `EX_PAR`（mode）`EX_LIMIT` |
| `rcan_ent(prname, prid)` | prid=0 は全件（`prname`=NULL は全プリンタ）、他は 1 件を取り消して件数を返す | `EX_ADR` `EX_NOEXS` `EX_PAR` |
| `rget_ent(prname, prid, stat, cnt)` | PR_STAT（72 B）を `cnt` 件まで書き、件数を返す（全て NULL/0 なら総数） | `EX_ADR` `EX_NOEXS` `EX_PAR` |
| `rset_par(prname, prpar, fout)` | 利用者の操作を待たず `PR_SET`。名前が空・未登録なら先頭のプリンタ名に置き換える | `EX_ADR` `EX_NOEXS` |
| `rout_fil` / `rpvw_fil` | 引数とプリンタの検査の後 `EX_NOSPT`（TAD の割付けと画面が無い） | `EX_ADR` `EX_NOEXS` `EX_NOSPT` |

## 選んだ設計・未対応

- 印刷する装置が無いので登録は `PR_WAIT` のまま残る。`PR_DEL` でのファイル削除、終了メッセージ（`PR_MESG`）、`time` は未対応。
- 構造体の大きさは欄の並びから決めた（PR_CONF 408 B、`L_DEVNM`・`L_FNM` は原文に値が無く 20）。表は共有画面の塊の後ろ 0x63FFE400〜（レイアウトは `prn.mkn` 冒頭）。
- 原文の `rget_cnf` の関数値の記述と `prname`=NULL の場合は文が欠けていたので推定。
