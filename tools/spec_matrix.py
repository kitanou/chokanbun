#!/usr/bin/env python3
"""BTRON3 仕様書 (OS 仕様編) の関数を抽出し、実装・試験と照合する (#42 Phase 0)。

使い方:
  python3 tools/spec_matrix.py fetch <作業ディレクトリ>     原文を取得して UTF-8 の .txt にする
  python3 tools/spec_matrix.py matrix <作業ディレクトリ>    docs/compat/btron3-matrix.md を標準出力へ
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
        body.append("| 関数 | 原型 | 実装 | 試験 | 原文のエラー | 本体に現れないエラー |")
        body.append("|---|---|---|---|---|---|")
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
            body.append(f"| `{name}` | {'`' + pr + '`' if pr else '—'} | {im} | {te} | {len(codes)} | {cell} |")
        body.append("")
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
    ("3.2", "なし", "未実装", "TAD 実身構成 (レコード種別)"),
    ("3.3.1", "tad.mkn", "部分適合", "固定長・可変長・ラージセグメントの読み書き"),
    ("3.4.1", "tad.mkn", "部分適合", "セグメントの ID 定数 (TS_*)"),
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


if __name__ == "__main__":
    cmd, work = sys.argv[1], sys.argv[2]
    if cmd == "fetch":
        fetch(work)
    elif cmd == "matrix":
        print(matrix(work))
    elif cmd == "shared":
        print(shared_md(work))
    else:
        sys.exit("使い方: spec_matrix.py fetch|matrix <作業ディレクトリ>")
