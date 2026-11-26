# BTRON3 適合確認の台帳（生成物）

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) Phase 5。`python3 tools/spec_matrix.py ledger -` で [btron3-ledger.tsv](btron3-ledger.tsv) から生成する。
> 合否基準は [btron3-test-plan.md](btron3-test-plan.md) §3、独立性（基準 6）の判定規則は同 §3.1。基準 1〜8 がすべて ○ の関数だけを「適合確認済」とし、[btron3-matrix.md](btron3-matrix.md) の注記に出す。

記号: ○ 満たす、× 満たさない、— 対象が無い（規定が無い）。

| 関数 | 節 | 1 要求 | 2 正常 | 3 異常 | 4 境界 | 5 相互作用 | 6 独立性 | 7 再現性 | 8 記録 | 状態 | 確認した版 | 試験 | 根拠 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `cre_nam` | 1.4 | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | 適合確認済 | 8bc8f43（`make test` rc=0） | 名試: 作成・取得・重複作成は ER_EXS・重複作成で値は不変・変更・無い名の変更は ER_NOEXS・強制で新規・強制で上書き・負の値・空の名前は ER_PAR・不正な指定は ER_PAR・名前の番地が不正は ER_ADR・9文字目は無視・16件まで作れる・17件目は ER_NOSPC・削って空けると作れる・DELEXIT の名は持ち主の終了で消える・DELEXIT 無しの名は残る・他の行程の DELEXIT で持ち主が移る | 原文 1.4.3 cre_nam の opt（N_CREATE・N_MODIFY・N_FORCE・DELEXIT）・エラー表・「先頭 8 文字（16 バイト）が有効」・データは W。DELEXIT の文の後半は原文の文字化けで、残った語から「他の行程の指定があってもこの指定で持ち主が移る」と読む（btron3-os.md 1.4）。表の 16 件は ER_NOSPC（領域の不足）を起こす実装依存の大きさ |
| `del_nam` | 1.4 | ○ | ○ | ○ | ○ | — | ○ | ○ | ○ | 適合確認済 | 8bc8f43（`make test` rc=0） | 名試: 削除・無い名の削除は ER_NOEXS・空の名前は ER_PAR・名前の番地が不正は ER_ADR・削って空けると作れる | 原文 1.4.3 del_nam のエラー表（ER_ADR・ER_NOEXS・ER_PAR） |
| `get_nam` | 1.4 | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | 適合確認済 | 8bc8f43（`make test` rc=0） | 名試: 取得・空の名前は ER_PAR・名前の番地が不正は ER_ADR・書き先の番地が不正は ER_ADR・削除後は ER_NOEXS・9文字目は無視・DELEXIT の名は持ち主の終了で消える | 原文 1.4.3 get_nam のエラー表（ER_ADR は name と data の両方）。他の行程が作った名を読めること（全行程から参照可）は DELEXIT の 2 項目で確認 |

**適合確認済: 3 関数**（台帳にある 3 関数のうち）。

