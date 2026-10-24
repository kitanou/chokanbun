# BTRON3 互換層の `ER_*` 網羅表

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) / 試験計画: [btron3-test-plan.md](btron3-test-plan.md)
> 対象: BTRON3仕様書 Ver. 3.20.00 第2編 第1章 1.1〜1.10 の実装済み API。
> 作成: 2026-10-22、更新: 2026-10-23。`ER_*` の名称と、各 QEMU 試験が直接参照しているエラーを対応づける。

## 0. 範囲と読み方

- 対象は核の `ER_*` のみ。実身／仮身マネージャの `EX_*` は別体系（`user/btron/er.mkn` の eclass `0xFFFE`）なので、この表には含めない。`実試` の `EX_*` は [btron3-os.md](btron3-os.md) の 3.8 で扱う。
- 「仕様・実装メモ」欄は、原文を直接確認した [btron3-spec-verification.md](btron3-spec-verification.md) と API 照合の [btron3-os.md](btron3-os.md) に記載された `ER_*` を整理したもの。原文のエラー表をすべて再走査した表ではない。原文の記載が未整理の条件は「—」または「未整理」とした。
- 「直接確認」は、試験の題または期待値にその `ER_*` が明示されているものを指す。文字列の静的抽出なので、実行時に必ずその分岐を通ることを証明するものではない。子行程の戻り値としてだけ現れるものは、その試験の欄に含めた。
- `ER_NONE` はエラーではなく時間切れ・該当なし、`ER_MINTR` はメッセージハンドラによる待ちの中断を表す。どちらも呼出し側では負の値として観測されるため、この表に含める。
- `ER_*` の数値は仕様で規定されていない。`user/btron/er.mkn` の選択（`eclass=-1`、`detail=1` 始まり）と、漢令の errno からの変換表が実装の正本である。

## 1. 集計

| 項目 | 数 |
|---|---:|
| `user/btron/er.mkn` が定義する `ER_*` | 42 |
| 互換層の試験と `時元試` が参照する `ER_*` | 37 |
| どの試験も参照していない `ER_*` | 5 |
| BTRON3 互換層の QEMU 試験 | 17 種・689 項目 |

未参照の 5 名は `ER_ERDEV`・`ER_IO`・`ER_NODSK`・`ER_NOMDA`・`ER_XFS`。理由と次の一手は §4 にまとめる。

`ER_NODEV` は互換層の 17 種には現れないが、RTC 無効の起動で `時元試`（`user/time_test.mkn`）が `get_tim` の戻り値として直接確認している。このため「未参照」には数えない。

## 2. API 別の対応

凡例: 「記載」は仕様・実装メモにある主な `ER_*`、「直接確認」は試験で題・期待値に現れる `ER_*`、「不足」は記載があるのに直接確認がないもの、または実装・原文の条件が未整理のもの。試験名の略号は §3 の表と同じ。

### 1.1 プロセス／タスク管理

| API | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `get_tid` | エラー規定なし | 識 | — | なし |
| `cre_prc`（LINK 版） | `ER_PPRI` `ER_SZOVR` `ER_ADR` `ER_REC` `ER_NOEXS` `ER_NOFS` `ER_ACCES` `ER_BUSY` | 録 | `ER_PPRI` `ER_SZOVR` `ER_ADR` `ER_REC` `ER_NOEXS` `ER_NOFS` `ER_BUSY` | `ER_ACCES` |
| `ext_prc` | エラー規定なし | 信 | — | なし |
| `ter_prc` | `ER_SELF` `ER_NOPRC` `ER_LEVEL` `ER_PAR` | 強 | 全て | なし |
| `chg_pri` | `ER_PPRI` `ER_PAR` `ER_NOPRC` `ER_ID` | 強 | 全て | なし |
| `prc_sts` | `ER_NOPRC` `ER_ADR` | 強 | 両方 | なし |
| `get_usr` | `ER_NOPRC` `ER_ADR` | 利 | 両方 | なし |
| `chg_usr` | `ER_ACCES` | 利 | `ER_ACCES` | なし（level 0 以外の拒否は解釈） |
| `get_inf` | `ER_NOPRC` `ER_ADR` | 強 | 両方 | なし |
| `slp_tsk` | `ER_PAR` `ER_NONE`、`MH_BREAK` 時は `ER_MINTR` | 強 | `ER_PAR` `ER_NONE` | `ER_MINTR` |
| `dly_tsk` | `ER_PAR`、`MH_BREAK` 時は `ER_MINTR` | 強 | `ER_PAR` | `ER_MINTR` |
| `wup_tsk` / `can_wup` | `ER_ID` | 強・副 | `ER_ID` | なし |
| `cre_tsk` / `ext_tsk` / `ter_tsk` | `ER_ADR` `ER_PPRI` `ER_LIMIT` `ER_NOMEM` `ER_ID` | 副 | `ER_ADR` `ER_PPRI` `ER_LIMIT` `ER_ID` | `ER_NOMEM`（頁の枯渇を作れない） |

### 1.2 メッセージ管理

| API | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `snd_msg` | `ER_SELF` `ER_NOPRC` `ER_SZOVR` `ER_NOSPC` `ER_PAR` `ER_ADR` | 信 | 全て | `CONFM` 待ちの `ER_MINTR` は直接確認なし |
| `rcv_msg` | `ER_PAR` `ER_NOME` `ER_NONE` `ER_SZOVR` `ER_MINTR` | 信・信手 | 全て | なし |
| `clr_msg` | `ER_PAR` | 信 | `ER_PAR` | なし |
| `req_tmg` / `can_tmg` | `ER_PAR` `ER_NOSPC` | 信 | 両方 | なし |
| `def_msg` / `ret_msg` | `ER_PAR` `ER_ADR` `ER_CTX` | 信手 | 全て | なし |
| `brk_msg` | `ER_NOME` | 信 | `ER_NOME` | なし |

### 1.3 同期通信管理

| API 群 | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `cre_sem` `del_sem` `sig_sem` `wai_sem` | `ER_PAR` `ER_ID` `ER_NOEXS` `ER_DLT` `ER_LIMIT` `ER_NONE` `ER_OBJ` `ER_MINTR` | 同 | 全て | なし |
| `cre_flg` `del_flg` `set_flg` `clr_flg` `wai_flg` | 上と同じ（`ER_OBJ` は排他セマフォ用） | 同 | 全て | なし。同じフラグへの複数待ちは未試験 |
| `cre_mbf` `del_mbf` `snd_mbf` `rcv_mbf` | `ER_PAR` `ER_ADR` `ER_ID` `ER_NOEXS` `ER_DLT` `ER_NONE` `ER_OBJ` `ER_MINTR` | 緩 | 全て | なし |
| `cre_por` `del_por` `cal_por` `acp_por` `fwd_por` `rpl_rdv` | `ER_PAR` `ER_ADR` `ER_ID` `ER_NOEXS` `ER_DLT` `ER_NONE` `ER_OBJ` `ER_MINTR` | 緩 | 全て | 受付側が返答せず終了する経路は仕様未確認 |

### 1.4 グローバル名管理

| API | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `cre_nam` | `ER_EXS` `ER_NOEXS` `ER_NOSPC` `ER_PAR` `ER_ADR` | 名 | 全て | なし |
| `del_nam` | `ER_NOEXS` | 名 | `ER_NOEXS` | なし |
| `get_nam` | `ER_NOEXS` `ER_ADR` | 名 | 両方 | なし（戻り動作の原文欠落は別途要確認） |

### 1.5 メモリ管理

| API | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `get_mbk` | `ER_PAR` `ER_ADR` `ER_LIMIT` `ER_NOMEM` `ER_CTX` | 貯 | `ER_PAR` `ER_ADR` `ER_NOMEM` `ER_CTX` | `ER_LIMIT`（塊表 32 項満杯・共有域 8 頁づまり） |
| `rel_mbk` | `ER_MPTR` `ER_CTX` | 貯 | 両方 | なし |
| `mbk_sts` | `ER_ADR` | 貯 | `ER_ADR` | なし |
| `malloc` 系 18 関数 | 失敗は NULL。内部で `ER_CTX` `ER_MPTR` などを返す | 貯 | `ER_CTX` `ER_MPTR` | `ER_LIMIT`（塊表満杯・共有域づまり）。`ER_NOMEM` は `get_mbk` 側で確認 |

### 1.6 ファイル管理

| API 群 | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `get_lnk` `chg_wrk` | `ER_ADR` `ER_NOEXS` `ER_NOFS` `ER_ACCES` | 録 | `ER_ADR` `ER_NOEXS` `ER_NOFS` | `ER_ACCES` の専用項目なし |
| `cre_fil` `cre_lnk` `gen_fil` | `ER_FNAME` `ER_PAR` `ER_ADR` `ER_NOEXS` `ER_NOFS` `ER_EXS` `ER_RONLY` `ER_SZOVR` `ER_LIMIT` `ER_REC` `ER_ACCES` | 録 | `ER_FNAME` `ER_PAR` `ER_ADR` `ER_NOEXS` `ER_NOFS` `ER_EXS` `ER_RONLY` `ER_SZOVR` `ER_LIMIT` `ER_REC` `ER_ACCES` | なし |
| `del_fil` | `ER_BUSY` `ER_LOCK` `ER_PERM` `ER_REC` `ER_NOEXS` `ER_ACCES` | 録 | `ER_BUSY` `ER_LOCK` `ER_PERM` `ER_REC` `ER_NOEXS` `ER_ACCES` | なし |
| `opn_fil` / `cls_fil` | `ER_NOEXS` `ER_PAR` `ER_ADR` `ER_NOFS` `ER_BUSY` `ER_RONLY` `ER_ACCES` `ER_PWD` `ER_FD` `ER_LIMIT` | 録 | `ER_NOEXS` `ER_PAR` `ER_ADR` `ER_NOFS` `ER_BUSY` `ER_RONLY` `ER_ACCES` `ER_PWD` `ER_FD` `ER_LIMIT` | なし |
| レコード操作（`see_rec`〜`trc_rec`） | `ER_PAR` `ER_ADR` `ER_FD` `ER_ENDR` `ER_REC` `ER_LOCK` `ER_BUSY` `ER_SZOVR` | 録 | 全て | なし |
| `loc_rec` / `xch_fil` | `ER_PAR` `ER_FD` `ER_LOCK` `ER_BUSY` `ER_XFS` | 録 | `ER_PAR` `ER_FD` `ER_LOCK` `ER_BUSY` | `ER_XFS`（別 FS） |
| `fil_sts` / `ofl_sts` | `ER_ADR` `ER_FD` | 録 | 両方 | なし |
| ファイルシステム（`att_fls`〜`chg_fsm`） | `ER_EXS` `ER_BUSY` `ER_NOFS` `ER_NOEXS` `ER_ACCES` `ER_TRON` `ER_RONLY` `ER_FNAME` `ER_PAR` `ER_NODEV` `ER_NOMDA` | 録 | `ER_EXS` `ER_BUSY` `ER_NOFS` `ER_NOEXS` `ER_ACCES` `ER_TRON` `ER_RONLY` `ER_FNAME` `ER_PAR` | `ER_NODEV` `ER_NOMDA` |
| `map_rec` / `ump_rec` | `ER_FD` `ER_NOSPT` `ER_PAR` `ER_ADR` `ER_ENDR` `ER_REC` `ER_LOCK` `ER_BUSY` `ER_NOEXS` | 録 | 全て | なし |

### 1.7 イベント管理

| API 群 | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `get_evt` `put_evt` `clr_evt` `req_evt` `las_evt` | `ER_PAR` `ER_ADR` `ER_NOSPC` `ER_NODEV` `ER_BUSY` `ER_ERDEV` `ER_IO` | 件 | `ER_PAR` `ER_ADR` `ER_NOSPC` | 実機依存の `ER_NODEV` `ER_BUSY` `ER_ERDEV` `ER_IO` |
| `get_kmp` `set_krp` `get_krp` `set_krm` `get_krm` `get_kid` `get_ktb` `set_ktb` | `ER_PAR` `ER_ADR` `ER_NODEV` `ER_BUSY` `ER_ERDEV` `ER_IO` | 件 | `ER_PAR` `ER_ADR` | 実機依存の 4 名 |
| `get_pdp` `set_pdp` `chg_pda` `sig_buz` `ctl_buz` | `ER_PAR` `ER_ADR` `ER_NODEV` `ER_ERDEV` `ER_IO` | 件 | `ER_PAR` | 実機依存の 3 名、`ER_ADR` の専用項目なし |

### 1.8 デバイス管理

| API | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `opn_dev` | `ER_PAR` `ER_ADR` `ER_NOEXS` `ER_BUSY` `ER_ACCES` `ER_RONLY` `ER_DEV` `ER_DD` `ER_LIMIT` `ER_NODEV` | 設 | `ER_PAR` `ER_ADR` `ER_NOEXS` `ER_BUSY` `ER_ACCES` `ER_RONLY` `ER_DEV` `ER_DD` `ER_LIMIT` | `ER_NODEV` |
| `rea_dev` / `wri_dev` | `ER_PAR` `ER_ADR` `ER_DD` `ER_DEV` `ER_RONLY` `ER_BUSY` `ER_IO` | 設 | `ER_PAR` `ER_ADR` `ER_DD` `ER_DEV` `ER_RONLY` `ER_BUSY` | `ER_IO` |
| `chg_dmd` | `ER_ACCES` `ER_PAR` `ER_NOEXS` | 設 | 全て | なし |
| `dev_sts` `get_dev` `lst_dev` | `ER_ADR` `ER_PAR` `ER_NOEXS` | 設 | 全て | なし |
| `sus_dev` | `ER_PAR` `ER_BUSY` `ER_LIMIT` | 設 | `ER_PAR` `ER_BUSY` | `ER_LIMIT`（禁止カウンタ 32767） |

### 1.9 時計管理

| API | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `get_tim` / `get_tod` | `ER_ADR` `ER_NODEV` | 時・時元 | `ER_ADR`、`get_tim` の `ER_NODEV`（RTC 無効） | `get_tod` の `ER_NODEV`（`get_tim` は確認済み） |
| `set_tim` / `set_tod` | `ER_ACCES` `ER_ADR` `ER_PAR` | 利 | 全て | なし |

### 1.10 システム管理

| API | 記載 | 試験 | 直接確認 | 不足 |
|---|---|---|---|---|
| `def_exc` / `ret_exc` | `ER_PAR` `ER_ADR` `ER_CTX` | 例 | 全て | なし |
| `get_ver` | `ER_ADR` | 系 | `ER_ADR` | なし |
| `get_cnf` | `ER_NOEXS` `ER_ADR` `ER_PAR` | 系 | 全て | なし |

## 3. `ER_*` 索引

試験名の略号: 識=`btron_gtid.mkn`、名=`btron_gname.mkn`、時=`btron_clk.mkn`、時元=`time_test.mkn`、信=`btron_msg.mkn`、利=`btron_usr.mkn`、強=`btron_term.mkn`、同=`btron_sync.mkn`、緩=`btron_comm.mkn`、録=`btron_file.mkn`、貯=`btron_mem.mkn`、件=`btron_evt.mkn`、設=`btron_dev.mkn`、系=`btron_sys.mkn`、例=`btron_exc.mkn`、信手=`btron_msg_hdr.mkn`、実=`btron_omgr.mkn`。

| `ER_*` | 直接参照する試験 | 主な発生条件・API |
|---|---|---|
| `ER_ACCES` | 利・録・設・時元 | 利用者レベルの不足、`chg_usr`・FS 接続権・`chg_dmd`・`set_tim`/`set_tod` |
| `ER_ADR` | 識・名・時・時元・信・利・強・緩・録・貯・件・設・系・例・信手 | 窓外・未整列・書込先不正などの番地検査 |
| `ER_BUSY` | 録・設 | ファイル・デバイスの排他、使用中、作業ファイル |
| `ER_CTX` | 貯・例・信手 | 権限（システム塊）、例外文脈・メッセージ文脈の外 |
| `ER_DD` | 設 | 開法と逆の読み書き（向きの不一致） |
| `ER_DEV` | 設 | デバイスの向き（読否など） |
| `ER_DLT` | 同・緩 | 待ち対象の削除 |
| `ER_ENDR` | 録 | 終端レコードへの操作 |
| `ER_ERDEV` | — | デバイス自体の異常。模型では返さない |
| `ER_EXS` | 名・録 | 名前・ファイル ID の重複 |
| `ER_FD` | 録 | 記述子不正・モード不一致・閉じた記述子 |
| `ER_FNAME` | 録 | ファイル名の不正・長すぎ |
| `ER_ID` | 強・副・同・緩 | 不正な ID、種違い、副タスクでない対象 |
| `ER_IO` | — | 装置の入出力エラー・時間切れ |
| `ER_LEVEL` | 強 | 利用者レベルの上下関係 |
| `ER_LIMIT` | 同・録・設 | オブジェクト数・表・記述子・ファイル数・ロックの上限 |
| `ER_LOCK` | 録 | レコードロックの衝突 |
| `ER_MINTR` | 同・緩・信手 | `MH_BREAK` による待ちの中断 |
| `ER_MPTR` | 貯 | 塊でない番地・持主でない塊の解放 |
| `ER_NODEV` | 時元 | 装置が無い（RTC 無効の `get_tim` など） |
| `ER_NODSK` | — | ディスク容量不足。現在の録層は `ER_SZOVR`/`ER_NOMEM` で代替 |
| `ER_NOEXS` | 識・名・同・緩・録・設・系・実 | 名前・ID・オブジェクト・項目が無い |
| `ER_NOFS` | 録・実 | ファイルシステムが接続されていない |
| `ER_NOLNK` | 録 | リンクファイルでない対象へのリンク操作 |
| `ER_NOMDA` | — | 媒体が無い。取外し媒体の模型が無い |
| `ER_NOME` | 信 | `WAIEVT` に該当メッセージが無い |
| `ER_NOMEM` | 貯 | ローカル塊域の枯渇 |
| `ER_NONE` | 信・強・同・緩・件・信手 | 時間切れ・該当なし（エラーではない） |
| `ER_NOPRC` | 信・利・強 | 行程が無い・終了済み |
| `ER_NOSPC` | 名・信・件 | 名前表・メッセージキュー・時限表・イベント要求表の満杯 |
| `ER_NOSPT` | 録 | 未対応の写像（`F_SYSTEM` など） |
| `ER_OBJ` | 同・緩 | オブジェクトの状態不正（排他セマフォの二重取得など） |
| `ER_PAR` | 識・名・時元・信・利・強・同・緩・録・貯・件・設・系・例・信手 | 引数の不正・範囲外・余計ビット |
| `ER_PERM` | 録 | 削除禁止・ルート削除など |
| `ER_PPRI` | 強・録 | 優先度の範囲外・群の外 |
| `ER_PWD` | 録 | パスワードの不一致・未指定 |
| `ER_REC` | 録 | レコード・実行形式・リンクの内容不正 |
| `ER_RONLY` | 録・設 | 読取専用 FS・書禁媒体 |
| `ER_SELF` | 信・強 | 自分宛の禁止操作・自分自身の強制終了 |
| `ER_SZOVR` | 信・録・時元 | メッセージ本体・ファイル本文・時刻文字列の大きさ超過 |
| `ER_TRON` | 録 | TRON 形式でないファイルシステム |
| `ER_XFS` | — | 別のファイルシステムをまたぐ操作（`xch_fil`） |

## 4. 未検証の `ER_*`

| `ER_*` | 発生するはずの条件 | 現状 | 次の一手 |
|---|---|---|---|
| `ER_ERDEV` | 1.7・1.8 のデバイス自体の異常 | 核内の模型は `ER_ERDEV` を返さない | 実機ドライバか故障注入を入れる。それまでは「模型の制限」として記録 |
| `ER_IO` | 1.8 のデバイス読み書き（virtio-blk）の入出力エラー／時間切れ | `kernel/proc/dev.mkn` に経路はあるが、試験がない | virtio の異常応答・タイムアウトを注入する試験を追加する |
| `ER_NODSK` | 1.6 のディスク容量不足 | 録層は容量超過を `ER_SZOVR`、頁不足を `ER_NOMEM` にしている | 原文の条件と errno 対応を決め、`ER_NODSK` を返す経路を作るか「非対応」と明記する |
| `ER_NOMDA` | 1.6・1.8 の媒体無し | 取外し可能媒体の模型が無い | 媒体の着脱を模型に足すか、対象外と明記する |
| `ER_XFS` | 1.6 の `xch_fil` で別 FS の記述子を渡す | 実装経路はあるが、書込可能な FS が 1 つしかない | 2 つ目の書込可能 FS（RAM の別ユニットなど）を用意して 1 件試す |

## 5. 名前はあるが直接確認がない条件

未参照の 5 名とは別に、`ER_*` 自体は他の試験で参照されていても、特定の API・条件では直接確認がないものがある。2026-10-23 に `gen_fil` の `ER_ACCES`、`del_fil` の `ER_LOCK`、`opn_fil` の `ER_LIMIT`、`xch_fil` の `ER_LOCK`、`cre_prc` の `ER_BUSY` を `録試` に追加した。

| API・条件 | 不足している `ER_*` | 補う試験の案 |
|---|---|---|
| `cre_prc` の権限 | `ER_ACCES` | SYS の像ファイルは FS のアクセス管理レベル 0 で、`A_MODE` が常に一般 0x0FFF に整えられるため、実行権を絞れない。レベル 1 以上の FS に像ファイルを置く仕組みが要る |
| `snd_msg` の `CONFM` 待ち中断 | `ER_MINTR` | 既存の `信手試` の `MH_BREAK` を `CONFM` 送信側にも広げる |
| `slp_tsk` / `dly_tsk` の待ち中断 | `ER_MINTR` | ハンドラから `MH_BREAK` を送る子を 1 役足す |
| `get_mbk` / `malloc` の上限 | `ER_LIMIT` | 塊表 32 項満杯、共有域 8 頁づまりを順に作る |
| FS 操作の装置・媒体 | `ER_NODEV` `ER_NOMDA` | §4 の模型・構成待ち |
| `xch_fil` の別 FS | `ER_XFS` | 2 つ目の書込可能 FS を接続して試す |
| `sus_dev` の禁止カウンタ上限 | `ER_LIMIT` | `D_DISSUS` を 32767 回行い、次を試す |

## 6. 維持方法

- `user/btron/er.mkn` に `ER_*` を足したら、§2 の該当 API 行と §3 の索引を更新する。名称の追加は数値の通し番号を変えない。
- 試験を足したら、§2 の「直接確認」と §4・§5 を同じコミットで更新する。項目数を変えた場合は [btron3-test-plan.md](btron3-test-plan.md) §4 と `tests/run_tests.sh` の固定値も更新する。
- 静的な抽出は次のコマンドで再現できる。`ER_` の直前に別の識別子の文字が付いたものを除外するため、境界を含めて検索する。

```sh
for f in user/btron_*.mkn user/time_test.mkn; do
  printf '%s\t' "$(basename "$f")"
  grep -oE '(^|[^A-Z0-9_])ER_[A-Z0-9_]+' "$f" |
    sed -E 's/^[^E]*//' | sort -u | tr '\n' ' '
  printf '\n'
done
```

- この表は「試験が参照している名前」の一覧であり、仕様の全エラー条件を網羅した証明ではない。§2 の「記載」欄を原文の復号結果と照合し、条件単位の表へ育てるのは次の段階とする。
