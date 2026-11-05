#!/usr/bin/env python3
"""BTRON3 仕様書 (OS 仕様編) の関数を抽出し、実装・試験と照合する (#42 Phase 0)。

使い方:
  python3 tools/spec_matrix.py fetch <作業ディレクトリ>     原文を取得して UTF-8 の .txt にする
  python3 tools/spec_matrix.py matrix <作業ディレクトリ>    docs/compat/btron3-matrix.md を標準出力へ
  python3 tools/spec_matrix.py consts <作業ディレクトリ>    docs/compat/btron3-constants.md を標準出力へ
  python3 tools/spec_matrix.py shared <作業ディレクトリ>    docs/compat/btron3-shared-data-sections.md を標準出力へ

原文は ISO-2022-JP の HTML。取得は curl、変換は iconv を使う。原文の本文は保存・転載しない
(関数名・原型・エラーコード名・構造体名のような API の識別子だけを使う)。
"""
import glob
import os
import re
import subprocess
import sys

BASE = "https://www.chokanji.com/developer/doc/btron3"
PAGES = {
    "shared_data": ["data_type", "tron_code", "tad1", "tad2", "tad3", "fd_format"],
    "os_spec/kernel": ["kernel", "proc", "message", "taskcomm", "gname", "memory", "file", "device", "event", "clk", "system"],
    "os_spec/dp": ["dp", "intro", "basic_concept", "basic_func", "figure_func", "character_func", "pointer_func"],
    "os_spec/shell": ["shell", "window", "menu", "parts", "panel", "tray", "data", "tip", "omgr", "font_mgr", "tcpip", "printmgr"],
}
# 節の表題 (原文の目次どおりの番号)
SECTIONS = {
    "kernel/proc": "1.1 プロセス／タスク管理", "kernel/message": "1.2 メッセージ管理",
    "kernel/taskcomm": "1.3 タスク間通信", "kernel/gname": "1.4 グローバル名",
    "kernel/memory": "1.5 メモリ管理", "kernel/file": "1.6 ファイル管理",
    "kernel/device": "1.7 デバイス管理", "kernel/event": "1.8 イベント管理",
    "kernel/clk": "1.9 時計管理", "kernel/system": "1.10 システム管理",
    "dp/basic_func": "2.3 基本関数", "dp/figure_func": "2.4 図形描画関数",
    "dp/character_func": "2.5 文字(列)描画関数", "dp/pointer_func": "2.6 ポインタ制御関数",
    "shell/window": "3.1 ウィンドウマネージャ", "shell/menu": "3.2 メニューマネージャ",
    "shell/parts": "3.3 パーツマネージャ", "shell/panel": "3.4 パネルマネージャ",
    "shell/tray": "3.5 トレーマネージャ", "shell/data": "3.6 データマネージャ",
    "shell/tip": "3.7 テキスト入力プリミティブ", "shell/omgr": "3.8 実身／仮身マネージャ",
    "shell/font_mgr": "3.9 フォントマネージャ", "shell/tcpip": "3.10 TCP/IP マネージャ",
    "shell/printmgr": "3.11 印刷マネージャ",
}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def fetch(work):
    for d, names in PAGES.items():
        os.makedirs(os.path.join(work, d), exist_ok=True)
        for n in names:
            html = os.path.join(work, d, n + ".html")
            subprocess.run(["curl", "-sL", f"{BASE}/{d}/{n}.html", "-o", html], check=True)
            raw = subprocess.run(["iconv", "-c", "-f", "ISO-2022-JP", "-t", "UTF-8", html], capture_output=True, check=True).stdout.decode("utf-8", "replace")
            open(os.path.join(work, d, n + ".txt"), "w").write(re.sub(r"<[^>]*>", "", raw))


def parse_page(path):
    """【形式】ごとに (関数名, 原型, エラーコード列) を返す。"""
    t = open(path).read()
    t = t.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&").replace("&nbsp;", " ")
    parts = re.split(r"【形式】", t)
    out = []
    for i, p in enumerate(parts[1:]):
        proto = re.split(r"【", p, 1)[0]
        proto = " ".join(proto.split())
        m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(", proto)
        if not m:
            continue
        name = m.group(1)
        err = ""
        if "【エラーコード】" in p:
            err = p.split("【エラーコード】", 1)[1]
            err = re.split(r"【|\n[a-z][a-z0-9_]*\n", err, 1)[0]
        codes = []
        for c in re.findall(r"\b(E[A-Z]?_[A-Z0-9_]+|ER_[A-Z0-9_]+)\b", err):
            if c not in codes:
                codes.append(c)
        out.append((name, proto, codes))
    # 見出しだけにある関数 (1 つの【形式】に複数の関数がまとめて書かれている場合など)
    have = {n for n, _, _ in out}
    for h in re.findall(r"\n([a-z][a-z0-9_]*)\n \n", t):
        if h not in have and "_" in h:
            have.add(h)
            out.append((h, "", []))
    return out


def implementations():
    """実装している BTRON 名 → (ファイル, 本体のテキスト, 互換層側の日本語名)。"""
    impl = {}
    for f in glob.glob(os.path.join(ROOT, "user/btron/*.mkn")):
        lines = open(f).read().split("\n")
        i = 0
        while i < len(lines):
            m = re.search(r"記號「([A-Za-z_][A-Za-z0-9_]*)」\s*術曰「([^」]+)」", lines[i])
            jp = None
            if m:
                name, jp = m.group(1), m.group(2)
            else:
                m = re.match(r"術曰「([A-Za-z_][A-Za-z0-9_]*)」", lines[i])
                name = m.group(1) if m else None
            if name:
                j = i
                while j < len(lines) and not lines[j].startswith("終術"):
                    j += 1
                impl.setdefault(name, (os.path.basename(f), "\n".join(lines[i:j]), jp))
                i = j
            i += 1
    return impl


def omgr_japanese(spec_names):
    """3.8 は日本語名の関数で実装している。定義の直前の註に BTRON 名が書いてあるものを拾う。"""
    got = {}
    path = os.path.join(ROOT, "user/btron/omgr.mkn")
    lines = open(path).read().split("\n")
    for i, ln in enumerate(lines):
        m = re.match(r"術曰「([^」]+)」", ln)
        if not m:
            continue
        jp = m.group(1)
        j = i - 1
        block = []
        while j >= 0 and lines[j].startswith("註") and len(block) < 12:
            block.append(lines[j])
            j -= 1
        text = "\n".join(block)
        for n in spec_names:
            if re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(n), text):
                got.setdefault(n, jp)
    return got


def tests():
    txt = ""
    for f in glob.glob(os.path.join(ROOT, "user/btron_*.mkn")) + glob.glob(os.path.join(ROOT, "user/*_test.mkn")):
        txt += open(f).read() + "\n"
    return txt


def tested(name, impl, tst):
    names = [name]
    if name in impl and impl[name][2]:
        names.append(impl[name][2])
    for n in names:
        if re.search(r"呼「%s」" % re.escape(n), tst) or re.search(r"行「%s」" % re.escape(n), tst):
            return True
    return False


def arg_check(name, proto, impl, key):
    """原型の引数の数と、実装の受ける引数の数が合うか。比べられないとき (3.8 の日本語名、原型なし) は「—」。"""
    if name not in impl or not proto or key == "shell/omgr":
        return "—"
    m = re.search(r"\((.*)\)", proto)
    args = m.group(1).strip() if m else ""
    n = 0 if args in ("", "void", "VOID") else args.count(",") + 1
    head = impl[name][1].split("\n")[0]
    return "○" if head.count("受「") == n else "×"


def matrix(work):
    impl = implementations()
    tst = tests()
    om = omgr_japanese([n for n, _, _ in parse_page(os.path.join(work, "os_spec/shell/omgr.txt"))])
    for n, jp in om.items():
        if n not in impl:
            impl[n] = ("omgr.mkn", "", jp)
    rows = []
    for key, title in SECTIONS.items():
        d = "os_spec/" + key
        path = os.path.join(work, d + ".txt")
        funcs = []
        seen = set()
        for name, proto, codes in parse_page(path):
            if name in seen:
                continue
            seen.add(name)
            funcs.append((name, proto, codes))
        rows.append((title, key, funcs))
    L = []
    L.append("# BTRON3 OS 仕様編 適合性マトリクス（関数単位。生成物）")
    L.append("")
    L.append("> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42)。`python3 tools/spec_matrix.py matrix <作業ディレクトリ>` で生成（原文の取得は `fetch`）。")
    L.append("> 原文は ISO-2022-JP の HTML を `iconv` で変換して読んだ。本文は転載せず、関数名・エラーコード名だけを記録する。")
    L.append("")
    L.append("## 読み方")
    L.append("")
    L.append("- 実装: `user/btron/*.mkn` に同名の関数（`記號「名」` か `術曰「名」`）があるか。")
    L.append("- 試験: `user/btron_*.mkn`（互換層の試験プログラム）がその名前を呼んでいるか。")
    L.append("- 本体に現れないエラー: 原文のエラーコードのうち、**その関数の本体に名前が直接現れないもの**。他の関数が返す場合や、そもそも未対応の場合がある（要確認）。第1章は核が返すので対象外。")
    L.append("- 3.8 は日本語名の関数で実装している。定義の直前の註に BTRON 名が書いてあるものを実装済みと数える（誤差があり得る）。対応は [design-object-model.md](design-object-model.md) と [btron3-conformance.md](btron3-conformance.md) の 3.8 の行を参照。")
    L.append("- 状態は機械的な判定で、「適合確認済み」は人が根拠を確認して付ける。ここでは 0 件。")
    L.append("")
    tot = {"all": 0, "impl": 0, "test": 0}
    nbad_args = []
    summary = []
    body = []
    for title, key, funcs in rows:
        n = len(funcs)
        ni = sum(1 for f in funcs if f[0] in impl)
        nt = sum(1 for f in funcs if f[0] in impl and tested(f[0], impl, tst))
        tot["all"] += n
        tot["impl"] += ni
        tot["test"] += nt
        summary.append((title, n, ni, nt))
        body.append(f"## {title}（{n} 関数）")
        body.append("")
        body.append("| 関数 | 原型 | 実装 | 引数 | 試験 | 原文のエラー | 本体に現れないエラー |")
        body.append("|---|---|---|---|---|---|---|")
        for name, proto, codes in funcs:
            if name in impl:
                fn, src, jp = impl[name]
                miss = [c for c in codes if c not in src]
                im = f"`{fn}`"
                te = "あり" if tested(name, impl, tst) else "なし"
            else:
                miss = []
                im = "未実装"
                te = "—"
            if name not in impl:
                cell = "—"
            elif key.startswith("kernel/"):
                cell = "—（核が返す）"
            elif key == "shell/omgr":
                cell = "—（日本語名の関数。要確認）"
            else:
                cell = " ".join("`" + c + "`" for c in miss)
            pr = proto.replace("|", "／").replace("`", "")
            errs = " ".join("`" + c + "`" for c in codes) if codes else "—"
            ar = arg_check(name, proto, impl, key)
            if ar == "×":
                nbad_args.append((key, name))
            body.append(f"| `{name}` | {'`' + pr + '`' if pr else '—'} | {im} | {ar} | {te} | {errs} | {cell} |")
        body.append("")
    L.append("- 引数: 原型の引数の数と、実装の受ける引数の数が合うか（○ 合う、× 合わない、— 比べられない）。型・意味までは見ない。")
    L.append("")
    L.append("## 集計")
    L.append("")
    L.append("| 節 | 関数 | 実装 | 実装＋試験 |")
    L.append("|---|---|---|---|")
    for title, n, ni, nt in summary:
        L.append(f"| {title} | {n} | {ni} | {nt} |")
    L.append(f"| **合計** | **{tot['all']}** | **{tot['impl']}** | **{tot['test']}** |")
    L.append("")
    L.extend(body)
    return "\n".join(L)


# 共有データ編の節 → (関連する実装, 状態, 一言)。表に無い節は「未実装」。キーは節番号の前置き (長い一致が優先)。
SHARED_STATUS = [
    ("1", "types.mkn・er.mkn", "実装済・未検証", "基本データタイプ (整数・Bool・SIZE/PNT/RECT・ErrCode)"),
    ("2.1", "tcode.mkn", "部分適合", "多国語・文字セット・書体セットの枠"),
    ("2.2", "tconv.mkn・jis0208.mkn", "実装済・未検証", "JIS X 0201/0208 との変換"),
    ("2.3", "tcode.mkn・tconv.mkn", "部分適合", "TRON 仕様日本文字コード (B〜D ゾーンの字形は出典なし)"),
    ("3.1", "tad.mkn", "部分適合", "TAD の概要 (セグメントの枠)"),
    ("3.2", "tad.mkn", "部分適合", "実身レコード種別 (TAD記録分類・TAD実行CPU系)"),
    ("3.3.1", "tad.mkn", "部分適合", "固定長・可変長・ラージセグメントの読み書き"),
    ("3.3.2", "tad.mkn", "部分適合", "文章データと図形データの開始・終了"),
    ("3.3.3", "tad.mkn", "部分適合", "画像データ"),
    ("3.4.1", "tad.mkn", "部分適合", "セグメントの ID 定数 (TS_*)"),
    ("3.4.2", "tad.mkn", "部分適合", "管理情報 (TAD情報書・TAD情報版)"),
    ("3.4.3", "tad.mkn", "部分適合", "文章開始／終了 (TAD文章始書・TAD始読)"),
    ("3.4.4", "tad.mkn", "部分適合", "図形開始／終了 (TAD図形始書・TAD始読)"),
    ("3.4.5", "tad.mkn", "部分適合", "画像 (TAD画像書・TAD画像読)"),
    ("3.4.6", "tad.mkn", "部分適合", "仮身 (TAD仮身書・TAD仮身読)"),
    ("3.4.7", "tad.mkn", "部分適合", "機能付箋 (TAD機能付箋書・読)"),
    ("3.4.8", "tad.mkn", "部分適合", "指定付箋 (TAD指定付箋書・読)"),
    ("3.5", "tad.mkn・tadvec.mkn", "部分適合", "文章付箋の LEN の規定 (39 件を原文から生成した試験)。用紙・余白は読み書き済み、他の付箋の欄は未解釈"),
    ("3.6", "tad.mkn・tadvec.mkn", "部分適合", "図形セグメントの LEN の規定 (25 件を原文から生成した試験)。長方形・線属性は読み書き済み、他の欄は未解釈"),
    ("付録A", "tad.mkn", "実装済・未検証", "TAD セグメント ID の一覧"),
]


def shared_sections(work):
    """共有データ編の節と、節ごとの #define・構造体名。"""
    files = [("data_type", "第1章"), ("tron_code", "第2章"), ("tad1", "第3章"), ("tad2", "第3章"), ("tad3", "第3章"), ("fd_format", "第4章")]
    rows = []
    for fn, chap in files:
        t = open(os.path.join(work, "shared_data", fn + ".txt")).read()
        t = t.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
        heads = [(m.start(), m.group(1), m.group(2).strip()) for m in re.finditer(r"^(\d+(?:\.\d+)+)[ \u3000]+(\S[^\n]*)$", t, re.M)]
        # 表の中の参照行を見出しと誤って拾わないよう、数字が単調に増えるものだけ残す
        keep = []
        last = None
        for pos, num, title in heads:
            key = tuple(int(x) for x in num.split("."))
            if last is None or key > last:
                keep.append((pos, num, title))
                last = key
        if fn == "data_type":
            keep = [(0, "1", "基本データタイプ")]
        for i, (pos, num, title) in enumerate(keep):
            end = keep[i + 1][0] if i + 1 < len(keep) else len(t)
            seg = t[pos:end]
            defs = []
            for d in re.findall(r"#define\s+([A-Za-z_][A-Za-z0-9_]*)", seg):
                if d not in defs:
                    defs.append(d)
            structs = []
            for d in re.findall(r"}\s*([A-Z][A-Za-z0-9_]*)\s*;", seg):
                if d not in structs:
                    structs.append(d)
            rows.append((fn, num, title, defs, structs))
    return rows


def shared_status(num):
    best = None
    for pre, impl, state, note in SHARED_STATUS:
        if num == pre or num.startswith(pre + "."):
            if best is None or len(pre) > len(best[0]):
                best = (pre, impl, state, note)
    return best[1:] if best else ("なし", "未実装", "")


def shared_md(work):
    rows = shared_sections(work)
    L = ["# BTRON3 共有データ編 節別マトリクス（生成物）", "",
         "> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42)。`python3 tools/spec_matrix.py shared <作業ディレクトリ>` で生成（原文の取得は `fetch`）。",
         "> 原文の本文は転載せず、節番号・表題・`#define` 名・構造体名だけを記録する。要求の要約は [btron3-shared-data.md](btron3-shared-data.md)。", "",
         "- 状態の判定は `tools/spec_matrix.py` の `SHARED_STATUS`（節番号の前置きで割り当てる。人が決める）。**「適合確認済み」は 0 件**。",
         "- 実装の列は `user/btron/` の関連ファイル。節の中の個々の欄・セグメントの配置は、`tad.mkn` が解釈していないものを含む。", "",
         "| 編章 | 節 | 表題 | `#define` 名 | 構造体名 | 関連する実装 | 状態 |", "|---|---|---|---|---|---|---|"]
    n = 0
    cnt = {}
    for fn, num, title, defs, structs in rows:
        impl, state, note = shared_status(num)
        cnt[state] = cnt.get(state, 0) + 1
        d = " ".join("`%s`" % x for x in defs[:6]) + (" …(%d)" % len(defs) if len(defs) > 6 else "")
        st = " ".join("`%s`" % x for x in structs[:6]) + (" …(%d)" % len(structs) if len(structs) > 6 else "")
        L.append("| %s | %s | %s | %s | %s | %s | %s |" % (fn, num, title.replace("|", "／"), d or "—", st or "—", impl, state))
        n += 1
    L.insert(6, "- 節の数: %d（%s）。" % (n, "、".join("%s %d" % (k, v) for k, v in sorted(cnt.items()))))
    L.append("")
    return "\n".join(L)


# --- TAD の付箋 (SUBID ごとの LEN) の試験ベクトル (#42 Phase 1) -----------------------------
TEXT_IDS = {"3.5.2": "TS_TPAGE", "3.5.3": "TS_TRULER", "3.5.4": "TS_TFONT", "3.5.5": "TS_TUB", "3.5.6": "TS_TATTR",
            "3.5.7": "TS_TSTYLE", "3.5.8": "TS_TVAR", "3.5.9": "TS_TMEMO", "3.5.10": "TS_TAPPL"}
FIG_IDS = {"3.6.2": "TS_FPRIM", "3.6.3": "TS_FDEF", "3.6.4": "TS_FGRP", "3.6.5": "TS_FMAC", "3.6.6": "TS_FATTR",
           "3.6.8": "TS_FMEMO"}


def tad_catalog(work):
    """文章付箋 (tad2) と図形セグメント (tad3) の (節, ID, SUBID, LEN の書き方, 表題)。付録は除く。"""
    out = []
    for fn, ids in (("tad2", TEXT_IDS), ("tad3", FIG_IDS)):
        t = open(os.path.join(work, "shared_data", fn + ".txt")).read().replace("&lt;", "<").replace("&gt;", ">")
        lines = t.split("\n")
        end = len(lines)
        for i, ln in enumerate(lines):
            if re.match(r"^付録", ln) or re.match(r"^3\.6\.9\b", ln) and fn == "tad3" and i > 0 and False:
                end = i
                break
        sec = None
        title = ""
        for i, ln in enumerate(lines[:end]):
            m = re.match(r"^(\d+\.\d+(?:\.\d+)*)[ \u3000]+(\S.*)$", ln)
            if m and not re.match(r"^\d+\.\d+\.\d+\.\d+", ln):
                sec = m.group(1)
            if (re.match(r"^[^\s□].*[:：](基本|拡張)レベル\s*$", ln)) or (re.match(r"^\S.*(セグメント|付箋)\s*$", ln) and not ln.startswith("□")):
                title = ln.strip()
            if re.match(r"^\s*LEN\s*:", ln) and sec in ids and i + 1 < len(lines):
                sm = re.match(r"^\s*SUBID\s*:\s*(\d+)\b", lines[i + 1])
                if not sm:
                    continue
                lenspec = re.sub(r"\s+", " ", ln.split(":", 1)[1].strip())
                out.append((fn, sec, ids[sec], int(sm.group(1)), lenspec, title))
    return out


def tad_lens(spec):
    """LEN の書き方 → (固定の長さの列, 以上なら下限)。分からなければ (None, None)。"""
    spec = spec.replace("＋", "+").replace("，", ",").replace("、", ",")
    if re.fullmatch(r"\d+(\s*,\s*\d+)*", spec):
        return [int(x) for x in re.split(r"\s*,\s*", spec)], None
    m = re.fullmatch(r"(\d+)\s*〜", spec)
    if m:
        return None, int(m.group(1))
    if spec == "〜":
        return None, 0
    return None, None


def tad_mkn(work):
    """既存の TAD文章付箋検・TAD図形付箋検が規定どおりかを調べる試験ベクトル (機械漢文)。"""
    cat = tad_catalog(work)
    L = ["註 生成物 (python3 tools/spec_matrix.py tadvec <作業ディレクトリ>)。共有データ編 3.5・3.6 の LEN の規定 (SUBID ごと) を TAD文章付箋検・TAD図形付箋検に当てる。",
         "註 戻り値は食い違いの数。規定の長さで 1、固定長なら規定の長さ + 2 で 0 になるはず。LEN が「〜」の規定は下限 + 200 で 1。要: btron/tad.mkn。", ""]
    for kind, fn_name, call in (("text", "TAD仕様文章", "TAD文章付箋検"), ("fig", "TAD仕様図形", "TAD図形付箋検")):
        want = "tad2" if kind == "text" else "tad3"
        L.append("術曰「%s」 返 無符六四" % fn_name)
        L.append("    設「違」之無符六四 為 0")
        n = 0
        for fn, sec, tsid, sub, spec, title in cat:
            if fn != want:
                continue
            fixed, lower = tad_lens(spec)
            checks = []
            if fixed:
                for v in fixed:
                    checks.append((v, 1))
                if len(fixed) == 1:
                    checks.append((fixed[0] + 2, 0))
            elif lower is not None:
                checks.append((lower + 200, 1))
            for ln_, exp in checks:
                L.append("    若 呼「%s」以(「%s」, %d, %d) 不等 %d 則" % (call, tsid, sub, ln_, exp))
                L.append("        置「違」為 違 加 1")
                L.append("    終若")
                n += 1
        L.append("    歸 違")
        L.append("終術")
        L.append("")
    return "\n".join(L)


def tad_md(work):
    cat = tad_catalog(work)
    L = ["# BTRON3 TAD 付箋・図形セグメントの LEN 規定（生成物）", "",
         "> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) Phase 1。`python3 tools/spec_matrix.py tadcat <作業ディレクトリ>` で生成（原文の取得は `fetch`）。",
         "> 共有データ編 3.5（文章付箋）と 3.6（図形）の SUBID ごとの LEN の規定。付録の再掲は除く。原文の説明文は転載しない。",
         "> 試験: 同じ規定から生成した `user/btron/tadvec.mkn` を `識試` が実行する（`TAD仕様ベクタ文章`・`TAD仕様ベクタ図形`）。", "",
         "| 節 | 親 ID | SUBID | LEN の規定 | 表題 |", "|---|---|---|---|---|"]
    for fn, sec, tsid, sub, spec, title in cat:
        L.append("| %s | `%s` | %d | %s | %s |" % (sec, tsid, sub, spec.replace("|", "／"), title.replace("|", "／")[:40]))
    L.append("")
    L.append("合計 %d 件（文章 %d、図形 %d）。" % (len(cat), sum(1 for c in cat if c[0] == "tad2"), sum(1 for c in cat if c[0] == "tad3")))
    L.append("")
    return "\n".join(L)


def consts_md(work):
    """原文の #define の値と、user/btron/*.mkn の 常「名」 の値を突き合わせる。"""
    spec = {}
    for f in sorted(glob.glob(os.path.join(work, "os_spec/*/*.txt")) + glob.glob(os.path.join(work, "shared_data/*.txt"))):
        t = open(f).read().replace("&lt;", "<").replace("&gt;", ">")
        for m in re.finditer(r"#define\s+([A-Za-z_]\w*)\s+(\(?-?(?:0x[0-9A-Fa-f]+|\d+)\)?)(?=\s|/|$)", t):
            spec.setdefault(m.group(1), set()).add((m.group(2).strip("()"), os.path.basename(f)))
    impl = {}
    for f in glob.glob(os.path.join(ROOT, "user/btron/*.mkn")):
        for m in re.finditer(r"常「([A-Za-z_]\w*)」之\S+ 為 (-?(?:0x[0-9A-Fa-f]+|\d+))", open(f).read()):
            impl.setdefault(m.group(1), set()).add((m.group(2), os.path.basename(f)))

    def val(x):
        return int(x, 16) if x.lower().startswith(("0x", "-0x")) else int(x)

    both = [k for k in spec if k in impl]
    bad = []
    n = 0
    for k in both:
        for sv, sf in spec[k]:
            n += 1
            ivs = {val(a) for a, _ in impl[k]}
            if val(sv) not in ivs and (val(sv) & 0xFFFFFFFF) not in {i & 0xFFFFFFFF for i in ivs}:
                bad.append((k, sv, sf, sorted(impl[k])))
    L = ["# BTRON3 定数の値の照合（生成物）", "",
         "> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42)。`python3 tools/spec_matrix.py consts <作業ディレクトリ>` で生成（原文の取得は `fetch`）。",
         "> 原文の `#define 名 数値` と、`user/btron/*.mkn` の `常「名」之… 為 数値` を名前で突き合わせる（32 ビットに丸めた値も同じとみなす）。", "",
         "- 原文の数値の定数: **%d**。そのうち実装に同名の定数があるもの: **%d**（%d 組を比較）。" % (len(spec), len(both), n),
         "- 値が食い違うもの: **%d**。" % len(bad), ""]
    if bad:
        L += ["| 定数 | 原文の値 | 原文のページ | 実装の値（ファイル） |", "|---|---|---|---|"]
        for k, sv, sf, iv in bad:
            L.append("| `%s` | %s | %s | %s |" % (k, sv, sf, "、".join("%s (%s)" % x for x in iv)))
        L.append("")
    L.append("実装に無い定数 %d 個は、未実装の関数やデータ構造に属するもの（一覧は生成時に `consts` の出力で確認する）。" % (len(spec) - len(both)))
    L.append("")
    return "\n".join(L)


if __name__ == "__main__":
    cmd, work = sys.argv[1], sys.argv[2]
    if cmd == "fetch":
        fetch(work)
    elif cmd == "matrix":
        print(matrix(work))
    elif cmd == "tadvec":
        print(tad_mkn(work))
    elif cmd == "tadcat":
        print(tad_md(work))
    elif cmd == "consts":
        print(consts_md(work))
    elif cmd == "shared":
        print(shared_md(work))
    else:
        sys.exit("使い方: spec_matrix.py fetch|matrix <作業ディレクトリ>")
