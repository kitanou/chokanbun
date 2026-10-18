# BTRON3 適合試験計画

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) / 全体表: [btron3-conformance.md](btron3-conformance.md)
> 対象: BTRON3仕様書 Ver. 3.20.00 第1編・第2編。作成: 2026-10-17（Phase 5 の最初の版）。
> 目的: 規範項目ごとの**合否基準**を先に決め、既存の QEMU 試験を規範項目へ紐付け、不足を洗い出す。

## 1. 位置づけ

- 適合性マトリクスの状態「適合確認済」へ進めるための条件は、本書の §3 で定める。**現時点で §3 を満たす項目は 0**（マトリクスの集計と一致）。
- 既存の試験は、実装者が原文を**読み取った解釈**を検証している。解釈そのものの正しさ（原文の文字化け・欠落箇所）は試験では保証されない。このため、試験が通ることは「実装済・未検証」から進めても「適合確認済」とする根拠にはならない。
- 仕様書本文は転載しない。試験の題と期待値は独自の記述とする。

## 2. 試験の種類と実行方法

| 種別 | 内容 | 実行 | 記録 |
|---|---|---|---|
| コンパイラ／言語 | 構文・型・IR・ELF 生成の黄金試験と診断試験（`tests/lang/ok`・`err`） | `make test` | 標準出力（PASS/FAIL） |
| 互換層の QEMU 試験 | EL0 の外部命令（`user/btron_*.mkn`、`user/pian_test.mkn`）を漢殻から起動し、UART に出る `<命令> <題> 0x…` の行で合否を見る | `make test`（QEMU を自動起動） | `tests/output/kernel_qemu.log` |
| 対話確認 | 同じ核を手で起動し、命令を打つ | `make run` | 端末 |

- 一項目は 1 行で、末尾が `0x0000000000000001` なら合格。終了コードは失敗数。
- `tests/run_tests.sh` は各試験の**項目数を固定**で検査する（例: 録試 20、緩試 24）。項目を足したら数も更新する。数が合わないと失敗にする方針で、項目の脱落を検出する。
- 試験は決定的であること。時刻に依存する項目（時試の現在日付など）は、ホストの UTC 日付との差を許す形で検査する。

## 3. 「適合確認済」への合否基準

規範項目（API・データ形式・状態遷移の単位）が「適合確認済」になる条件を、すべて満たすこととする。

1. **要求の抽出**: 原文の該当節を**文字化けなく**確認し、要求を `btron3-os.md` / `btron3-shared-data.md` に要約済み。「要確認」が残っていない（残る場合は、実装依存と明記して選択と理由を記録済み）。
2. **正常系**: 規定された主な動作を 1 件以上検証している。
3. **異常系**: 原文のエラー（`ER_*`）の発生条件ごとに 1 件以上検証している。
4. **境界条件**: 範囲・サイズ・上限（例: 名前長、件数、符号、`T_NOWAIT`/`T_FOREVER`）を検証している。
5. **相互作用**: 資源の解放（`DELEXIT`、終了時の自動返却）、権限（利用者レベル）、待ちの起床順など、他の API との関係が規定されていれば検証している。
6. **独立性**: 期待値の少なくとも一部が**実装と独立**に得られている（原文の例・公開テストベクトル・別実装の出力・ホスト側の計算）。実装者の解釈だけを根拠にした項目は「実装済・未検証」に留める。
7. **再現性**: QEMU で再現でき、実行コマンドとログが保存されている（`tests/output/` のログに加え、実行した版を記録する）。
8. **記録**: マトリクスの該当行に、試験の題・場所・ログの参照を書く。

「完全準拠」はマトリクス全項目が上記を満たし、未解決の非適合が残らない状態（#42 の定義）。

## 4. 既存試験と規範項目の対応

凡例: 正＝正常系、異＝異常系（`ER_*`）、境＝境界、相＝相互作用（資源の解放・権限・待ち合わせ）。項目数は `tests/run_tests.sh` の固定値。

| 試験 | ファイル | 項目 | 規範項目 | 対象 API・データ | 区分 | 備考 |
|---|---|---|---|---|---|---|
| 識試 | `user/btron_gtid.mkn` | 13 | OS 1.1、共有データ §1、ER 規約 | `get_tid`、`ER_*` の符号と `錯換`、`H`（符号・範囲・隣欄保持）、`Bool`、`SIZE`/`PNT`/`RECT` の配置と共用体 | 正・境 | `ER_*` の数値は実装依存（G0）。型配置は欄名が仮 |
| 名試 | `user/btron_gname.mkn` | 21 | OS 1.4 グローバル名 | `cre_nam`（`N_CREATE`/`N_MODIFY`/`N_FORCE`）、`del_nam`、`get_nam` | 正・異・境・相 | 8 文字、16 件、`ER_EXS`/`ER_NOEXS`/`ER_PAR`/`ER_ADR`/`ER_NOSPC`、`DELEXIT` |
| 時試 | `user/btron_clk.mkn` | 11 | OS 1.9 時計管理 | `get_tim`、`get_tod`（暦・閏年・通日） | 正・異・境 | 暦の期待値は手計算とホスト日付との比較。ずれの符号は要確認 |
| 信試 | `user/btron_msg.mkn` | 45 | OS 1.2 メッセージ、1.1 の終了通知 | `snd_msg`、`rcv_msg`、`clr_msg`、`cre_prc`（BTRON3 流）、`ext_prc`、`MS_EXIT` | 正・異・境・相 | 型 1〜31、本体 1〜32 B、キュー 8、`ER_SZOVR`/`ER_NOSPC`/`ER_NOPRC`、枠の即解放 |
| 利試 | `user/btron_usr.mkn` | 19 | OS 1.1 利用者情報、1.9 設定系 | `get_usr`、`chg_usr`、`set_tim`、`set_tod` | 正・異・相 | 権限（level 0 のみ設定可）、子が親の写しを継ぐ。level の向きは解釈 |
| 強試 | `user/btron_term.mkn` | 23 | OS 1.1 強制終了・状態 | `ter_prc`（`TERM_NRM`/`TERM_ALL`）、`prc_sts`、`MS_TERM` | 正・異・相 | `ER_SELF`/`ER_NOPRC`/`ER_LEVEL`/`ER_PAR`、子孫の終了順、枠の回収 |
| 同試 | `user/btron_sync.mkn` | 21 | OS 1.3 セマフォ・イベントフラグ | `cre_sem`、`del_sem`、`sig_sem`、`wai_sem`、`cre_flg`、`del_flg`、`set_flg`、`clr_flg`、`wai_flg` | 正・異・境・相 | FIFO、時間切れ、`ER_DLT`、`DELEXIT`、排他の自動返却。待ち順は解釈 |
| 緩試 | `user/btron_comm.mkn` | 27 | OS 1.3 メッセージバッファ・ランデブ | `cre_mbf`、`del_mbf`、`snd_mbf`、`rcv_mbf`、`cre_por`、`del_por`、`cal_por`、`acp_por`、`fwd_por`、`rpl_rdv` | 正・異・境・相 | 環の折り返し、満杯・空、転送、削除。`bufsz`=0 は未対応 |
| 録試 | `user/btron_file.mkn` | 114 | OS 1.6 ファイル管理 B1〜B5、1.1 の `cre_prc` | `get_lnk`、`chg_wrk`、`att_fls`、`det_fls`、`lst_fls`、`fls_sts`、`cre_fil`、`cre_lnk`、`gen_fil`、`fnd_lnk`、`lnk_sts`、`syn_lnk`、`get_nlk`、`del_fil`、`opn_fil`、`cls_fil`、`fil_sts`、`ofl_sts`、`see_rec`、`fnd_rec`、`rea_rec`、`wri_rec`、`ins_rec`、`apd_rec`、`del_rec`、`trc_rec`、`loc_rec`、`xch_fil`、`chk_fil`、`chg_fmd`、`chg_fat`、`chg_fpw`、`chg_fnm`、`chg_ftm`、`get_dfm`、`set_dfm`、`cre_prc` | 正・異・境・相 | B1: 出現番号、`F_BASED`/`F_DIRECT`、作業ファイル継承。B2: 記述子の世代、ファイル数の上限と頁の返却、親レコードの満杯（`ER_SZOVR`）、参照数の増減、`F_EXCL`/`F_WEXCL` の行程間試験（子行程を使う）、行程終了での自動クローズ、読取専用 FS。B3: レコードの追記・挿入・書き足し（後ろが壊れない）・切り詰め・削除、リンクレコード、本文の容量、記述子間と行程間のロック、挿入・削除でのロック番号のずれ、`xch_fil`。B4: 属性の設定・解除、パスワード（20 文字・21 文字の境界を含む）、名前・時刻の変更、既定のアクセスモード、`A_MODE`、別の利用者・グループ・レベルになる子行程でのアクセス判定 |
| 篇試 | `user/pian_test.mkn` | 28 | 篇藏（内部設計。BTRON3 の規範ではない） | 篇ID、章、パス、名替、予約章、深さ・名前長の上限 | 正・異・境 | 内部ストレージの試験。BTRON3 適合の根拠にはしない |
| 貯試 | `user/btron_mem.mkn` | 45 | OS 1.5 メモリ管理 | `get_mbk`、`rel_mbk`、`mbk_sts`、`malloc` 系 18 関数 | 正・異・境・相 | ローカル塊の割当・解放・再利用（昇順 first-fit、解放後の穴）、ローカル域の枯渇（`ER_NOMEM`）、共有・システム塊の全行程写像（同一 VA・同一物理頁を子行程で横断確認）、`DELEXIT` の自動解放、`M_SYSTEM` のレベル 0 権限（子がレベル 1 で `ER_CTX`）、持ち主でない塊の解放（`ER_MPTR`）、`ER_PAR`（余計ビット・頁数 0・負）、`ER_ADR`（书写き先が不正）、`mbk_sts` の口径（空き枚数の減りと戻り）。子は 3 役。不足: 塊表 32 項の満杯・共有域 8 頁づまり（`ER_LIMIT`）の試験なし |
| 件試 | `user/btron_evt.mkn` | 73 | OS 1.7 イベント管理 | `get_evt`、`put_evt`、`clr_evt`、`get_pdp`、`set_pdp`、`get_etm`、`get_kmp`、`chg_emk`、`set_krp`、`get_krp`、`set_krm`、`get_krm`、`get_kid`、`get_ktb`、`set_ktb`、`chg_pda`、`sig_buz`、`ctl_buz`、`req_evt`、`las_evt` | 正・異・境・相 | 隊 32 項と優先度・発生順、マスク外の破棄、`CLR`/`NOCLR`、`EP_POS`/`EP_STAT`/`EP_TIME`、満杯（`ER_NOSPC`）、`ER_PAR`（t_mask≦0・opt 不正・型 0/5/16・余計ビット・メロディー番号）・`ER_ADR`（窓外）、`chg_emk`（負で取得）、`get_etm` と時間の進み、`get_kmp` のキー反映、`set`/`get_krm`・`krp` の往復、`get_kid`、`get_ktb`/`set_ktb`（keymax 0・kctmax 4001・往復）、絶対座標タイプの `set_pdp`、`ctl_buz` の往復、`req_evt` の `MS_SYS5` を `rcv_msg` で受信・解除、`las_evt` の経過、`EV_AUTKEY` の合成。実機が無いため核内の模型で試験する（子行程は使わない） |
| 設試 | `user/btron_dev.mkn` | 90 | OS 1.8 デバイス管理 | `opn_dev`、`cls_dev`、`rea_dev`、`wri_dev`、`chg_dmd`、`dev_sts`、`get_dev`、`lst_dev`、`sus_dev` | 正・異・境・相 | 論理名の解決（前綴り一致・支番 1〜3 桁・前 0 なし）と未登録（`ER_NOEXS`）、`o_mode` の不正ビット（`ER_PAR`）と排他（`D_EXCL`/`D_WEXCL` の `ER_BUSY`）、同時オープン 32 の上限（`ER_LIMIT`）、塊型の読み書き（`rda`）と属性データ（`start`<0、読のみ）、`a_size`、文字型（`con`）の路と空読み（`ER_BUSY`）、向きの検査（読否 `prn` の `D_READ` → `ER_DEV`、書禁 `rom` の `D_WRITE` → `ER_RONLY`）、`D_READ`/`D_WRITE` オープンでの逆操作（`ER_DD`）、`dev_sts`（`attr`/`mode`/`blksz`/`wprt`）、`get_dev`/`lst_dev`（`DEV_INFO`）、`chg_dmd` のレベル 0 権限（`ER_ACCES`）と `mode` の範囲、`sus_dev` の通常・強制カウンタ（`D_CHECK`/`D_SUSPEND`/`ER_BUSY`）。実機が無いため核内の模型 4 ユニット（`rda`/`rom`/`con`/`prn`）で試験する（子行程は使わない） |
| 系試 | `user/btron_sys.mkn` | 38 | OS 1.10 システム管理 | `get_ver`、`get_cnf` | 正・異・境 | `T_VER`（20 B）の全欄（`maker`/`id`/`spver`/`prver`/`prno[4]`/`cpu`/`var`）と 20 バイトだけ書くこと、格納域が窓外・窓末で入らない場合（`ER_ADR`）、構成情報の数値 3 項目（`NPRC`/`PGSZ`/`NDEV`）と文字列 2 項目（`SYSNAM`/`SYSVER`）の内容と末尾の NUL、未知の名前（`ER_NOEXS`）・部分名・余分付き・大小文字、名または格納域が窓外（`ER_ADR`）、数値で `len`<4 と `len`<0（`ER_PAR`）、文字列の `len`=0・不足（4）・ちょうど（11）・余りあり（12）の切り詰め。`def_exc`/`ret_exc` は未実装のため試験しない（子行程は使わない） |
| 言語 | `tests/lang/ok`・`err` | ok 7・err 37 | （BTRON3 とは無関係） | 言語仕様の黄金・診断試験 | — | 互換層を書く言語の健全性 |
| 起動時 | `tests/run_tests.sh` | — | 核の基本動作 | argv 受け渡し、終了コード、EL0 行程、メモリ保護など | — | BTRON3 の項目には紐付けない |

**集計**: BTRON3 互換層の QEMU 試験は 13 種・計 540 項目（識試 13、名試 21、時試 11、信試 45、利試 19、強試 23、同試 21、緩試 27、録試 114、貯試 45、件試 73、設試 90、系試 38）。ほかに篇藏 28 項目。

## 5. API 単位の試験の有無（第2編 第1章）

実装済みの API について、試験があるか、足りない区分は何かを記す。**試験が無い API は「実装済・未検証」の根拠が弱い**。

| API | 試験 | 足りない区分・不足 |
|---|---|---|
| `get_tid` | 識試 | 副タスク・エラー規定（要確認） |
| `cre_prc`（LINK 版） | 録試 | 子の生成・作業ファイルの継承・`MS_EXIT`・引数（argc）・各エラーは確認済み。優先度の反映、型 0 以外のメッセージ、`ER_BUSY`/`ER_ACCES` は未検証 |
| `cre_prc`（旧形 `BTRON生行程`） | 信試 | 試験と殻の補助。BTRON3 の規範には使わない |
| `ext_prc` | 信試（`MS_EXIT`） | 資源解放の網羅（共有メモリ等は未実装） |
| `ter_prc`、`prc_sts` | 強試 | `ER_LEVEL` の向きは解釈。優先度の返り値は固定値 |
| `get_usr`、`chg_usr` | 利試 | 利用者名の接尾部、グループ名の検証は未実装 |
| `snd_msg`、`rcv_msg`、`clr_msg` | 信試 | `CONFM`（取り出しまで待つ・相手が終わると `ER_NOPRC`・自分宛は `ER_SELF`）を子行程で確認。`CHECK`・`WAIEVT`・`req_tmg`・`can_tmg` は信試で確認のみ |
| `cre_nam`、`del_nam`、`get_nam` | 名試 | 良好。`get_nam` の戻り動作は原文の欠落箇所（要確認） |
| `cre_sem` `del_sem` `sig_sem` `wai_sem` | 同試 | カウント上限 65535、16 個上限（`ER_LIMIT`）の境界試験なし |
| `cre_flg` `del_flg` `set_flg` `clr_flg` `wai_flg` | 同試 | OR 待ち（`TWF_ORW`）、複数待ち、16 個上限の試験なし |
| `cre_mbf` `del_mbf` `snd_mbf` `rcv_mbf` | 緩試 | `rcv_mbf` の戻り値は原文欠落（要確認） |
| `cre_por` `del_por` `cal_por` `acp_por` `fwd_por` `rpl_rdv` | 緩試 | 受付側が返答せず終了する場合は仕様未確認で試験なし |
| `get_tim`、`get_tod` | 時試 | `local` の解釈（要確認）、時刻帯 ≠ 0 の取得は利試 |
| `set_tim`、`set_tod` | 利試 | 年の範囲 1985〜2100 の境界、夏時間補正 |
| `get_lnk`、`chg_wrk` | 録試 | 良好（B1 の範囲） |
| `cre_fil` | 録試 | `ER_IO`・`ER_NODSK` は発生し得ず未検証。親への W が無い `ER_ACCES` は子行程で確認。`F_FILEID`・`A_MODE` は未対応（`ER_PAR` を確認） |
| `cre_lnk` | 録試 | 良好（浮動・固定、各エラー、満杯）。リンクの更新時刻は未検証 |
| `del_fil` | 録試 | `ER_LOCK` は未検証。`ER_ACCES` は子行程で確認。戻り値の意味は原文欠落（要確認）で、自前の解釈の検証のみ |
| `opn_fil` | 録試 | `ER_ACCES`・`ER_PWD` は確認済み（グループと所有者の経路）。同じ行程の二重オープンの規則は暫定で試験していない |
| `cls_fil` | 録試 | `ER_IO` は発生し得ず未検証 |
| `chk_fil`、`chg_fmd`、`chg_fat`、`chg_fpw`、`chg_fnm`、`chg_ftm`、`get_dfm`、`set_dfm` | 録試 | アクセス管理レベル 0（`SYS`）での素通し、`chk_fil` の E ビットと `F_EXCUTE`、公開経路の単独試験、`chg_fnm` の `ER_RONLY` は未検証。細部は原文の欠落で自前の解釈 |
| `fil_sts`、`ofl_sts` | 録試 | `F_STATE` の全フィールド（時刻・f_group など）の値は未検証。`F_LOCATE` は NULL のみ |
| `see_rec`、`fnd_rec` | 録試 | `F_BWD` 系は未対応（`ER_PAR`）。`ER_IO` は発生し得ず未検証 |
| `rea_rec`、`wri_rec` | 録試 | `wri_rec` の `units` は無視。リンクレコードの属性以外の書き込みは `ER_PAR` を確認。戻り値の意味は原文欠落で自前の解釈 |
| `ins_rec`、`apd_rec` | 録試 | リンクの `ER_LIMIT`（参照数 255）は未検証。`ER_REC`（原文が不明）は未対応 |
| `del_rec`、`trc_rec` | 録試 | 良好 |
| `loc_rec` | 録試 | `F_LOCK` の待ち・`ER_MINTR`・複数ロックは未検証（未実装） |
| `xch_fil` | 録試 | `ER_XFS`（別 FS）と他の記述子のロック（`ER_LOCK`）は未検証 |
| `att_fls`、`det_fls`、`lst_fls`、`fls_sts`、`syn_fls`、`chg_fls`、`chg_fsm` | 録試 | `chg_fls` の書込権 W による ER_ACCES と、装置が開かれている場合の ER_BUSY は未試験・未実装 |
| `get_mbk`、`rel_mbk`、`mbk_sts` | 貯試 | ローカル塊: 先頭が頁 8 から連続し、書いて読め、解放した穴が再利用され、16 頁の塊 14 件でローカル域が尽きる（`ER_NOMEM`。残りの穴には小さな塊が当たる）。`ER_ADR`（書き先の番地が不正）、`ER_PAR`（指定 0x2・余計ビット・頁数 0 と負）、`ER_MPTR`（零・非整列・塊途中・塊で無い整列番地の放）。`mbk_sts` は blksz=4096・total=4096・空き枚数（塊で減り、解放で戻る） |
| `malloc`/`calloc`/`realloc`/`free`、`S*`、`K*`、`V*` | 貯試 | 共有塊は降順 first-fit（0x406FF000 = 頁 255 から）で、子から同一物理頁が見え（子の判定が戻る）、子の読みが親の値を壊さない。システム塊は 0x406FE000 に当たり書け読め、解除を含む。子がレベル 1 で `ER_CTX`・持ち主以外の解放は `ER_MPTR`。`DELEXIT` の共有塊は子の終了で自動解放される。`malloc` 族 18 関数（Smalloc は共有域、Kmalloc は常駐システム、Vmalloc は非常駐システム、calloc の零詰めと realloc の写しを含む。`free` の零は成功）。不足: `ER_LIMIT`（塊表満杯・共有域 8 頁づまり）の試験なし |
| `get_evt`、`put_evt`、`clr_evt`、`get_etm`、`chg_emk`、`req_evt`、`las_evt` | 件試 | 隊 32 項の満杯（`ER_NOSPC`）、型 0・5・16 以上の `ER_PAR`、`opt` の余計ビット、マスク外の破棄、`EV_NULL` の合成（時 = 現在・座 = PD 位置・状 = メタキー状態）、優先度クラス（APPL1〜4 が BUTDWN より先、AUTKEY は次、APPL5〜8 は最後）とクラス内の発生順、`clr_evt` の `last_mask`（`EM_ALL` は選んだ 1 項だけ）、`req_evt` の `MS_SYS5` を `rcv_msg` で受信（型 10・本体 20 B・送り手 = 要求元）と解除後の非配送、`las_evt` の増加と `EM_NULL` での現在時刻化、`get_etm` の 25 ms 刻み |
| `get_kmp`、`set_krp`、`get_krp`、`set_krm`、`get_krm`、`get_kid`、`get_ktb`、`set_ktb` | 件試 | `put_evt` の KEYDWN/KEYUP がキー状態に反映されること（`get_kmp`）、`offset`/`interval` の往復と 0 の `ER_PAR`、KeyMap の往復、`KBD_ID` の kind=1、KeyTab の往復と keymax=0・kctmax=4001 の `ER_PAR`、`EV_AUTKEY` の合成（対象キー・優先度・時間）と対象外・キーアップでの非合成。不足: 実機の入力（virtio-input）を繋いだときのドライバ境界 |
| `get_pdp`、`set_pdp`、`chg_pda`、`sig_buz`、`ctl_buz` | 件試 | PD 位置の往復と `PNT` の欄の並び、イベント無しで `EV_NULL`、属性の変更（`PD_ABS` で `set_pdp` が 1）と不正ビットの `ER_PAR`、`sig_buz` の種別検査（0・-1・時間指定・メロディー番号）、`ctl_buz` の 6 種の往復。不足: 実機の PD・ブザー |
| `opn_dev`、`cls_dev`、`rea_dev`、`wri_dev`、`chg_dmd`、`dev_sts`、`get_dev`、`lst_dev` | 設試 | 論理名（`rda`/`rom`/`con`/`prn` の前綴り一致、支番 1〜3 桁、前 0 なし、`ER_NOEXS`）、`o_mode` の許容ビットと `ER_PAR`、排他（ユニット単位の `ER_BUSY`、閉じれば再開ける）、32 相の上限（`ER_LIMIT`）、塊型の読み書きと属性データ（`start`<0）、`a_size` に容量・空き、文字型の 32 B 路と `ER_BUSY`、向き（読否 → `ER_DEV`、書禁 → `ER_RONLY`）と逆操作（`ER_DD`）、`dev_sts` の 4 欄、`get_dev` の支数、`lst_dev` の `DEV_INFO` 並び、`chg_dmd` の `ER_ACCES`・レベル 0 権限。不足: 実機の器類表（ディスク・コンソール・印刷） |
| `sus_dev` | 設試 | 通常・強制の禁止カウンタ（`D_DISSUS`/`D_ENASUS`/`D_CHECK`）、通常の `D_SUSPEND` は両方 0 を要求、`D_FORCE|D_SUSPEND` は強制 0 を要求（`ER_BUSY`）、電源管理が無いので直ちに 0。不足: 実機の電源管理 |
| `get_ver`、`get_cnf` | 系試 | `T_VER`（20 B）の全欄（`maker`/`id`/`spver`/`prver`/`prno[4]`/`cpu`/`var`）と 20 バイトだけ書くこと、格納域が窓外・窓末で入らない場合（`ER_ADR`）、数値 3 項目（`NPRC`/`PGSZ`/`NDEV`）と文字列 2 項目（`SYSNAM`/`SYSVER`）の内容・末尾 NUL、未知の名前・部分名・余分付き・大小文字（`ER_NOEXS`）、`len` の境界（数値で `len`<4・`len`<0 は `ER_PAR`、文字列の切り詰め）。不足: `def_exc`/`ret_exc`（未実装のため試験なし） |

## 6. 未整備の試験（優先順）

| 優先 | 試験 | 規範項目 | 前提・内容 |
|---|---|---|---|
| 1 | `ER_*` の網羅表 | 全体 | 原文のエラー名を API ごとに列挙し、各試験の異常系との対応を表にする（欠けた `ER_*` を可視化） |
| 2 | 同期系の上限・OR 待ち | 1.3 | `ER_LIMIT`、カウント上限、`TWF_ORW` を同試に追加 |
| 3 | 型の残り | 共有データ §1 | `ErrCode` の二定義、`MSEC`/`STIME` の幅、浮動小数点の方針が決まってから |
| 4 | 録層 B6 以降 | 1.6 | 写像・永続化・大きなファイルの本文。実装と同時に正常・異常・境界を足す。B4 の未検証項目（アクセス管理レベル 0 の FS、`chk_fil` の全ビット、複数ユーザーの公開経路）、`xch_fil` の `ER_LOCK` も併せて足す |
| 5 | メッセージのハンドラ・タイムアウト | 1.2 | `def_msg`/`ret_msg`/`brk_msg`、`req_tmg`。EL0 への非同期上りの実装後 |
| 6 | 文字コード・TAD の往復試験 | 共有データ §2・§3 | 符号表と TAD の ID／配置を原文で確定してから。テストベクトルの入手経路を決める |
| 7 | 描画・HMI の統合試験 | 第2編 第2章・第3章 | 表示装置の実装後。QEMU の framebuffer 出力の比較方法（スクリーンショットの画素比較）を決める |
| 8 | 独立な期待値の導入 | 全体 | §3 の 6 を満たす手段（原文の例、別実装、ホスト計算）を項目ごとに調べる |

## 7. 実行記録の残し方

- `make test` のたびに `tests/output/kernel_qemu.log` が上書きされる。適合の根拠として残す場合は、マトリクスの更新時にコミット ID と合否の集計を書く。
- 失敗した項目は題と期待値・実測値をログに出す形式を保つ（`判定` 術が `<命令> <題> 0x…` を出す）。
- 試験の追加・変更時は、本書の §4 の表（項目数）、`tests/run_tests.sh` の固定値、マトリクスの状態を同じコミットで更新する。

## 8. 本書自体の未解決事項

- 原文の文字化け箇所の確定前は、§3 の 1 を満たせない。確定方法（原文ページの直接確認）を先に決める。
- §3 の 6 の「独立な期待値」を、どの項目でどう得るか（特に TAD・文字コード）。
- B-right/V の差分は別表（`btron3-bright-v.md`、未作成）で扱い、本計画の対象外。
