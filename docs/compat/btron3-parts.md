# BTRON3 OS 仕様編 第3章 3.3 パーツマネージャ — 要求の整理（F4・F7）

> 出典: BTRON3 仕様書 Ver. 3.20.00 第2編 第3章 3.3（`os_spec/shell/parts.html`、33 関数・11 種のパーツ）。更新: 2026-11-01。
> 状況: **要求抽出のみ。未実装**。原文は漢字切替列の ESC が欠けた形で取得され、手作業で復号した。**(推定)** は読みが確定していない箇所。図 79〜95 は画像で未確認。本文は転載せず独自の言い回しで要約する。

## 1. 位置づけ

- HMI の部品（パーツ）の表示と操作を担う。パーツは 1 つのウィンドウかパネルに属して登録される。登録は、定義構造体を渡す `ccre_*` か、データマネージャの `PARTS_DATA` を番号で指す `copn_par`。
- パーツ ID（`PAID`、正の `W`）は**行程グローバル**で、他行程からも操作できる（メニューやパネルの ID は行程ローカル）。所属ウィンドウ／パネルの削除、または登録行程の終了で自動削除される。文字列などの参照先がプロセスローカルなら他行程からは使えない。
- 型と属性は登録後に変更できない。状態（表示・点滅・入力可否・操作許可・枠・強調）は後から変えられる。表示領域 `r` は所属ウィンドウ／パネルの相対座標。
- パネル（3.4）の `PARTS_ITEM` と、`pact_pnl` が呼ぶ `cact_par` の相手。つまり 3.4 の実用的な実装にはパーツが要る。

## 2. パーツの種類（11）

| 型 | 定数 | 名称 | 要点 |
|---|---|---|---|
| 1 | `TB_PARTS` | テキストボックス | 1 行文字列の表示と編集。ドラッグで選択。`P_APPEND` で既定の選択位置が変わる |
| 2 | `XB_PARTS` | シークレットテキストボックス | `TB` と同機能で、内容を読めない形で表示 |
| 3 | `NB_PARTS` | 数値ボックス | 数値の表示と入力。`fmt` で桁・小数点・ゼロ表示 |
| 4 | `SB_PARTS` | シリアルボックス | `fmt` 文字列で複数フィールドを定義し、各フィールドを数値または選択肢で編集 |
| 5 | `AS_PARTS` | テキストオルタネートスイッチ | 名称と ON/OFF。クリックで反転 |
| 6 | `MS_PARTS` | テキストモメンタリスイッチ | 名称のみ。押している間だけ反応し、状態は持たない |
| 7 | `PA_PARTS` | ピクトグラムオルタネート | ON/OFF 用の 2 つの `BMAP_DATA` を切り替え |
| 8 | `PM_PARTS` | ピクトグラムモメンタリ | 1 つの `BMAP_DATA`（`offpat` 未使用） |
| 9 | `WS_PARTS` | スイッチセレクタ | 複数の選択肢から 1 つ（`P_NOSEL` なら 0 個も可） |
| 10 | `SS_PARTS` | スクロールセレクタ | `WS` と同様で、選択肢が多いとスクロール。`P_NUMBER` で番号付け |
| 11 | `VL_PARTS` | ボリューム | スライダ。`clo`/`chi`（現在値）、`lo`/`hi`（全体）。`P_HALIGN` で縦横、`P_SBAR` でスクロールバー化 |

## 3. データ型

| 名 | 内容 |
|---|---|
| `PARTDISP` | 表示属性 `frpat`（枠／下線パターン）・`bgpat`（背景、0 は既定）・`chcol`（文字色、負は既定）・`misc`（カーソルと選択部の色 (推定)） |
| `TEXTBOX` | `type`・`r`・`txsize`（最大文字数。`TNULL` を含み、上限は実装依存で 80 文字以上）・`text`・`atr` |
| `NUMBOX` | `type`・`r`・`fmt`・`cv`（整数 `l` か実数 `d` の共用体）・`atr` |
| `SERBOX` | `type`・`r`・`fmt`（`TC*`）・`nfld`・`cv`（`W*`）・`atr` |
| `SWSEL` | `type`・`r`・`cv`・`name`・`atr`（`AS`/`MS`/`WS`/`SS` で共用） |
| `PICTSW` | `type`・`r`・`cv`・`onpat`・`offpat`・`atr` |
| `VOLUME` | `type`・`r`・`clo`・`chi`・`lo`・`hi`・`patnum`・`atr` |
| `PARTS` | 上の共用体 |
| `type` | 下位 5 ビットが型（`P_TYPE` = 0x001f）、以降が属性・状態ビット |

数値ボックスの `fmt`: 桁数・整数／実数・小数以下の桁数（0〜15）・末尾ゼロ表示・全角／半角など。シリアルボックスの `fmt` は、数値フィールド（`0000 11ZA SSSS SSSS` に最小値・最大値が続く）、項目フィールド（`0000 1000 SSSS SSSS`）、終了コード（全ビット 0）の列。

## 4. 定数

| 区分 | 定数（値） |
|---|---|
| 属性 | `P_HALIGN` 0x0020、型ごとに別意味のもの: 0x0040（`P_PRESS`/`P_NUMBER`/`P_DOUBLE`/`P_SBAR`）、0x0080（`P_DCLICK`/`P_NOSEL`/`P_APPEND`/`P_NONOB`）。`P_EMPHAS` 0x0200、`P_NOFRAME` 0x0400、`P_DISABLE` 0x0800、`P_INACT` 0x1000、`P_BLINK` 0x2000、`P_DISP` 0x4000、`P_PARTDISP` 0x8000 |
| 文字属性 | `MC_STR` 0x1000、`MC_FIG` 0x1001、`MC_ATTR` 0x1002、`MC_EMPHAS` 0x1400、`MC_INACT` 0x1800、`MC_SFLD` 0x0800、`MC_NFLD` 0x0c00、`MC_NZERO` 0x0200、`MC_NLEFT` 0x0100（3.2 の `MC_*` と数値が異なるので要確認） |
| 数値 | `P_LNUM` 0、`P_DNUM` 0x0080、`P_FIX1` 0x0010 (推定)、`S_UNDEF` 0x8000、`L_UNDEF` 0x80000000、`D_UNDEF` 1.797693e308（注釈は NaN で不整合） |
| 終了コード | `P_CHANGE` 0x1000、`P_BREAK` 0x2000、`P_SMASK` 0x0fff、`P_MENU` 0x6010、`P_EVENT` 0x6020。戻り値の形は `01PC SSSS SSSS SSSS`（0x4000 + 中断 + 変化 + 終了理由） |
| クリック・理由 | `P_SGL` 1・`P_DBL` 2。終了理由 `P_TAB` 0・`P_NL` 1・`P_END` 2・`P_BUT` 3・`P_MOVE` 4・`P_COPY` 5。方向 `P_UP` 0・`P_DOWN` 1。移動 `P_SMOOTH` 0・`P_AREA` 4・`P_JUMP` 8 |
| 表示制御（`cdsp_par`） | `P_ERASE` 0、`P_NODISP` 0x1000、`P_RDISP` 0x8000（ほか `P_DISP`・`P_BLINK`） |
| 状態変更（`cchg_par`） | `P_NORMAL` 2・`P_FRAME` 4・`P_ENABLE` 8・`P_ACT` 0x10。対の `P_EMPHAS`・`P_NOFRAME`・`P_DISABLE`・`P_INACT` と、組ごとに 1 つずつ OR |

## 5. 関数（33）

共通: 戻り値は正常で 0 以上、エラーで負。エラーは `EX_*`。

| 群 | 関数 | 要点 | エラー |
|---|---|---|---|
| 登録 | `ccre_par(wid, PARTS*)` | 定義から登録。表示状態なら表示、消去状態なら登録のみ | `EX_ADR` `EX_NOSPC` `EX_PAR` `EX_WID` `EX_DNUM` |
| | `ccre_tbx`・`ccre_xbx`・`ccre_nbx`・`ccre_sbx`・`ccre_asw`・`ccre_msw`・`ccre_pas`・`ccre_pms`・`ccre_sel`・`ccre_scr`・`ccre_vol` | 種類別の登録（11）。引数 `ty` は無視され型は関数で固定 | 原文に節なし |
| | `copn_par(wid, dnum, PNT*)` | `PARTS_DATA` から登録。`pos` が NULL なら定義内の位置 | `EX_ADR` `EX_DNUM` `EX_NOSPC` `EX_PAR` `EX_WID` |
| 削除 | `cdel_par(pid, opt)` | 1 つ削除。`opt` は 0（表示を消す）か 0 以外（残す） | `EX_PID` |
| | `cdel_pwd(wid, opt)` | 窓内の全パーツ。`P_SBAR` のボリュームは除く | `EX_WID` |
| 表示 | `cdsp_par(pid, vis)` | 消去・表示・点滅・再表示 | `EX_PAR` `EX_PID` |
| | `cdsp_pwd(wid, RECT*, vis)` | 矩形内の全パーツ。NULL は全域。`P_SBAR` は除く | `EX_ADR` `EX_PAR` `EX_WID` |
| 検索 | `cchk_par(pid, pos)` | 点がパーツ内なら型コード（1〜11）、外は 0。`P_DISABLE` や非表示は常に 0 | `EX_PID` |
| | `cfnd_par(wid, pos, pid*)` | 登録順に点位置のパーツを探す。`P_DISABLE`・非表示・`P_SBAR` は除く | `EX_ADR` `EX_WID` |
| 操作 | `cact_par(pid, WEVENT*)` | 入力イベントに対する操作を始める。対象外・操作不可・非入力状態は何もせず 0。中断時は 01PC 形式を返し、`ev` を `EV_NULL` にして再呼出し | `EX_ADR` `EX_PID` |
| | `cexe_par(pid, WEVENT*)` | 1 イベントだけ処理する版。`wget_evt` の結果を渡す。`P_EVENT` 時の扱いは `cact_par` と同様 (推定) | `EX_ADR` `EX_PID` |
| 値 | `cget_val(pid, size, W*)` | 現在値の取得。`TB`/`XB` は文字列、`NB` は整数か実数、`SB` は `cv` 列、`SS` は [cv, 表示数, 先頭番号]、`VL` は `clo`・`chi`・`lo`・`hi`、`MS` は 0。戻り値は格納したワード数 | `EX_ADR` `EX_PID` |
| | `cset_val(pid, size, W*)` | 現在値の設定。表示中なら再描画。`SS` は可視範囲へスクロール | `EX_ADR` `EX_PAR` `EX_PID` |
| 定義 | `cget_dat(pid, W*)` | 定義データ（`txsize`・`fmt`・`name`・`onpat`/`offpat`・`patnum`）の取得 | 原文に節なし |
| | `cset_dat(pid, W)` | 定義データの設定。`SB` の項目数が変わると `EX_PAR` で不変。引数の型が説明と食い違う | `EX_DNUM` `EX_PAR` `EX_PID` |
| 文字列 | `ccut_txt(pid, size, buff, cut)` | `TB`/`XB` の選択範囲を取得。`cut` ≠ 0 なら削除。`buff` が NULL なら長さのみ | `EX_ADR` `EX_PAR` `EX_PID` |
| | `cins_txt(pid, pos, buff)` | 位置に挿入し、挿入部が選択状態になる。`txsize` 超過は切り捨て (推定) | `EX_ADR` `EX_PAR` `EX_PID` |
| 位置・状態 | `cget_pos`・`cset_pos(pid, RECT*)` | 表示矩形の取得・設定。設定は新旧の領域を再描画 | `EX_ADR` `EX_PAR` `EX_PID` |
| | `cget_sts(pid, wid*)` | 型・属性・状態ワードと所属 ID | `EX_ADR` `EX_PID` |
| | `cchg_par(pid, cmd)` | 状態変更（対の同時指定は `EX_PAR`） | `EX_PAR` `EX_PID` |
| | `cchg_pwd(wid, cmd)` | 窓内の全パーツ。`P_SBAR` のボリュームは除く | `EX_PAR` `EX_WID` |
| 定常 | `cidl_par(wid, pos*)` | 点滅やポインタ形状などの定常処理。`P_SBAR` も対象 | `EX_ADR` `EX_WID` |

## 6. 未確認・未解決

- `ccre_*` 11 関数と `cget_dat` のエラー欄が空。`ccut_txt` の `cut` = 0 の説明、`P_COPY`・`P_DOWN` の注記の末尾、`cget_val` の `size` = 2 の説明が欠落。
- `D_UNDEF` の値と注記の不整合。`ccre_nbx` の `W *val` と `NUMBOX.cv`（共用体）の不一致。`cset_dat` の `W par` が `PA_PARTS` では `W*` という説明。型ごとに 0x0040・0x0080・0x8000 が別の意味を持つので、読み誤りに注意。
- `MC_*` の値が 3.2 と食い違う（3.2 は `MC_IND` 0x1100 など）。どちらの章でも原文の確認が要る。
- 図 79〜95。`PARTS_DATA`・`PAT_DATA`・`BMAP_DATA`（3.6・共有データ編）の形式。`EX_PID`・`EX_WID` ほかの数値（`er.mkn` に未定義）。

## 7. 実装に向けた依存

- 描画は 2.4・2.5、入力は 1.7 と 3.1 の `wget_evt`。`cact_par`・`cexe_par` は `wget_evt` の結果を受けるので、3.1 のイベントは実装済みで足りる。
- 最小の実装は、`ccre_msw`・`ccre_asw`（文字のスイッチ）、`cdel_par`、`cdsp_par`、`cchk_par`・`cfnd_par`、`cact_par`（押下の検出）。次いでテキストボックスと数値ボックス。3.4 パネルの `PARTS_ITEM` はこれに依存する。
- 現状: 未実装（0/33 関数）。
