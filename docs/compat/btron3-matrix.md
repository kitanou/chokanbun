# BTRON3 OS 仕様編 適合性マトリクス（関数単位。生成物）

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42)。`python3 tools/spec_matrix.py matrix <作業ディレクトリ>` で生成（原文の取得は `fetch`）。
> 原文は ISO-2022-JP の HTML を `iconv` で変換して読んだ。本文は転載せず、関数名・エラーコード名だけを記録する。

## 読み方

- 実装: `user/btron/*.mkn` に同名の関数（`記號「名」` か `術曰「名」`）があるか。
- 試験: `user/btron_*.mkn`（互換層の試験プログラム）がその名前を呼んでいるか。
- 本体に現れないエラー: 原文のエラーコードのうち、**その関数の本体に名前が直接現れないもの**。他の関数が返す場合や、そもそも未対応の場合がある（要確認）。第1章は核が返すので対象外。
- 3.8 は日本語名の関数で実装している。定義の直前の註に BTRON 名が書いてあるものを実装済みと数える（誤差があり得る）。対応は [design-object-model.md](design-object-model.md) と [btron3-conformance.md](btron3-conformance.md) の 3.8 の行を参照。
- 状態は機械的な判定で、「適合確認済み」は人が根拠を確認して付ける。ここでは 0 件。

## 集計

| 節 | 関数 | 実装 | 実装＋試験 |
|---|---|---|---|
| 1.1 プロセス／タスク管理 | 16 | 16 | 16 |
| 1.2 メッセージ管理 | 8 | 8 | 8 |
| 1.3 タスク間通信 | 19 | 19 | 19 |
| 1.4 グローバル名 | 3 | 3 | 3 |
| 1.5 メモリ管理 | 19 | 19 | 13 |
| 1.6 ファイル管理 | 41 | 41 | 41 |
| 1.7 デバイス管理 | 9 | 9 | 9 |
| 1.8 イベント管理 | 20 | 20 | 20 |
| 1.9 時計管理 | 4 | 4 | 4 |
| 1.10 システム管理 | 4 | 4 | 4 |
| 2.3 基本関数 | 37 | 26 | 24 |
| 2.4 図形描画関数 | 42 | 6 | 6 |
| 2.5 文字(列)描画関数 | 20 | 20 | 20 |
| 2.6 ポインタ制御関数 | 6 | 6 | 6 |
| 3.1 ウィンドウマネージャ | 51 | 41 | 41 |
| 3.2 メニューマネージャ | 15 | 15 | 15 |
| 3.3 パーツマネージャ | 33 | 33 | 32 |
| 3.4 パネルマネージャ | 12 | 12 | 12 |
| 3.5 トレーマネージャ | 10 | 10 | 10 |
| 3.6 データマネージャ | 7 | 7 | 7 |
| 3.7 テキスト入力プリミティブ | 8 | 8 | 8 |
| 3.8 実身／仮身マネージャ | 60 | 31 | 27 |
| 3.9 フォントマネージャ | 14 | 14 | 14 |
| 3.10 TCP/IP マネージャ | 28 | 28 | 28 |
| 3.11 印刷マネージャ | 9 | 9 | 9 |
| **合計** | **495** | **409** | **396** |

## 1.1 プロセス／タスク管理（16 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `cre_prc` | `WERR cre_prc(LINK* lnk, W pri, MESSAGE* msg)` | `msg.mkn` | あり | 11 | —（核が返す） |
| `ext_prc` | `VOID ext_prc(W code)` | `msg.mkn` | あり | 0 | —（核が返す） |
| `ter_prc` | `ERR ter_prc(W pid, W code, W opt)` | `proc.mkn` | あり | 4 | —（核が返す） |
| `chg_pri` | `WERR chg_pri(W id, W pri, W opt)` | `proc.mkn` | あり | 4 | —（核が返す） |
| `prc_sts` | `WERR prc_sts(W pid, P_STATE* buff, TC* name)` | `proc.mkn` | あり | 0 | —（核が返す） |
| `chg_usr` | `ERR chg_usr(P_USER* buff)` | `proc.mkn` | あり | 2 | —（核が返す） |
| `get_usr` | `WERR get_usr(W pid, P_USER* buff)` | `proc.mkn` | あり | 2 | —（核が返す） |
| `get_inf` | `ERR get_inf(W pid, P_INFO* buff)` | `proc.mkn` | あり | 2 | —（核が返す） |
| `cre_tsk` | `WERR cre_tsk(FP entry, W pri, W arg)` | `proc.mkn` | あり | 4 | —（核が返す） |
| `ext_tsk` | `VOID ext_tsk()` | `proc.mkn` | あり | 0 | —（核が返す） |
| `ter_tsk` | `ERR ter_tsk(W tskid)` | `proc.mkn` | あり | 1 | —（核が返す） |
| `slp_tsk` | `ERR slp_tsk(W time)` | `proc.mkn` | あり | 3 | —（核が返す） |
| `wup_tsk` | `ERR wup_tsk(W tskid)` | `proc.mkn` | あり | 2 | —（核が返す） |
| `can_wup` | `WERR can_wup(W tskid)` | `proc.mkn` | あり | 1 | —（核が返す） |
| `dly_tsk` | `ERR dly_tsk(W time)` | `proc.mkn` | あり | 2 | —（核が返す） |
| `get_tid` | `W get_tid()` | `proc.mkn` | あり | 0 | —（核が返す） |

## 1.2 メッセージ管理（8 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `snd_msg` | `ERR snd_msg(W pid, MESSAGE* msg, W opt)` | `msg.mkn` | あり | 7 | —（核が返す） |
| `rcv_msg` | `WERR rcv_msg(W t_mask, MESSAGE* msg, W msgsz, W opt)` | `msg.mkn` | あり | 4 | —（核が返す） |
| `clr_msg` | `ERR clr_msg(W t_mask, W last_mask)` | `msg.mkn` | あり | 1 | —（核が返す） |
| `req_tmg` | `ERR req_tmg(W time, W code)` | `msg.mkn` | あり | 2 | —（核が返す） |
| `can_tmg` | `ERR can_tmg()` | `msg.mkn` | あり | 0 | —（核が返す） |
| `def_msg` | `ERR def_msg(W t_mask, FP msghdr)` | `msg.mkn` | あり | 2 | —（核が返す） |
| `ret_msg` | `ERR ret_msg(W ret)` | `msg.mkn` | あり | 0 | —（核が返す） |
| `brk_msg` | `ERR brk_msg()` | `msg.mkn` | あり | 0 | —（核が返す） |

## 1.3 タスク間通信（19 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `cre_sem` | `WERR cre_sem(W cnt, UW opt)` | `sync.mkn` | あり | 3 | —（核が返す） |
| `del_sem` | `ERR del_sem(ID id)` | `sync.mkn` | あり | 2 | —（核が返す） |
| `sig_sem` | `ERR sig_sem(ID id)` | `sync.mkn` | あり | 4 | —（核が返す） |
| `wai_sem` | `ERR wai_sem(ID id, TMOUT tmo)` | `sync.mkn` | あり | 7 | —（核が返す） |
| `cre_flg` | `WERR cre_flg(W ptn, UW opt)` | `sync.mkn` | あり | 3 | —（核が返す） |
| `del_flg` | `ERR del_flg(ID id)` | `sync.mkn` | あり | 2 | —（核が返す） |
| `set_flg` | `ERR set_flg(ID id, W ptn)` | `sync.mkn` | あり | 3 | —（核が返す） |
| `clr_flg` | `ERR clr_flg(ID id, W ptn)` | `sync.mkn` | あり | 2 | —（核が返す） |
| `wai_flg` | `WERR wai_flg(ID id, W ptn, UW mode, TMOUT tmo)` | `sync.mkn` | あり | 6 | —（核が返す） |
| `cre_mbf` | `WERR cre_mbf(W bufsz, W max, UW opt)` | `sync.mkn` | あり | 3 | —（核が返す） |
| `del_mbf` | `ERR del_mbf(ID id)` | `sync.mkn` | あり | 2 | —（核が返す） |
| `snd_mbf` | `ERR snd_mbf(ID id, VP msg, W sz, TMOUT tmo)` | `sync.mkn` | あり | 6 | —（核が返す） |
| `rcv_mbf` | `WERR rcv_mbf(ID id, VP msg, TMOUT tmo)` | `sync.mkn` | あり | 6 | —（核が返す） |
| `cre_por` | `WERR cre_por(W maxcmsz, W maxrmsz, UW opt)` | `sync.mkn` | あり | 3 | —（核が返す） |
| `del_por` | `ERR del_por(ID id)` | `sync.mkn` | あり | 2 | —（核が返す） |
| `cal_por` | `WERR cal_por(ID id, UW calptn, VP msg, W cmsz, TMOUT tmo)` | `sync.mkn` | あり | 6 | —（核が返す） |
| `acp_por` | `WERR acp_por(ID id, UW acpptn, W *rdv, VP msg, TMOUT tmo)` | `sync.mkn` | あり | 6 | —（核が返す） |
| `fwd_por` | `ERR fwd_por(ID id, UW calptn, W rdv, VP msg, W cmsz)` | `sync.mkn` | あり | 4 | —（核が返す） |
| `rpl_rdv` | `ERR rpl_rdv(W rdv, VP msg, W rmsz)` | `sync.mkn` | あり | 2 | —（核が返す） |

## 1.4 グローバル名（3 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `cre_nam` | `WERR cre_nam(TC* name, W data, W opt)` | `gname.mkn` | あり | 5 | —（核が返す） |
| `del_nam` | `ERR del_nam(TC* name)` | `gname.mkn` | あり | 3 | —（核が返す） |
| `get_nam` | `ERR get_nam(TC* name, W* data)` | `gname.mkn` | あり | 3 | —（核が返す） |

## 1.5 メモリ管理（19 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `get_mbk` | `ERR get_mbk( VP *adr, W nblk, UW atr )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `rel_mbk` | `ERR rel_mbk( VP adr )` | `mem.mkn` | あり | 2 | —（核が返す） |
| `mbk_sts` | `ERR mbk_sts( M_STATE *sts )` | `mem.mkn` | あり | 1 | —（核が返す） |
| `malloc` | `void* malloc( size_t size )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `calloc` | `void* calloc( size_t nelem, size_t elsize )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `realloc` | `void* realloc( void *ptr, size_t size )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `free` | `void free( void *ptr )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `Smalloc` | `void* Smalloc( size_t size )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `Scalloc` | `void* Scalloc( size_t nelem, size_t elsize )` | `mem.mkn` | なし | 0 | —（核が返す） |
| `Srealloc` | `void* Srealloc( void *ptr, size_t size )` | `mem.mkn` | なし | 0 | —（核が返す） |
| `Sfree` | `void Sfree( void *ptr )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `Kmalloc` | `void* Kmalloc( size_t size )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `Kcalloc` | `void* Kcalloc( size_t nelem, size_t elsize )` | `mem.mkn` | なし | 0 | —（核が返す） |
| `Krealloc` | `void* Krealloc( void *ptr, size_t size )` | `mem.mkn` | なし | 0 | —（核が返す） |
| `Kfree` | `void Kfree( void *ptr )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `Vmalloc` | `void* Vmalloc( size_t size )` | `mem.mkn` | あり | 0 | —（核が返す） |
| `Vcalloc` | `void* Vcalloc( size_t nelem, size_t elsize )` | `mem.mkn` | なし | 0 | —（核が返す） |
| `Vrealloc` | `void* Vrealloc( void *ptr, size_t size )` | `mem.mkn` | なし | 0 | —（核が返す） |
| `Vfree` | `void Vfree( void *ptr )` | `mem.mkn` | あり | 0 | —（核が返す） |

## 1.6 ファイル管理（41 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `get_lnk` | `WERR get_lnk(TC *path, LINK *lnk, W mode)` | `file.mkn` | あり | 8 | —（核が返す） |
| `chg_wrk` | `ERR chg_wrk(LINK *lnk)` | `file.mkn` | あり | 6 | —（核が返す） |
| `cre_fil` | `WERR cre_fil(LINK *lnk, TC *name, A_MODE *mode, UH atype, W opt)` | `file.mkn` | あり | 14 | —（核が返す） |
| `cre_lnk` | `ERR cre_lnk(LINK *lnk, F_LINK *ref, W opt)` | `file.mkn` | あり | 14 | —（核が返す） |
| `gen_fil` | `WERR gen_fil(LINK *lnk, TC *name, F_STATE *stat, F_LINK *ref, W opt)` | `file.mkn` | あり | 13 | —（核が返す） |
| `opn_fil` | `WERR opn_fil(LINK *lnk, W o_mode, TC *pwd)` | `file.mkn` | あり | 11 | —（核が返す） |
| `cls_fil` | `ERR cls_fil(W fd)` | `file.mkn` | あり | 2 | —（核が返す） |
| `del_fil` | `WERR del_fil(LINK *org, LINK *lnk, W force)` | `file.mkn` | あり | 11 | —（核が返す） |
| `see_rec` | `ERR see_rec(W fd, W offset, W mode, W *recnum)` | `file.mkn` | あり | 4 | —（核が返す） |
| `fnd_rec` | `WERR fnd_rec(W fd, W mode, UW typemask, UH subtype, W *recnum)` | `file.mkn` | あり | 5 | —（核が返す） |
| `fnd_lnk` | `ERR fnd_lnk(W fd, W mode, LINK *lnk, UH subtype, W *recnum)` | `file.mkn` | あり | 8 | —（核が返す） |
| `rea_rec` | `WERR rea_rec(W fd, W offset, B *buf, W size, W *r_size, UH *subtype)` | `file.mkn` | あり | 6 | —（核が返す） |
| `wri_rec` | `ERR wri_rec(W fd, W offset, B *buf, W size, W *r_size, UH *subtype, UW units)` | `file.mkn` | あり | 8 | —（核が返す） |
| `ins_rec` | `ERR ins_rec(W fd, B *buf, W size, W type, UH subtype, UW units)` | `file.mkn` | あり | 9 | —（核が返す） |
| `apd_rec` | `ERR apd_rec(W fd, B *buf, W size, W type, UH subtype, UW units)` | `file.mkn` | あり | 9 | —（核が返す） |
| `del_rec` | `WERR del_rec(W fd)` | `file.mkn` | あり | 6 | —（核が返す） |
| `trc_rec` | `ERR trc_rec(W fd, W size)` | `file.mkn` | あり | 6 | —（核が返す） |
| `xch_fil` | `ERR xch_fil(W fd_1, W fd_2)` | `file.mkn` | あり | 6 | —（核が返す） |
| `loc_rec` | `ERR loc_rec(W fd, W mode)` | `file.mkn` | あり | 8 | —（核が返す） |
| `chk_fil` | `WERR chk_fil(LINK *lnk, W mode, TC *pwd)` | `file.mkn` | あり | 9 | —（核が返す） |
| `chg_fmd` | `ERR chg_fmd(LINK *lnk, A_MODE *mode)` | `file.mkn` | あり | 8 | —（核が返す） |
| `chg_fat` | `ERR chg_fat(LINK *lnk, W attr)` | `file.mkn` | あり | 8 | —（核が返す） |
| `chg_fpw` | `ERR chg_fpw(W fd, TC *pwd)` | `file.mkn` | あり | 6 | —（核が返す） |
| `chg_fnm` | `ERR chg_fnm(LINK *lnk, TC *name)` | `file.mkn` | あり | 9 | —（核が返す） |
| `chg_ftm` | `ERR chg_ftm(LINK *lnk, F_TIME *times)` | `file.mkn` | あり | 7 | —（核が返す） |
| `fil_sts` | `WERR fil_sts(LINK *lnk, TC *name, F_STATE *stat, F_LOCATE *locat)` | `file.mkn` | あり | 6 | —（核が返す） |
| `ofl_sts` | `WERR ofl_sts(W fd, TC *name, F_STATE *stat, F_LOCATE *locat)` | `file.mkn` | あり | 6 | —（核が返す） |
| `lnk_sts` | `WERR lnk_sts(LINK *lnk, F_LINK *stat)` | `file.mkn` | あり | 6 | —（核が返す） |
| `syn_lnk` | `WERR syn_lnk(LINK *lnk, W opt)` | `file.mkn` | あり | 7 | —（核が返す） |
| `get_dfm` | `ERR get_dfm(DA_MODE *mode)` | `file.mkn` | あり | 1 | —（核が返す） |
| `set_dfm` | `ERR set_dfm(DA_MODE *mode)` | `file.mkn` | あり | 2 | —（核が返す） |
| `att_fls` | `ERR att_fls(TC *dev, TC *name, LINK *lnk, UW mode)` | `file.mkn` | あり | 12 | —（核が返す） |
| `det_fls` | `ERR det_fls(TC *dev, W eject)` | `file.mkn` | あり | 9 | —（核が返す） |
| `syn_fls` | `ERR syn_fls(VOID)` | `file.mkn` | あり | 4 | —（核が返す） |
| `fls_sts` | `WERR fls_sts(TC *dev, FS_STATE *buff)` | `file.mkn` | あり | 9 | —（核が返す） |
| `chg_fls` | `ERR chg_fls(TC *dev, TC *fs_name, TC *fs_locate)` | `file.mkn` | あり | 12 | —（核が返す） |
| `get_nlk` | `WERR get_nlk(LINK *lnk)` | `file.mkn` | あり | 5 | —（核が返す） |
| `lst_fls` | `WERR lst_fls(F_ATTACH *buff, W cnt)` | `file.mkn` | あり | 3 | —（核が返す） |
| `map_rec` | `WERR map_rec(W fd, W offset, B **addr, W size, W mode)` | `file.mkn` | あり | 8 | —（核が返す） |
| `ump_rec` | `ERR ump_rec(W fd, W mapid)` | `file.mkn` | あり | 3 | —（核が返す） |
| `chg_fsm` | `WERR chg_fsm( TC *dev, UW mode )` | `file.mkn` | あり | 5 | —（核が返す） |

## 1.7 デバイス管理（9 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `opn_dev` | `WERR opn_dev(TC* dev, W o_mode, W* error)` | `dev.mkn` | あり | 14 | —（核が返す） |
| `cls_dev` | `ERR cls_dev(W dd, W eject, W* error)` | `dev.mkn` | あり | 4 | —（核が返す） |
| `rea_dev` | `ERR rea_dev(W dd, W start, B* buf, W size, W* a_size, W* error)` | `dev.mkn` | あり | 10 | —（核が返す） |
| `wri_dev` | `ERR wri_dev(W dd, W start, B* buf, W size, W* a_size, W* error)` | `dev.mkn` | あり | 11 | —（核が返す） |
| `chg_dmd` | `ERR chg_dmd(TC* dev, W mode)` | `dev.mkn` | あり | 4 | —（核が返す） |
| `dev_sts` | `ERR dev_sts(TC* dev, DEV_STATE* buf)` | `dev.mkn` | あり | 2 | —（核が返す） |
| `get_dev` | `WERR get_dev(TC* dev, W devno)` | `dev.mkn` | あり | 2 | —（核が返す） |
| `lst_dev` | `WERR lst_dev(DEV_INFO* dev, W ndev)` | `dev.mkn` | あり | 2 | —（核が返す） |
| `sus_dev` | `WERR sus_dev(UW mode)` | `dev.mkn` | あり | 4 | —（核が返す） |

## 1.8 イベント管理（20 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `get_evt` | `WERR get_evt(W t_mask, EVENT* evt, W opt)` | `evt.mkn` | あり | 4 | —（核が返す） |
| `put_evt` | `ERR put_evt(EVENT* evt, W opt)` | `evt.mkn` | あり | 4 | —（核が返す） |
| `clr_evt` | `ERR clr_evt(W t_mask, W last_mask)` | `evt.mkn` | あり | 1 | —（核が返す） |
| `get_pdp` | `WERR get_pdp(PNT* pos)` | `evt.mkn` | あり | 7 | —（核が返す） |
| `set_pdp` | `WERR set_pdp(PNT pos)` | `evt.mkn` | あり | 7 | —（核が返す） |
| `get_etm` | `ERR get_etm(UW* time)` | `evt.mkn` | あり | 1 | —（核が返す） |
| `get_kmp` | `ERR get_kmp(KeyMap keymap)` | `evt.mkn` | あり | 7 | —（核が返す） |
| `chg_emk` | `WERR chg_emk(W mask)` | `evt.mkn` | あり | 0 | —（核が返す） |
| `set_krp` | `ERR set_krp(W offset, W interval)` | `evt.mkn` | あり | 1 | —（核が返す） |
| `get_krp` | `ERR get_krp(W* offset, W* interval)` | `evt.mkn` | あり | 1 | —（核が返す） |
| `set_krm` | `ERR set_krm(KeyMap keymap)` | `evt.mkn` | あり | 1 | —（核が返す） |
| `get_krm` | `ERR get_krm(KeyMap keymap)` | `evt.mkn` | あり | 1 | —（核が返す） |
| `get_kid` | `ERR get_kid(KBD_ID* id)` | `evt.mkn` | あり | 7 | —（核が返す） |
| `get_ktb` | `WERR get_ktb(KeyTab* keytab)` | `evt.mkn` | あり | 7 | —（核が返す） |
| `set_ktb` | `ERR set_ktb(KeyTab* keytab)` | `evt.mkn` | あり | 8 | —（核が返す） |
| `chg_pda` | `WERR chg_pda(W atr)` | `evt.mkn` | あり | 7 | —（核が返す） |
| `sig_buz` | `ERR sig_buz(W type)` | `evt.mkn` | あり | 5 | —（核が返す） |
| `ctl_buz` | `ERR ctl_buz(W kind, UW *val)` | `evt.mkn` | あり | 2 | —（核が返す） |
| `req_evt` | `ERR req_evt(W t_mask)` | `evt.mkn` | あり | 2 | —（核が返す） |
| `las_evt` | `WERR las_evt(W t_mask)` | `evt.mkn` | あり | 1 | —（核が返す） |

## 1.9 時計管理（4 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `get_tim` | `ERR get_tim(STIME* time, TIMEZONE* tz)` | `clk.mkn` | あり | 1 | —（核が返す） |
| `set_tim` | `ERR set_tim(STIME time, TIMEZONE* tz)` | `clk.mkn` | あり | 3 | —（核が返す） |
| `get_tod` | `ERR get_tod(DATE_TIM* dt, STIME time, Bool local)` | `clk.mkn` | あり | 1 | —（核が返す） |
| `set_tod` | `ERR set_tod(DATE_TIM* dt, STIME* time, Bool local)` | `clk.mkn` | あり | 3 | —（核が返す） |

## 1.10 システム管理（4 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `def_exc` | `ERR def_exc(W exckind, FP exchdr)` | `exc.mkn` | あり | 3 | —（核が返す） |
| `ret_exc` | `VOID ret_exc(W ret)` | `exc.mkn` | あり | 0 | —（核が返す） |
| `get_ver` | `ERR get_ver(T_VER* version)` | `sys.mkn` | あり | 1 | —（核が返す） |
| `get_cnf` | `WERR get_cnf(TC* name, VP value, W len)` | `sys.mkn` | あり | 3 | —（核が返す） |

## 2.3 基本関数（37 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `gini_dsp` | `ERR gini_dsp (W mode)` | `dp.mkn` | なし | 1 | `EG_NOSP` |
| `gfin_dsp` | `ERR gfin_dsp ( )` | `dp.mkn` | なし | 0 |  |
| `gcls_env` | `ERR gcls_env ( GID gid )` | `dp.mkn` | あり | 1 |  |
| `gopn_dev` | `GID gopn_dev ( TC *dev, B *par )` | `dp.mkn` | あり | 5 | `EG_DEV` |
| `gopn_mem` | `GID gopn_mem ( TC *dev, BMP *bmap, B *par )` | `dp.mkn` | あり | 6 | `EG_DEV` `EG_NOSPC` |
| `gnew_env` | `GID gnew_env ( GID gid )` | `dp.mkn` | あり | 3 | `EG_NOSPC` |
| `gini_env` | `ERR gini_env ( GID gid )` | `dp.mkn` | あり | 1 |  |
| `gget_spc` | `ERR gget_spc ( TC *dev, DEVSPEC *buf )` | `dp.mkn` | あり | 2 |  |
| `gget_dev` | `ERR gget_dev ( W gid, TC dev[11] )` | `dp.mkn` | あり | 2 |  |
| `gget_dsp` | `ERR gget_dsp ( W gid, DEVSPEC *buf )` | `dp.mkn` | あり | 2 |  |
| `gget_csp` | `ERR gget_csp ( W gid, CSPEC *buf )` | `dp.mkn` | あり | 3 |  |
| `gset_bcs` | `ERR gset_bcs ( GID gid, CSPEC *cspec )` | 未実装 | — | 3 | — |
| `gget_bcs` | `ERR gget_bcs ( GID gid, CSPEC *cspec )` | 未実装 | — | 3 | — |
| `gset_col` | `W gset_col ( GID gid, UW p, COLOR *cv, UW cnt )` | 未実装 | — | 4 | — |
| `gget_col` | `W gget_col ( GID gid, UW p, COLOR OUT *cv, UW cnt )` | 未実装 | — | 4 | — |
| `gcnv_col` | `W gcnv_col ( GID gid, COLOR cv, PIXVAL OUT *pixv )` | `dp.mkn` | あり | 3 |  |
| `gset_msk` | `ERR gset_msk ( GID gid, PIXVAL pixv )` | `dp.mkn` | あり | 2 | `EG_NOSPT` |
| `gget_msk` | `ERR gget_msk ( GID gid, PIXVAL OUT *pixv )` | `dp.mkn` | あり | 2 | `EG_NOSPT` |
| `gget_clp` | `ERR gget_clp ( GID gid, GRGN *clip, W csize, W *a_size )` | `dp.mkn` | あり | 2 |  |
| `gset_clp` | `ERR gset_clp ( GID gid, GRGN *clip )` | `dp.mkn` | あり | 4 | `EG_ADR` `EG_NOSPC` `EG_PAR` |
| `gget_fra` | `ERR gget_fra ( GID gid, RECT *rp )` | `dp.mkn` | あり | 2 | `EG_ADR` `EG_GID` |
| `gset_fra` | `ERR gset_fra ( GID gid, RECT r )` | `dp.mkn` | あり | 2 | `EG_PAR` |
| `gget_vis` | `ERR gget_vis ( GID gid, RECT *rp )` | `dp.mkn` | あり | 2 | `EG_ADR` `EG_GID` |
| `gset_vis` | `ERR gset_vis ( GID gid, RECT r )` | `dp.mkn` | あり | 2 | `EG_PAR` |
| `gget_for` | `ERR gget_for ( GID gid, RLIST *rlp )` | 未実装 | — | 2 | — |
| `gset_for` | `ERR gset_for ( GID gid, RLIST *rlp )` | 未実装 | — | 2 | — |
| `gsiz_pat` | `ERR gsiz_pat ( GID gid, UW kind, UW hsize, UW vsize, W *size )` | 未実装 | — | 4 | — |
| `gcre_pat` | `ERR gcre_pat ( GID gid, PAT *def, UB *loc, UB **pat, W *size、W cvt )` | 未実装 | — | 6 | — |
| `gset_lmk` | `ERR gset_lmk ( GID gid, UW nbytes, UB *mask )` | 未実装 | — | 3 | — |
| `gget_lmk` | `W gget_lmk ( GID gid, UB *mask )` | 未実装 | — | 2 | — |
| `gget_bmp` | `ERR gget_bmp ( GID gid, BMP *bmap )` | `dp.mkn` | あり | 2 |  |
| `gget_bnd` | `ERR gget_bnd ( GID gid, RECT *rp )` | `dp.mkn` | あり | 2 | `EG_ADR` `EG_GID` |
| `gmov_bnd` | `ERR gmov_bnd ( GID gid, W dh, W dv )` | `dp.mkn` | あり | 2 |  |
| `gmov_cor` | `ERR gmov_cor ( GID gid, W dh, W dv )` | `dp.mkn` | あり | 2 |  |
| `gcnv_abs` | `ERR gcnv_abs ( GID gid, PNT *pp )` | `dp.mkn` | あり | 3 | `EG_ADR` `EG_GID` `EG_PAR` |
| `gcnv_rel` | `ERR gcnv_rel ( GID gid, PNT *pp )` | `dp.mkn` | あり | 3 | `EG_ADR` `EG_GID` `EG_PAR` |
| `gloc_env` | `ERR gloc_env ( GID gid W lock )` | 未実装 | — | 3 | — |

## 2.4 図形描画関数（42 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `gdra_lin` | `ERR gdra_lin ( GID gid, PNT p1, PNT p2, LATTR attr, PAT *pat, DCM mode )` | 未実装 | — | 3 | — |
| `gtst_pnt` | `Bool gtst_pnt ( GID gid, PNT p, PIXVAL *val )` | `dp.mkn` | あり | 2 |  |
| `gdra_pnt` | `ERR gdra_pnt ( GID gid, PNT p, PIXVAL val, DCM mode )` | `dp.mkn` | あり | 2 |  |
| `gfil_pnt` | `ERR gfil_pnt ( GID gid, PNT p, PAT *pat, DCM mode )` | `dp.mkn` | あり | 3 | `EG_ADR` |
| `gfra_rec` | `ERR gfra_rec ( GID gid, RECT r, LATTR attr, PAT *pat, DEG angle, DCM mode )` | `dp.mkn` | あり | 3 | `EG_ADR` |
| `gfil_rec` | `ERR gfil_rec ( GID gid, RECT r, PAT *pat, DEG angle, DCM mode )` | `dp.mkn` | あり | 3 | `EG_ADR` |
| `gfra_rrc` | `ERR gfra_rrc ( GID gid, RECT r, UW rh, UW rv, LATTR attr, PAT *pat, DEG angle, DCM mode )` | 未実装 | — | 3 | — |
| `gfil_rrc` | `ERR gfil_rrc ( GID gid, RECT r, UW rh, UW rv, PAT *pat, DEG angle, DCM mode )` | 未実装 | — | 3 | — |
| `gfra_ovl` | `ERR gfra_ovl ( GID gid, RECT r, LATTR attr, PAT *pat, DEG angle, DCM mode )` | 未実装 | — | 3 | — |
| `gfil_ovl` | `ERR gfil_ovl ( GID gid, RECT r, PAT *pat, DEG angle, DCM mode )` | 未実装 | — | 3 | — |
| `gdra_arc` | `ERR gdra_arc ( GID gid, RECT r, PNT sp, PNT ep, LATTR attr, PAT *pat, DEG angle, DCM mode )` | 未実装 | — | 3 | — |
| `gfra_sec` | `ERR gfra_sec ( GID gid, RECT r, PNT sp, PNT ep, LATTR attr, PAT *pat, DEG angle, DCM mode )` | 未実装 | — | 3 | — |
| `gfil_sec` | `ERR gfil_sec ( GID gid, RECT r, PNT sp, PNT ep, PAT *pat, DEG angle, DCM mode )` | 未実装 | — | 3 | — |
| `gfra_cho` | `ERR gfra_cho ( GID gid, RECT r, PNT sp, PNT ep, LATTR attr, PAT *pat, DEG angle, DCM mode )` | 未実装 | — | 3 | — |
| `gfil_cho` | `ERR gfil_cho ( GID gid, RECT r, PNT sp, PNT ep, PAT *pat, DEG angle, DCM mode )` | 未実装 | — | 4 | — |
| `gdra_pln` | `ERR gdra_pln ( GID gid, POLY *p, LATTR attr, PAT *pat, DCM mode )` | 未実装 | — | 5 | — |
| `gfra_pol` | `ERR gfra_pol ( GID gid, POLY *p, LATTR attr, PAT *pat, DCM mode )` | 未実装 | — | 5 | — |
| `gfil_pol` | `ERR gfil_pol ( GID gid, POLY *p, PAT *pat, DCM mode )` | 未実装 | — | 5 | — |
| `gfil_gen` | `ERR gfil_gen ( GID gid, GRGN *rgn, PAT *pat, DCM mode )` | 未実装 | — | 5 | — |
| `gfil_rgn` | `Bool gfil_rgn ( GID gid, PIXVAL val, PNT p, PAT *pat, DCM mode )` | 未実装 | — | 4 | — |
| `gdra_spl` | `ERR gdra_spl ( GID gid, UW np, PNT *pt, LATTR attr, PAT *pat, DCM mode )` | 未実装 | — | 5 | — |
| `gfil_spl` | `ERR gfil_spl ( GID gid, UW np, PNT *pt, PAT *pat, DCM mode )` | 未実装 | — | 6 | — |
| `gcop_bmp` | `ERR gcop_bmp ( GID srcid, RECT *sr, GID dstid, RECT *dr, GRGN *mask, DCM mode )` | `dp.mkn` | あり | 7 | `EG_LIMIT` `EG_NOSPC` |
| `gsav_bmp` | `ERR gsav_bmp ( GID gid, RECT *gr, BMP *bmap, RECT *br, GRGN *mask, DCM mode )` | 未実装 | — | 8 | — |
| `grst_bmp` | `ERR grst_bmp ( GID gid, RECT *gr, BMP *bmap, RECT *br, GRGN *mask, DCM mode )` | 未実装 | — | 8 | — |
| `grst_mbm` | `ERR grst_mbm ( GID gid, RECT *gr, BMP *bmap, RECT *br, UB *mask, DCM mode )` | 未実装 | — | 8 | — |
| `grot_bmp` | `ERR grot_bmp ( GID srcid, GID dstid, RECT *rp, PNT *dp, DEG angle, GRGN *mask, DCM mode )` | 未実装 | — | 6 | — |
| `gscr_rec` | `W gscr_rec ( GID gid, RECT r, W dh, W dv RLIST *rlp, PAT *pat )` | 未実装 | — | 4 | — |
| `gsiz_cbm` | `ERR gsiz_cbm ( GID gid, RECT *rp, W compac, W *size )` | 未実装 | — | 4 | — |
| `gcom_bmp` | `Bool gcom_bmp ( GID gid, RECT *rp, CBMP *cbmp, W *stat )` | 未実装 | — | 4 | — |
| `gunc_bmp` | `ERR gunc_bmp ( GID gid, RECT *dr, CBMP *cbmp, RECT *sr, DCM mode )` | 未実装 | — | 5 | — |
| `gpic_lin` | `Bool gpic_lin ( PNT pt, PNT p0, PNT p1, UW width )` | 未実装 | — | 0 | — |
| `gpic_rec` | `Bool gpic_rec ( PNT pt, RECT r, DEG angle, UW width )` | 未実装 | — | 0 | — |
| `gpic_rrc` | `Bool gpic_rrc ( PNT pt, RECT r, UW rh, UW rv, DEG angle, UW width )` | 未実装 | — | 0 | — |
| `gpic_ovl` | `Bool gpic_ovl ( PNT pt, RECT r, DEG angle, UW width )` | 未実装 | — | 0 | — |
| `gpic_arc` | `Bool gpic_arc ( PNT pt, RECT r, PNT sp, PNT ep, DEG angle, UW width )` | 未実装 | — | 0 | — |
| `gpic_sec` | `Bool gpic_sec ( PNT pt, RECT r, PNT sp, PNT ep, DEG angle, UW width )` | 未実装 | — | 0 | — |
| `gpic_cho` | `Bool gpic_cho ( PNT pt, RECT r, PNT sp, PNT ep, DEG angle, UW width )` | 未実装 | — | 0 | — |
| `gpic_pln` | `Bool gpic_pln ( PNT pt, POLY *poly, UW width )` | 未実装 | — | 1 | — |
| `gpic_pol` | `Bool gpic_pol ( PNT pt, POLY *poly, UW width )` | 未実装 | — | 1 | — |
| `gpic_gen` | `Bool gpic_gen ( PNT pt, GRGN *rgn )` | 未実装 | — | 1 | — |
| `gpic_spl` | `Bool gpic_spl ( PNT p, UW np, PNT *pt, UW width )` | 未実装 | — | 1 | — |

## 2.5 文字(列)描画関数（20 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `gset_chp` | `ERR gset_chp ( GID gid, W x, W y, Bool abs )` | `dpchr.mkn` | あり | 2 |  |
| `gget_chp` | `ERR gget_chp ( GID gid, W *x, W *y )` | `dpchr.mkn` | あり | 2 |  |
| `gset_chc` | `ERR gset_chc ( GID gid, COLOR fgc, COLOR bgc )` | `dpchr.mkn` | あり | 1 |  |
| `gget_chc` | `ERR gget_chc ( GID gid, COLOR *fgc, COLOR *bgc )` | `dpchr.mkn` | あり | 2 |  |
| `gset_chd` | `ERR gset_chd ( GID gid, W dir, CGAP *gap )` | `dpchr.mkn` | あり | 3 | `EG_ADR` `EG_PAR` |
| `gget_chd` | `W gget_chd ( GID gid, CGAP OUT *gap )` | `dpchr.mkn` | あり | 2 | `EG_ADR` |
| `gset_fon` | `ERR gset_fon ( GID gid, FSSPEC *fnt )` | `font.mkn` | あり | 4 | `EG_NOSPC` |
| `gget_fon` | `ERR gget_fon ( GID gid, FSSPEC *fnt, FNTINFO *inf )` | `font.mkn` | あり | 2 |  |
| `gset_scr` | `ERR gset_scr ( GID gid, SCRIPT script)` | `dpchr.mkn` | あり | 2 |  |
| `gget_scr` | `ERR gget_scr ( GID gid, SCRIPT *script)` | `dpchr.mkn` | あり | 2 |  |
| `gget_chw` | `WERR gget_chw ( GID gid, TC ch )` | `dpchr.mkn` | あり | 1 |  |
| `gget_chh` | `WERR gget_chh ( GID gid, TC ch )` | `dpchr.mkn` | あり | 1 |  |
| `gget_stw` | `WERR gget_stw ( GID gid, TC *str, W len, CGAP *gap, W *pos )` | `dpchr.mkn` | あり | 3 | `EG_PAR` |
| `gget_sth` | `WERR gget_sth ( GID gid, TC *str, W len, CGAP *gap, W *pos )` | `dpchr.mkn` | あり | 3 | `EG_PAR` |
| `gget_str` | `WERR gget_str ( GID gid, TC *str, W len, CGAP *gap, PNT *chp, RECT *cr, RECT *dr, W *alen)` | `dpchr.mkn` | あり | 3 | `EG_PAR` |
| `gdra_chr` | `WERR gdra_chr ( GID gid, TC ch, DCM mode )` | `dpchr.mkn` | あり | 2 |  |
| `gdra_chp` | `WERR gdra_chp ( GID gid, W x, W y, TC ch, DCM mode )` | `dpchr.mkn` | あり | 2 | `EG_GID` `EG_PAR` |
| `gdra_str` | `WERR gdra_str ( GID gid, TC *str, W len, DCM mode )` | `dpchr.mkn` | あり | 3 |  |
| `gdra_stp` | `WERR gdra_stp ( GID gid, W x, W y, TC *str, W len, DCM mode )` | `dpchr.mkn` | あり | 3 | `EG_ADR` `EG_GID` `EG_PAR` |
| `gcop_chr` | `ERR gcop_chr ( GID gid, SIZE asize, SIZE isize, UB *img, DCM mode )` | `dpchr.mkn` | あり | 3 |  |

## 2.6 ポインタ制御関数（6 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `gini_ptr` | `ERR gini_ptr ( )` | `ptr.mkn` | あり | 0 |  |
| `gdsp_ptr` | `ERR gdsp_ptr ( W req )` | `ptr.mkn` | あり | 0 |  |
| `gset_ptr` | `ERR gset_ptr ( PTRSTL style, PTRIMG *img, COLOR fgcol, COLOR bgcol )` | `ptr.mkn` | あり | 2 |  |
| `gmov_ptr` | `ERR gmov_ptr ( PNT pos )` | `ptr.mkn` | あり | 1 |  |
| `gmot_ptr` | `ERR gmot_ptr ( W sts )` | `ptr.mkn` | あり | 0 |  |
| `gget_ptr` | `W gget_ptr ( PTRSTS *sts, PTRIMG *img )` | `ptr.mkn` | あり | 1 |  |

## 3.1 ウィンドウマネージャ（51 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `wopn_wnd` | `WID wopn_wnd(UW attr, UW par, RECT *r, RECT *org, W pict, TC *tit, PAT *bgpat, WDDISP * atr)` | `wnd.mkn` | あり | 5 | `EX_WPRC` `EX_WND` |
| `wopn_iwd` | `WID wopn_iwd(W gid)` | 未実装 | — | 3 | — |
| `wopn_pwd` | `WID wopn_pwd(RECT *r)` | 未実装 | — | 2 | — |
| `wcls_wnd` | `ERR wcls_wnd(W wid, W opt)` | `wnd.mkn` | あり | 2 |  |
| `wchg_wnd` | `W wchg_wnd(W wid, RECT *r, W mode)` | 未実装 | — | 4 | — |
| `wmov_wnd` | `W wmov_wnd(W wid, RECT *newr)` | `wnd.mkn` | あり | 3 |  |
| `wmov_drg` | `W wmov_drg(WEVENT *evt, RECT *newr)` | `wnd.mkn` | あり | 4 | `EX_PAR` |
| `wrsz_wnd` | `W wrsz_wnd(W wid, RECT *newr)` | `wnd.mkn` | あり | 4 |  |
| `wrsz_drg` | `W wrsz_drg(WEVENT *evt, RECT *limit, RECT *newr)` | `wnd.mkn` | あり | 4 | `EX_PAR` |
| `wscr_wnd` | `W wscr_wnd(W wid, RECT *r, W dh, W dv, W mode)` | `wnd.mkn` | あり | 4 | `EX_WND` |
| `wsta_dsp` | `W wsta_dsp(W wid, RECT *r, RLIST *rlst)` | `wnd.mkn` | あり | 3 | `EX_WND` |
| `wend_dsp` | `W wend_dsp(W wid)` | `wnd.mkn` | あり | 3 | `EX_WND` `EX_ADR` |
| `wchk_dsp` | `W wchk_dsp(W wid)` | `wnd.mkn` | あり | 2 | `EX_WND` |
| `wsta_drg` | `GID wsta_drg(W wid, W lock)` | `wnd.mkn` | あり | 5 |  |
| `wend_drg` | `ERR wend_drg(void)` | `wnd.mkn` | あり | 1 |  |
| `wget_drg` | `W wget_drg(PNT *pos, WEVENT *evt)` | `wnd.mkn` | あり | 2 |  |
| `wget_evt` | `W wget_evt(WEVENT *evt, W mode)` | `wnd.mkn` | あり | 1 |  |
| `wugt_evt` | `ERR wugt_evt(WEVENT *evt)` | `wnd.mkn` | あり | 2 |  |
| `wpas_evt` | `ERR wpas_evt(WEVENT *evt)` | `wnd.mkn` | あり | 2 |  |
| `wswi_wnd` | `ERR wswi_wnd(W wid, WEVENT *evt)` | `wnd.mkn` | あり | 4 |  |
| `wsnd_evt` | `W wsnd_evt(WEVENT *evt)` | 未実装 | — | 4 | — |
| `wrsp_evt` | `ERR wrsp_evt(WEVENT *evt, W nak)` | 未実装 | — | 2 | — |
| `wwai_rsp` | `W wwai_rsp(WEVENT *evt, W cmd, UW tmout)` | 未実装 | — | 2 | — |
| `wreq_dsp` | `ERR wreq_dsp(W wid)` | `wnd.mkn` | あり | 0 |  |
| `wfnd_wnd` | `W wfnd_wnd(PNT *gpos, PNT *lpos, W *wid)` | `wnd.mkn` | あり | 1 |  |
| `wget_act` | `WID wget_act(W *pid)` | `wnd.mkn` | あり | 1 |  |
| `wget_tit` | `W wget_tit(W wid, W *pict, TC *title)` | `wnd.mkn` | あり | 3 | `EX_WND` |
| `wset_tit` | `ERR wset_tit(W wid, W pict, TC *title, W mode)` | `wnd.mkn` | あり | 3 | `EX_WND` |
| `wget_sts` | `W wget_sts(W wid, WDSTAT *stat, WDDISP *atr)` | `wnd.mkn` | あり | 3 | `EX_WND` |
| `wget_gid` | `GID wget_gid(W wid)` | `wnd.mkn` | あり | 1 |  |
| `wset_bgp` | `ERR wset_bgp(W wid, PAT *pat)` | `wnd.mkn` | あり | 5 | `EX_NOSPC` `EX_WND` |
| `wget_bgp` | `W wget_bgp(W wid, PAT *pat, W size)` | `wnd.mkn` | あり | 4 | `EX_WND` |
| `wera_wnd` | `ERR wera_wnd(W wid, RECT *r)` | `wnd.mkn` | あり | 3 | `EX_WND` |
| `wchg_dsp` | `ERR wchg_dsp(WDDISP *atr, PAT *bgpat)` | `wnd.mkn` | あり | 2 |  |
| `wget_bar` | `ERR wget_bar(W wid, W *rbar, W *bbar, W *lbar)` | `wnd.mkn` | あり | 3 |  |
| `wget_dat` | `ERR wget_dat(W wid, W *dat)` | `wnd.mkn` | あり | 2 |  |
| `wset_dat` | `ERR wset_dat(W wid, W dat)` | `wnd.mkn` | あり | 1 |  |
| `wget_wrk` | `ERR wget_wrk(W wid, RECT *r)` | `wnd.mkn` | あり | 3 |  |
| `wset_wrk` | `ERR wset_wrk(W wid, RECT *r)` | `wnd.mkn` | あり | 3 |  |
| `wget_org` | `ERR wget_org(W wid, W *parent, RECT *org)` | `wnd.mkn` | あり | 3 |  |
| `wset_org` | `ERR wset_org(W wid, W parent, RECT *org)` | `wnd.mkn` | あり | 3 |  |
| `wlst_wnd` | `W wlst_wnd(W wid, W size, W *wids)` | `wnd.mkn` | あり | 1 |  |
| `wget_dmn` | `ERR wget_dmn(TC **dmenu)` | 未実装 | — | 1 | — |
| `wexe_dmn` | `W wexe_dmn(W item)` | 未実装 | — | 2 | — |
| `wdef_fep` | `ERR wdef_fep(W onoff)` | `wnd.mkn` | あり | 2 |  |
| `wchk_dck` | `W wchk_dck(UW first)` | 未実装 | — | 1 | — |
| `wchg_dck` | `W wchg_dck(W time)` | `wnd.mkn` | あり | 0 |  |
| `wchg_ful` | `ERR wchg_ful(void)` | 未実装 | — | 1 | — |
| `wcnv_rec` | `ERR wcnv_rec(UW attr, RECT *r, UW opt)` | `wnd.mkn` | あり | 2 |  |
| `wget_inf` | `ERR wget_inf(W item, VP buf, W size)` | `wnd.mkn` | あり | 4 | `EX_NOSPC` |
| `wset_inf` | `ERR wset_inf(W item, VP buf, W size)` | `wnd.mkn` | あり | 4 |  |

## 3.2 メニューマネージャ（15 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `mcre_men` | `MNID mcre_men(W nitem, MENUITEM *item, MENUDISP *attr)` | `menu.mkn` | あり | 3 |  |
| `mopn_men` | `MNID mopn_men(W dnum)` | `menu.mkn` | あり | 0 |  |
| `mdel_men` | `ERR mdel_men(W mid)` | `menu.mkn` | あり | 1 |  |
| `msel_men` | `W msel_men(W mid, PNT pos)` | `menu.mkn` | あり | 1 |  |
| `mfnd_key` | `W mfnd_key(W mid, TC ch)` | `menu.mkn` | あり | 1 |  |
| `mget_itm` | `W mget_itm(W mid, W pnum, MENUITEM *item)` | `menu.mkn` | あり | 3 |  |
| `mset_itm` | `ERR mset_itm(W mid, W pnum, MENUITEM *item)` | `menu.mkn` | あり | 4 |  |
| `mchg_atr` | `W mchg_atr(W mid, W selnum, UW mode)` | `menu.mkn` | あり | 2 |  |
| `mchg_dsp` | `W mchg_dsp(MENUDISP *attr, W posattr)` | `menu.mkn` | あり | 2 | `EX_DNUM` |
| `mcre_gmn` | `MNID mcre_gmn(GMENU *gm)` | `menu.mkn` | あり | 3 |  |
| `mopn_gmn` | `MNID mopn_gmn(W dnum)` | `menu.mkn` | あり | 3 | `EX_DNUM` `EX_NOSPC` `EX_PAR` |
| `mdel_gmn` | `ERR mdel_gmn(W mid)` | `menu.mkn` | あり | 1 |  |
| `msel_gmn` | `W msel_gmn(W mid, PNT pos)` | `menu.mkn` | あり | 1 |  |
| `mchg_gat` | `W mchg_gat(W mid, W num, UW mode)` | `menu.mkn` | あり | 2 |  |
| `mchg_dtm` | `W mchg_dtm(W time)` | `menu.mkn` | あり | 0 |  |

## 3.3 パーツマネージャ（33 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `ccre_par` | `PAID ccre_par(W wid, PARTS *parts)` | `parts.mkn` | あり | 5 | `EX_NOSPC` `EX_WID` `EX_DNUM` |
| `ccre_tbx` | `PAID ccre_tbx(W wid, UW ty, RECT *r, W txsize, TC *text, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_xbx` | `PAID ccre_xbx(W wid, UW ty, RECT *r, W txsize, TC *text, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_nbx` | `PAID ccre_nbx(W wid, UW ty, RECT *r, UW fmt, W *val, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_sbx` | `PAID ccre_sbx(W wid, UW ty, RECT *r, TC *fmt, W nfld, W *cv, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_asw` | `PAID ccre_asw(W wid, UW ty, RECT *r, W cv, TC *name, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_msw` | `PAID ccre_msw(W wid, UW ty, RECT *r, TC *name, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_pas` | `PAID ccre_pas(W wid, UW ty, RECT *r, W cv, W onp, W offp, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_pms` | `PAID ccre_pms(W wid, UW ty, RECT *r, W onp, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_sel` | `PAID ccre_sel(W wid, UW ty, RECT *r, W cv, TC *name, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_scr` | `PAID ccre_scr(W wid, UW ty, RECT *r, W cv, TC *name, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `ccre_vol` | `PAID ccre_vol(W wid, UW ty, RECT *r, W *val, W patnum, PARTDISP *atr)` | `parts.mkn` | あり | 0 |  |
| `copn_par` | `PAID copn_par(W wid, W dnum, PNT *pos)` | `parts.mkn` | あり | 5 | `EX_NOSPC` `EX_PAR` |
| `cdel_par` | `ERR cdel_par(W pid, W opt)` | `parts.mkn` | あり | 1 |  |
| `cdel_pwd` | `ERR cdel_pwd(W wid, W opt)` | `parts.mkn` | あり | 1 |  |
| `cdsp_par` | `ERR cdsp_par(W pid, UW vis)` | `parts.mkn` | あり | 2 |  |
| `cdsp_pwd` | `ERR cdsp_pwd(W wid, RECT *r, UW vis)` | `parts.mkn` | あり | 3 |  |
| `cchk_par` | `W cchk_par(W pid, PNT pos)` | `parts.mkn` | あり | 1 |  |
| `cfnd_par` | `W cfnd_par(W wid, PNT pos, W *pid)` | `parts.mkn` | あり | 2 |  |
| `cact_par` | `W cact_par(W pid, WEVENT *ev)` | `parts.mkn` | あり | 2 |  |
| `cget_val` | `W cget_val(W pid, W size, W *value)` | `parts.mkn` | あり | 2 |  |
| `cset_val` | `W cset_val(W pid, W size, W *value)` | `parts.mkn` | あり | 3 |  |
| `cget_dat` | `ERR cget_dat(W pid, W *par)` | `parts.mkn` | あり | 0 |  |
| `cset_dat` | `ERR cset_dat(W pid, W par)` | `parts.mkn` | あり | 3 | `EX_DNUM` |
| `ccut_txt` | `W ccut_txt(W pid, W size, TC *buff, W cut)` | `parts.mkn` | あり | 3 |  |
| `cins_txt` | `W cins_txt(W pid, PNT pos, TC *buff)` | `parts.mkn` | あり | 3 |  |
| `cget_pos` | `ERR cget_pos(W pid, RECT *r)` | `parts.mkn` | あり | 2 |  |
| `cset_pos` | `ERR cset_pos(W pid, RECT *r)` | `parts.mkn` | あり | 3 |  |
| `cget_sts` | `W cget_sts(W pid, W *wid)` | `parts.mkn` | あり | 2 |  |
| `cchg_par` | `ERR cchg_par(W pid, UW cmd)` | `parts.mkn` | あり | 2 | `EX_PAR` |
| `cchg_pwd` | `ERR cchg_pwd(W wid, UW cmd)` | `parts.mkn` | あり | 2 | `EX_PAR` |
| `cidl_par` | `ERR cidl_par(W wid, PNT *pos)` | `parts.mkn` | なし | 2 |  |
| `cexe_par` | `W cexe_par(W pid, WEVENT *ev)` | `parts.mkn` | あり | 2 |  |

## 3.4 パネルマネージャ（12 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `pcre_pnl` | `PNID pcre_pnl(PANEL *pnl, PNT *p)` | `panel.mkn` | あり | 4 |  |
| `popn_pnl` | `PNID popn_pnl(W dnum, PNT *p)` | `panel.mkn` | あり | 5 | `EX_NOSPC` `EX_SAVE` |
| `pdel_pnl` | `ERR pdel_pnl(W pnid)` | `panel.mkn` | あり | 1 |  |
| `pact_pnl` | `W pact_pnl(W pnid, EVENT *ev, W *itemno)` | `panel.mkn` | あり | 2 |  |
| `pget_itm` | `W pget_itm(W pnid, W itemno, PNL_ITEM *item)` | `panel.mkn` | あり | 3 |  |
| `pset_itm` | `W pset_itm(W pnid, W itemno, PNL_ITEM *item)` | `panel.mkn` | あり | 0 |  |
| `psel_box` | `W psel_box(W pnid, W itemno)` | `panel.mkn` | あり | 2 |  |
| `pget_gid` | `GID pget_gid(W pnid)` | `panel.mkn` | あり | 1 |  |
| `pact_err` | `W pact_err(W kind, TC *arg1, TC *arg2, TC *arg3)` | `panel.mkn` | あり | 3 | `EX_SAVE` |
| `pdsp_msg` | `W pdsp_msg(TC *msg)` | `panel.mkn` | あり | 1 |  |
| `pdsp_tim` | `ERR pdsp_tim(UW stat)` | `panel.mkn` | あり | 0 |  |
| `pact_msg` | `ERR pact_msg(WEVENT* ev)` | `panel.mkn` | あり | 1 |  |

## 3.5 トレーマネージャ（10 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `topn_tra` | `ERR topn_tra(void)` | `tray.mkn` | あり | 1 | `EX_NOSPC` |
| `tcls_tra` | `ERR tcls_tra(void)` | `tray.mkn` | あり | 1 |  |
| `tpsh_dat` | `W tpsh_dat(TRAYREC *data, W nrec, TC *name)` | `tray.mkn` | あり | 4 | `EX_NOSPC` |
| `tpop_dat` | `W tpop_dat(TRAYREC *data, W size, W *a_size, W rec, TC *name)` | `tray.mkn` | あり | 3 |  |
| `tdel_dat` | `W tdel_dat(void)` | `tray.mkn` | あり | 1 |  |
| `tsel_dat` | `W tsel_dat(W pos)` | `tray.mkn` | あり | 1 |  |
| `tmov_dat` | `W tmov_dat(W pos)` | `tray.mkn` | あり | 1 |  |
| `tget_sts` | `W tget_sts(UW *size, UW *rsize)` | `tray.mkn` | あり | 2 |  |
| `tset_dat` | `W tset_dat(TRAYREC *data, W nrec)` | `tray.mkn` | あり | 3 | `EX_NOSPC` |
| `tget_dat` | `W tget_dat(TRAYREC *data, W size, W *a_size, W rec)` | `tray.mkn` | あり | 2 |  |

## 3.6 データマネージャ（7 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `dopn_dat` | `W dopn_dat(LINK *lnk)` | `data.mkn` | あり | 4 | `EX_DFMT` `EX_SDATA` |
| `dcls_dat` | `ERR dcls_dat(W fid)` | `data.mkn` | あり | 1 |  |
| `dget_dtp` | `ERR dget_dtp(W type, W dnum, void **datap)` | `data.mkn` | あり | 4 | `EX_DFMT` |
| `dget_siz` | `W dget_siz(B *addr)` | `data.mkn` | あり | 1 |  |
| `dget_num` | `W dget_num(B *addr, W *type)` | `data.mkn` | あり | 2 |  |
| `ddef_dat` | `ERR ddef_dat(W type, W dnum, void *ptr, W size)` | `data.mkn` | あり | 4 | `EX_ADR` `EX_DFMT` `EX_DNUM` `EX_PAR` |
| `ddef_ldt` | `ERR ddef_ldt(W type, W dnum, void *ptr, W size)` | `data.mkn` | あり | 3 | `EX_ADR` `EX_DFMT` `EX_PAR` |

## 3.7 テキスト入力プリミティブ（8 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `ichg_mod` | `WERR ichg_mod(W mode)` | `tip.mkn` | あり | 1 |  |
| `ichg_lrn` | `WERR ichg_lrn(UW kind, W stat)` | `tip.mkn` | あり | 2 |  |
| `iopn_tip` | `WERR iopn_tip(TIPREC *tip, W mode)` | `tip.mkn` | あり | 5 | `EX_NOSPC` |
| `icls_tip` | `ERR icls_tip(W tipid)` | `tip.mkn` | あり | 0 |  |
| `iput_key` | `WERR iput_key(W tipid, EVENT *evt)` | `tip.mkn` | あり | 7 | `EX_LIMIT` |
| `iput_str` | `ERR iput_str(W tipid, TC *str)` | `tip.mkn` | あり | 4 | `EX_KEY` `EX_LIMIT` |
| `ichg_blk` | `WERR ichg_blk(W intvl)` | `tip.mkn` | あり | 0 |  |
| `idsp_car` | `ERR idsp_car(CARET *car, W mode)` | `tip.mkn` | あり | 1 |  |

## 3.8 実身／仮身マネージャ（60 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `oreg_vob` | `VID oreg_vob(VLINK *vlnk, VP vseg, W wid, UW disp)` | `omgr.mkn` | なし | 5 | —（日本語名の関数。要確認） |
| `b_odup_vob` | `VID b_odup_vob(W org)` | `omgr.mkn` | なし | 3 | —（日本語名の関数。要確認） |
| `odel_vob` | `W odel_vob(W vid, W clr)` | `omgr.mkn` | なし | 1 | —（日本語名の関数。要確認） |
| `ocls_wnd` | `ERR ocls_wnd(W wid)` | 未実装 | — | 0 | — |
| `odsp_vob` | `W odsp_vob(W vid, RECT *r, UW disp)` | 未実装 | — | 4 | — |
| `odsp_vor` | `W odsp_vor(W vid, RECT *r, UW disp, PNT scal)` | 未実装 | — | 4 | — |
| `odra_vob` | `ERR odra_vob(VLINK *vlnk, VP vseg, W wid, UW disp)` | 未実装 | — | 4 | — |
| `odra_vor` | `ERR odra_vor(VLINK *vlnk, VP vseg, W wid, UW disp, PNT scal)` | 未実装 | — | 4 | — |
| `ofnd_vob` | `W ofnd_vob(W wid, PNT pos, W *vid)` | 未実装 | — | 2 | — |
| `omov_vob` | `ERR omov_vob(W vid, W wid, RECT *newr, UW disp)` | 未実装 | — | 4 | — |
| `orsz_vob` | `ERR orsz_vob(W vid, RECT *newr, UW mode)` | 未実装 | — | 4 | — |
| `ochg_chs` | `W ochg_chs(W vid, W chsz, RECT *newr, UW mode)` | 未実装 | — | 3 | — |
| `ochg_col` | `ERR ochg_col(W vid, COLOR frcol, COLOR chcol, COLOR tbcol, COLOR bgcol, UW disp)` | 未実装 | — | 2 | — |
| `ochg_nam` | `W ochg_nam(W vid, TC *name)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `ochg_rel` | `W ochg_rel(W vid, W index)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `onew_obj` | `VID onew_obj(W vid, VLINK *vlnk)` | 未実装 | — | 4 | — |
| `ocre_obj` | `W ocre_obj(W vid, TC *name, W *nvid, LINK *lnk, W copy)` | `omgr.mkn` | あり | 4 | —（日本語名の関数。要確認） |
| `odsp_inf` | `ERR odsp_inf(W vid)` | 未実装 | — | 3 | — |
| `odsk_inf` | `ERR odsk_inf(W vid, W used, W gabage)` | 未実装 | — | 2 | — |
| `oget_vob` | `W oget_vob(W vid, VLINK *vlnk, VP vseg, UW size, UW *rsize)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `ochg_sts` | `W ochg_sts(W vid, UW mode)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `osta_prc` | `ERR osta_prc(W vid, W wid)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `oend_prc` | `GID oend_prc(W vid, VP dat, W update)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `oend_req` | `ERR oend_req(W vid, W stat)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `oreq_prc` | `W oreq_prc(W wid, W req, B *resp)` | 未実装 | — | 3 | — |
| `orsp_prc` | `ERR orsp_prc(EVENT *evt, B *resp, UW size, W status)` | 未実装 | — | 2 | — |
| `oput_dat` | `ERR oput_dat(W vid)` | 未実装 | — | 2 | — |
| `oupd_fil` | `ERR oupd_fil(W vid, LINK *lnk, W update)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `oset_tmf` | `ERR oset_tmf(LINK *lnk)` | `omgr.mkn` | あり | 1 | —（日本語名の関数。要確認） |
| `oget_men` | `ERR oget_men(W vid, TC **emenu, TC **tmenu, TC **vmenu, TC **fmenu)` | 未実装 | — | 3 | — |
| `oget_vmn` | `ERR oget_vmn(W vid, TC **emenu, TC **tmenu, TC **vmenu, TC **omenu, TC **dmenu, TC **fmenu)` | 未実装 | — | 3 | — |
| `oexe_vmn` | `W oexe_vmn(W vid, W item, VP buf)` | 未実装 | — | 4 | — |
| `ochg_env` | `W ochg_env(LINK *lnk, W wid)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `oget_env` | `WID oget_env(LINK *lnk)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `oreg_apg` | `ERR oreg_apg(LINK *lnk)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `odel_apg` | `ERR odel_apg(LINK *lnk)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `oset_sea` | `W oset_sea(W cnt, LINK *lnk)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `oget_sea` | `W oget_sea(W cnt, LINK *lnk)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `ofnd_apg` | `W ofnd_apg(VLINK *vlnk, LINK *lnk, TC *dtype, W cnt)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `oexe_apg` | `W oexe_apg(W vid, W item)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `odet_fls` | `ERR odet_fls(TC *dev, W eject)` | `omgr.mkn` | あり | 1 | —（日本語名の関数。要確認） |
| `ofdt_fls` | `ERR ofdt_fls(TC *dev, W eject)` | 未実装 | — | 2 | — |
| `oatt_fls` | `ERR oatt_fls(TC *dev, TC *name, LINK *lnk, W ronly)` | `omgr.mkn` | あり | 1 | —（日本語名の関数。要確認） |
| `ofat_fls` | `ERR ofat_fls(TC *dev, TC *name, LINK *lnk, W ronly)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `odet_vob` | `W odet_vob(W vid, TC *dev)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `oatt_vob` | `W oatt_vob(W vid, W ronly)` | `omgr.mkn` | あり | 2 | —（日本語名の関数。要確認） |
| `oprc_dev` | `ERR oprc_dev(EVENT *evt, TC *dev, W ronly)` | 未実装 | — | 2 | — |
| `ofmt_vob` | `W ofmt_vob(W vid)` | 未実装 | — | 2 | — |
| `ocnv_vob` | `W ocnv_vob(W org, W vid, LINK *lnk)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `oopn_obj` | `W oopn_obj(W vid, LINK *lnk, UW omode, TC *pwd)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `odel_obj` | `W odel_obj(LINK *lnk, W mode)` | `omgr.mkn` | なし | 1 | —（日本語名の関数。要確認） |
| `oget_fsn` | `ERR oget_fsn(W vid, W fd, VP dat, UW size)` | `omgr.mkn` | あり | 4 | —（日本語名の関数。要確認） |
| `oput_fsn` | `ERR oput_fsn(W vid, W fd, VP dat)` | `omgr.mkn` | あり | 3 | —（日本語名の関数。要確認） |
| `ocre_chd` | `W ocre_chd(W vid, TC *name, W *nvid)` | 未実装 | — | 4 | — |
| `otad_vob` | `W otad_vob(W vid, RECT *r, UW disp, LINK *lnk)` | 未実装 | — | 4 | — |
| `aset_sel` | `W aset_sel(W period)` | 未実装 | — | 0 | — |
| `adsp_sel` | `ERR adsp_sel(GID gid, SEL_RGN *selp, W mode)` | 未実装 | — | 1 | — |
| `adsp_slt` | `ERR adsp_slt(GID gid, SEL_LIST *selp, W mode, W dh, W dv)` | 未実装 | — | 1 | — |
| `apnl_men` | `W apnl_men(W pnid, W pid, EVENT *epv)` | 未実装 | — | 1 | — |
| `achg_bgc` | `W achg_bgc(W *mask, COLOR *color, COLOR bgc)` | 未実装 | — | 1 | — |

## 3.9 フォントマネージャ（14 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `fdef_fnt` | `WERR fdef_fnt(FLOC loc, W spec)` | `font.mkn` | あり | 7 | `EX_FTID` `EX_NOSPC` |
| `fdel_fnt` | `ERR fdel_fnt(FID fid)` | `font.mkn` | あり | 1 |  |
| `fdel_loc` | `WERR fdel_loc(FLOC loc, W spec)` | `font.mkn` | あり | 2 |  |
| `fget_def` | `WERR fget_def(FID fid, FDEF *def)` | `font.mkn` | あり | 2 |  |
| `fget_not` | `WERR fget_not(FID fid, B *buff, UW len)` | `font.mkn` | あり | 3 |  |
| `flst_fon` | `WERR flst_fon(FID fid, W mode, FLIST *buff, UW len)` | `font.mkn` | あり | 3 |  |
| `fopn_fon` | `WERR fopn_fon()` | `font.mkn` | あり | 1 |  |
| `fcls_fon` | `ERR fcls_fon(W fdesc)` | `font.mkn` | あり | 0 |  |
| `fset_fon` | `ERR fset_fon(W fdesc, FSSPEC *spec)` | `font.mkn` | あり | 3 |  |
| `fget_fon` | `ERR fget_fon(W fdesc, FSSPEC *spec)` | `font.mkn` | あり | 2 |  |
| `fset_ang` | `ERR fset_ang(W fdesc, W ang);` | `font.mkn` | あり | 2 |  |
| `fget_ang` | `WERR fget_ang(W fdesc);` | `font.mkn` | あり | 1 |  |
| `fget_fam` | `WERR fget_fam(W fdesc, W script, FNTINFO *inf);` | `font.mkn` | あり | 3 |  |
| `fget_img` | `WERR fget_img(W fdesc, FDATA *cimg, W size, W script, TC ch, UW mode)` | `font.mkn` | あり | 4 |  |

## 3.10 TCP/IP マネージャ（28 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `so_start` | `ERR so_start (W arg)` | `tcpip.mkn` | あり | 0 |  |
| `so_finish` | `ERR so_finish (W arg)` | `tcpip.mkn` | あり | 2 | `ER_BUSY` |
| `so_accept` | `WERR so_accept (W s, SOCKADDR *nam, W *namlen)` | `tcpip.mkn` | あり | 5 | `EX_NOBUFS` |
| `so_bind` | `ERR so_bind (W s, SOCKADDR *nam, W namlen)` | `tcpip.mkn` | あり | 6 | `EX_FAULT` |
| `so_close` | `ERR so_close (W s)` | `tcpip.mkn` | あり | 2 | `EX_PAR` |
| `so_connect` | `ERR so_connect (W s, SOCKADDR *nam, W namlen)` | `tcpip.mkn` | あり | 8 | `EX_PAR` `EX_FAULT` `EX_INPROGRESS` `EX_TIMEDOUT` `EX_CONNABORTED` |
| `so_fcntl` | `WERR so_fcntl (W s, W cmd, W arg)` | `tcpip.mkn` | あり | 2 |  |
| `so_gethostbyname` | `ERR so_gethostbyname (B *nam, HOSTENT *hp, B *buf)` | `tcpip.mkn` | あり | 3 | `EX_TIMEDOUT` |
| `so_gethostbyaddr` | `ERR so_gethostbyaddr (B *addr, W type, W len, HOSTENT *hp, B *buf)` | `tcpip.mkn` | あり | 2 |  |
| `so_getpeername` | `ERR so_getpeername (W s, SOCKADDR *nam, W *namlen)` | `tcpip.mkn` | あり | 4 | `EX_ADR` `EX_PAR` `EX_BADF` `EX_FAULT` |
| `so_getsockname` | `ERR so_getsockname (W s, SOCKADDR *nam, W *namlen)` | `tcpip.mkn` | あり | 4 | `EX_ADR` `EX_PAR` `EX_BADF` `EX_FAULT` |
| `so_getsockopt` | `ERR so_getsockopt (W s, W level, W optnam, B *optval, W *optlen)` | `tcpip.mkn` | あり | 5 | `EX_PAR` `EX_FAULT` |
| `so_ioctl` | `WERR so_ioctl (W s, W request, W arg)` | `tcpip.mkn` | あり | 3 |  |
| `so_listen` | `ERR so_listen (W s, W backlog)` | `tcpip.mkn` | あり | 2 |  |
| `so_read` | `WERR so_read (W s, B *buf, W len)` | `tcpip.mkn` | あり | 7 | `EX_ADR` `EX_PAR` `EX_BADF` `EX_WOULDBLOCK` `EX_TIMEDOUT` `EX_CONNABORTED` `EX_OPNOTSUP` |
| `so_recv` | `WERR so_recv (W s, B *buf, W len, W flags)` | `tcpip.mkn` | あり | 7 | `EX_ADR` `EX_PAR` `EX_BADF` `EX_WOULDBLOCK` `EX_TIMEDOUT` `EX_CONNABORTED` `EX_OPNOTSUP` |
| `so_recvfrom` | `WERR so_recvfrom (W s, B *buf, W len, W flags, SOCKADDR *from, W *flen)` | `tcpip.mkn` | あり | 7 | `EX_ADR` `EX_PAR` `EX_BADF` `EX_WOULDBLOCK` `EX_TIMEDOUT` `EX_CONNABORTED` `EX_OPNOTSUP` |
| `so_recvmsg` | `WERR so_recvmsg (W s, MSGHDR *msg, W flags)` | `tcpip.mkn` | あり | 7 | `EX_PAR` `EX_BADF` `EX_WOULDBLOCK` `EX_TIMEDOUT` `EX_CONNABORTED` `EX_OPNOTSUP` |
| `so_select` | `WERR so_select (W nfds, fd_set *rfds, fd_set *wfds, fd_set *efds, TIMEVAL *tmout)` | `tcpip.mkn` | あり | 1 |  |
| `so_write` | `WERR so_write (W s, B *buf, W len)` | `tcpip.mkn` | あり | 9 | `EX_ADR` `EX_PAR` `EX_BADF` `EX_SHUTDOWN` `EX_CONNABORTED` `EX_MSGSIZE` `EX_NOBUFS` `EX_WOULDBLOCK` `EX_TIMEOUT` |
| `so_send` | `WERR so_send (W s, B *buf, W len, W flags)` | `tcpip.mkn` | あり | 9 | `EX_ADR` `EX_PAR` `EX_BADF` `EX_SHUTDOWN` `EX_CONNABORTED` `EX_MSGSIZE` `EX_NOBUFS` `EX_WOULDBLOCK` `EX_TIMEOUT` |
| `so_sendto` | `WERR so_sendto (W s, B *buf, W len, W flags, SOCKADDR *to, W tolen)` | `tcpip.mkn` | あり | 11 | `EX_ADR` `EX_PAR` `EX_BADF` `EX_SHUTDOWN` `EX_CONNABORTED` `EX_MSGSIZE` `EX_NOBUFS` `EX_WOULDBLOCK` `EX_TIMEOUT` `EX_HOSTUNREACH` `EX_DESTADDRREQ` |
| `so_sendmsg` | `WERR so_sendmsg (W s, MSGHDR *msg, W flags)` | `tcpip.mkn` | あり | 10 | `EX_PAR` `EX_BADF` `EX_SHUTDOWN` `EX_CONNABORTED` `EX_MSGSIZE` `EX_NOBUFS` `EX_WOULDBLOCK` `EX_TIMEOUT` `EX_HOSTUNREACH` |
| `so_shutdown` | `ERR so_shutdown (W s, W how)` | `tcpip.mkn` | あり | 3 | `EX_NOBUFS` |
| `so_socket` | `WERR so_socket (W domain, W type, W protocol)` | `tcpip.mkn` | あり | 2 |  |
| `so_sethostname` | `ERR so_sethostname (B *name, W nlen)` | `tcpip.mkn` | あり | 1 |  |
| `so_setsockopt` | — | `tcpip.mkn` | あり | 0 |  |
| `so_gethostname` | — | `tcpip.mkn` | あり | 0 |  |

## 3.11 印刷マネージャ（9 関数）

| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |
|---|---|---|---|---|---|
| `rset_par` | `WERR rset_par(TC *prname, PR_PAR *prpar, LINK *fout)` | `prn.mkn` | あり | 2 |  |
| `rprn_fil` | `WERR rprn_fil(TC *prname, LINK *lnk, PR_PAR *prpar, UW mode)` | `prn.mkn` | あり | 2 |  |
| `rout_fil` | `ERR rout_fil(TC *prname, LINK *lnk, PR_PAR *prpar, LINK *fout)` | `prn.mkn` | あり | 2 | `EX_NOEXS` |
| `rpvw_fil` | `ERR rpvw_fil(TC *prname, LINK *lnk, PR_PAR *prpar)` | `prn.mkn` | あり | 2 | `EX_ADR` `EX_NOEXS` |
| `rcan_ent` | `WERR rcan_ent(TC *prname, W prid)` | `prn.mkn` | あり | 3 |  |
| `rget_ent` | `WERR rget_ent(TC *prname, W prid, PR_STAT *stat, W cnt)` | `prn.mkn` | あり | 3 |  |
| `rlst_prn` | `WERR rlst_prn(PR_INFO *info, W cnt)` | `prn.mkn` | あり | 1 |  |
| `rget_cnf` | `WERR rget_cnf(TC *prname, PR_CONF *cnf)` | `prn.mkn` | あり | 2 |  |
| `rset_cnf` | `ERR rset_cnf(TC *prname, PR_CONF *cnf)` | `prn.mkn` | あり | 5 |  |

