# BTRON3 第2編 第2章・第3章 API 一覧（棚卸し）

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) / 全体表: [btron3-conformance.md](btron3-conformance.md)
> 基準: BTRON3仕様書 Ver. 3.20.00 第2編 `os_spec/dp/`・`os_spec/shell/`
> 作成: 2026-10-17。Phase 0 の「全章・全節の API を一覧化する」の第2章・第3章分。

## 読む前の注意

- 各ページの**関数見出しを抜き出しただけ**で、引数・戻り値・エラー条件は未抽出。要約は独自の言い回し。仕様書本文は転載しない。
- 取得時に原文の日本語が文字化けし、一部ページは長さで切れていた。**件数は ±数件の誤差があり得る**。確定は原文ページの直接確認で行う（`parts`・`omgr` は後半を追加取得済み、`menu`・`panel`・`tip` は末尾の欠落があり得る）。
- 現状の実装: 第2章の**要求の抽出と第 1 段階の実装**が済み（[btron3-dp.md](btron3-dp.md)。汎用メモリ描画環境と点・長方形の描画。`描試` 33 項目）。第3章は未着手。表示装置・入力装置・GUI は未着手（F7）。下の表の「状態」は、btron3-dp.md の関数ごとの表が正本。依存関係は下の「前提」を参照。
- 第3.8 節の関数は「仮身（virtual object）」を単位とする。実身・仮身モデルの扱いは Issue #46 と [btron3-file-design.md](btron3-file-design.md) に従う。

## 件数

| 章 | 節 | ページ | 関数数 | 状態 |
|---|---|---|---|---|
| 2 ディスプレイプリミティブ | 2.3 基本関数（描画環境・色・クリップ・座標） | dp/basic_func | 37 | 未実装 |
| | 2.4 図形描画関数 | dp/figure_func | 42 | 未実装 |
| | 2.5 文字（列）描画関数 | dp/character_func | 20 | 未実装 |
| | 2.6 ポインタ制御関数 | dp/pointer_func | 6 | 未実装 |
| | 2.1 概要・2.2 基本概念 | dp/intro, basic_concept | （関数なし。データ型・概念） | 未調査 |
| 3 外殻（シェル） | 3.1 ウィンドウマネージャ | shell/window | 51 | 未実装 |
| | 3.2 メニューマネージャ | shell/menu | 15 | 未実装 |
| | 3.3 パーツマネージャ | shell/parts | 33 | 未実装 |
| | 3.4 パネルマネージャ | shell/panel | 12 | 未実装 |
| | 3.5 トレーマネージャ | shell/tray | 10 | 未実装 |
| | 3.6 データマネージャ | shell/data | 7 | 未実装 |
| | 3.7 テキスト入力プリミティブ | shell/tip | 8 | 未実装 |
| | 3.8 実身／仮身マネージャ（仮身・実身） | shell/omgr | 60 | 未実装 |
| | 3.9 フォントマネージャ | shell/font_mgr | 14 | 未実装 |
| | 3.10 TCP/IP マネージャ | shell/tcpip | 28 | 未実装 |
| | 3.11 印刷マネージャ | shell/printmgr | 9 | 未実装 |
| **合計** | | | **約 352** | |

## 第2章 ディスプレイプリミティブ

### 2.3 基本関数（37）

| 群 | 関数 |
|---|---|
| 初期化・終了 | `gini_dsp` `gfin_dsp` |
| 描画環境の生成・破棄・複製・初期化・排他 | `gopn_dev` `gopn_mem` `gnew_env` `gini_env` `gcls_env` `gloc_env` |
| 装置情報 | `gget_spc` `gget_dev` `gget_dsp` |
| 色 | `gget_csp` `gset_bcs` `gget_bcs` `gset_col` `gget_col` `gcnv_col` `gset_msk` `gget_msk` |
| クリップ・枠・可視・前景 | `gget_clp` `gset_clp` `gget_fra` `gset_fra` `gget_vis` `gset_vis` `gget_for` `gset_for` |
| パターン・線マスク | `gsiz_pat` `gcre_pat` `gset_lmk` `gget_lmk` |
| ビットマップ・座標 | `gget_bmp` `gget_bnd` `gmov_bnd` `gmov_cor` `gcnv_abs` `gcnv_rel` |

### 2.4 図形描画関数（42）

| 群 | 関数 |
|---|---|
| 点・線 | `gdra_pnt` `gtst_pnt` `gfil_pnt` `gdra_lin` `gdra_pln` |
| 矩形・角丸・楕円 | `gfra_rec` `gfil_rec` `gfra_rrc` `gfil_rrc` `gfra_ovl` `gfil_ovl` |
| 弧・扇・弓 | `gdra_arc` `gfra_sec` `gfil_sec` `gfra_cho` `gfil_cho` |
| 多角形・領域・曲線 | `gfra_pol` `gfil_pol` `gfil_gen` `gfil_rgn` `gdra_spl` `gfil_spl` |
| ビットマップ操作 | `gcop_bmp` `gsav_bmp` `grst_bmp` `grst_mbm` `grot_bmp` `gscr_rec` `gsiz_cbm` `gcom_bmp` `gunc_bmp` |
| 点の包含判定 | `gpic_lin` `gpic_rec` `gpic_rrc` `gpic_ovl` `gpic_arc` `gpic_sec` `gpic_cho` `gpic_pln` `gpic_pol` `gpic_gen` `gpic_spl` |

### 2.5 文字（列）描画関数（20）

`gset_chp` `gget_chp` `gset_chc` `gget_chc` `gset_chd` `gget_chd` `gset_fon` `gget_fon` `gset_scr` `gget_scr` `gget_chw` `gget_chh` `gget_stw` `gget_sth` `gget_str` `gdra_chr` `gdra_chp` `gdra_str` `gdra_stp` `gcop_chr`

### 2.6 ポインタ制御関数（6）

`gini_ptr` `gdsp_ptr` `gset_ptr` `gmov_ptr` `gmot_ptr` `gget_ptr`

## 第3章 シェル

### 3.1 ウィンドウマネージャ（51）

| 群 | 関数 |
|---|---|
| 生成・破棄・状態 | `wopn_wnd` `wopn_iwd` `wopn_pwd` `wcls_wnd` `wchg_wnd` `wchg_ful` `wswi_wnd` |
| 移動・大きさ・スクロール | `wmov_wnd` `wmov_drg` `wrsz_wnd` `wrsz_drg` `wscr_wnd` |
| 再描画 | `wsta_dsp` `wend_dsp` `wchk_dsp` `wreq_dsp` `wera_wnd` |
| ドラッグ | `wsta_drg` `wend_drg` `wget_drg` |
| イベント | `wget_evt` `wugt_evt` `wpas_evt` `wsnd_evt` `wrsp_evt` `wwai_rsp` `wchk_dck` `wchg_dck` `wdef_fep` |
| 検索・一覧 | `wfnd_wnd` `wget_act` `wlst_wnd` |
| 属性の取得・設定 | `wget_tit` `wset_tit` `wget_sts` `wget_gid` `wset_bgp` `wget_bgp` `wchg_dsp` `wget_bar` `wget_dat` `wset_dat` `wget_wrk` `wset_wrk` `wget_org` `wset_org` `wcnv_rec` `wget_inf` `wset_inf` |
| 表示メニュー | `wget_dmn` `wexe_dmn` |

### 3.2 メニューマネージャ（15）

`mcre_men` `mopn_men` `mdel_men` `msel_men` `mfnd_key` `mget_itm` `mset_itm` `mchg_atr` `mchg_dsp` `mcre_gmn` `mopn_gmn` `mdel_gmn` `msel_gmn` `mchg_gat` `mchg_dtm`

### 3.3 パーツマネージャ（33）

`ccre_par` `ccre_tbx` `ccre_xbx` `ccre_nbx` `ccre_sbx` `ccre_asw` `ccre_msw` `ccre_pas` `ccre_pms` `ccre_sel` `ccre_scr` `ccre_vol` `copn_par` `cdel_par` `cdel_pwd` `cdsp_par` `cdsp_pwd` `cchk_par` `cfnd_par` `cact_par` `cget_val` `cset_val` `cget_dat` `cset_dat` `ccut_txt` `cins_txt` `cget_pos` `cset_pos` `cget_sts` `cchg_par` `cchg_pwd` `cidl_par` `cexe_par`

### 3.4 パネルマネージャ（12）

`pcre_pnl` `popn_pnl` `pdel_pnl` `pact_pnl` `pget_itm` `pset_itm` `psel_box` `pget_gid` `pact_err` `pdsp_msg` `pdsp_tim` `pact_msg`

### 3.5 トレーマネージャ（10）

`topn_tra` `tcls_tra` `tpsh_dat` `tpop_dat` `tdel_dat` `tsel_dat` `tmov_dat` `tget_sts` `tset_dat` `tget_dat`

### 3.6 データマネージャ（7）

`dopn_dat` `dcls_dat` `dget_dtp` `dget_siz` `dget_num` `ddef_dat` `ddef_ldt`

### 3.7 テキスト入力プリミティブ（8）

`ichg_mod` `ichg_lrn` `iopn_tip` `icls_tip` `iput_key` `iput_str` `ichg_blk` `idsp_car`

### 3.8 実身／仮身マネージャ（60）

| 群 | 関数 |
|---|---|
| 仮身の登録・複製・削除・表示 | `oreg_vob` `odup_vob`（原文の綴りは `b_odup_vob` と取得され、要確認） `odel_vob` `ocls_wnd` `odsp_vob` `odsp_vor` `odra_vob` `odra_vor` `ofnd_vob` `omov_vob` `orsz_vob` |
| 仮身の属性 | `ochg_chs` `ochg_col` `ochg_nam` `ochg_rel` `oget_vob` `ochg_sts` `ochg_env` `oget_env` |
| 実身・オブジェクト | `onew_obj` `ocre_obj` `oopn_obj` `odel_obj` `ocre_chd` `ocnv_vob` `otad_vob` `oget_fsn` `oput_fsn` `oput_dat` `oupd_fil` |
| 処理の開始・終了・要求 | `osta_prc` `oend_prc` `oend_req` `oreq_prc` `orsp_prc` |
| メニュー | `oset_tmf` `oget_men` `oget_vmn` `oexe_vmn` `apnl_men` |
| アプリケーション | `oreg_apg` `odel_apg` `ofnd_apg` `oexe_apg` |
| ファイルシステム・装置 | `oset_sea` `oget_sea` `oatt_fls` `ofat_fls` `odet_fls` `ofdt_fls` `oatt_vob` `odet_vob` `oprc_dev` `ofmt_vob` `odsp_inf` `odsk_inf` |
| 選択表示 | `aset_sel` `adsp_sel` `adsp_slt` `achg_bgc` |

### 3.9 フォントマネージャ（14）

`fdef_fnt` `fdel_fnt` `fdel_loc` `fget_def` `fget_not` `flst_fon` `fopn_fon` `fcls_fon` `fset_fon` `fget_fon` `fset_ang` `fget_ang` `fget_fam` `fget_img`

### 3.10 TCP/IP マネージャ（28）

`so_start` `so_finish` `so_socket` `so_bind` `so_listen` `so_accept` `so_connect` `so_close` `so_shutdown` `so_read` `so_write` `so_recv` `so_recvfrom` `so_recvmsg` `so_send` `so_sendto` `so_sendmsg` `so_select` `so_fcntl` `so_ioctl` `so_getsockopt` `so_setsockopt` `so_getsockname` `so_getpeername` `so_gethostbyname` `so_gethostbyaddr` `so_gethostname` `so_sethostname`

### 3.11 印刷マネージャ（9）

`rset_par` `rprn_fil` `rout_fil` `rpvw_fil` `rcan_ent` `rget_ent` `rlst_prn` `rget_cnf` `rset_cnf`

## 前提と依存（実装順の手がかり）

1. **表示装置**: 第2章は描画環境（`gopn_dev`）が土台。QEMU `virt` の framebuffer（ramfb／virtio-gpu）が前提で、F7（GUI）の項目。
2. **入力**: 3.1 のイベント系・3.7 は第1章 1.7（イベント管理）と virtio-input が前提。
3. **メッセージ**: 3.1 の `wsnd_evt`/`wrsp_evt`、3.8 の `oreq_prc`/`orsp_prc` は第1章 1.2（ハンドラ・型）の完成に依存。
4. **ファイル**: 3.6・3.8 は 1.6 の録層（B2 以降）とデータボックス形式に依存。
5. **フォント**: 2.5・3.9 は共有データ編のフォント形式と TRON コード（Phase 1）に依存。
6. **TCP/IP（3.10）**: ネットワーク装置とスタックが要る独立トラック。優先度は最後でよい。

## 次の作業

1. 各ページの引数・戻り値・エラー条件・定数を抽出し、節ごとの要求文書（`btron3-os.md` の第2章・第3章）を作る。
2. 切れた・文字化けしたページ（`menu`・`panel`・`tip`・`tcpip`・`printmgr`）を原文で再確認し、件数を確定する。
3. 2.1・2.2 のデータ型（点・矩形・色・描画環境）を共有データ編と突き合わせる。
