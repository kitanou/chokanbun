# BTRON3 適合確認の台帳（生成物）

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) Phase 5。`python3 tools/spec_matrix.py ledger -` で [btron3-ledger.tsv](btron3-ledger.tsv) から生成する。
> 合否基準は [btron3-test-plan.md](btron3-test-plan.md) §3、独立性（基準 6）の判定規則は同 §3.1。基準 1〜8 がすべて ○ の関数だけを「適合確認済」とし、[btron3-matrix.md](btron3-matrix.md) の注記に出す。

記号: ○ 満たす、× 満たさない、— 対象が無い（規定が無い）。

| 関数 | 節 | 1 要求 | 2 正常 | 3 異常 | 4 境界 | 5 相互作用 | 6 独立性 | 7 再現性 | 8 記録 | 状態 | 確認した版 | 試験 | 根拠 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `cre_nam` | 1.4 | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | 適合確認済 | 0fb273f（`make test` rc=0） | 名試: 作成・取得・重複作成は ER_EXS・重複作成で値は不変・変更・無い名の変更は ER_NOEXS・強制で新規・強制で上書き・負の値・空の名前は ER_PAR・不正な指定は ER_PAR・名前の番地が不正は ER_ADR・9文字目は無視・16件まで作れる・17件目は ER_NOSPC・削って空けると作れる・DELEXIT 付きで作れる・子の作成と変更は全て成功・DELEXIT の名は持ち主の終了で消える・DELEXIT 無しの名は残る・他の行程の DELEXIT で持ち主が移る・DELEXIT 無しの変更で存続する名になる | 原文 1.4.1（全行程から参照・変更でき、自動削除の有無は生成／変更のたびに指定する）と 1.4.3 cre_nam（opt の N_CREATE・N_MODIFY・N_FORCE・DELEXIT、DELEXIT は最後にこの呼出しをした行程が対象、エラー表、先頭 8 文字（16 バイト）が有効、データは W）。表の 16 件は ER_NOSPC（領域の不足）を起こす実装依存の大きさで、判定には使わない |
| `del_nam` | 1.4 | ○ | ○ | ○ | ○ | — | ○ | ○ | ○ | 適合確認済 | 0fb273f（`make test` rc=0） | 名試: 削除・無い名の削除は ER_NOEXS・空の名前は ER_PAR・名前の番地が不正は ER_ADR・9文字目は無視（9 文字目だけ違う名で削れる）・削って空けると作れる | 原文 1.4.3 del_nam のエラー表（ER_ADR・ER_NOEXS・ER_PAR）と先頭 8 文字が有効 |
| `get_nam` | 1.4 | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | 適合確認済 | 0fb273f（`make test` rc=0） | 名試: 取得・削除（削除後の取得は ER_NOEXS）・空の名前は ER_PAR・名前の番地が不正は ER_ADR・書き先の番地が不正は ER_ADR・9文字目は無視・DELEXIT 無しの名は残る（子が作った名を親が読む） | 原文 1.4.3 get_nam のエラー表（ER_ADR は name と data の両方）と先頭 8 文字が有効、1.4.1 の全行程から参照できること |

**適合確認済: 3 関数**（台帳にある 3 関数のうち）。

