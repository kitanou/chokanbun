#!/usr/bin/env python3
"""漢令番号の照合: kernel/kernel.mkn の漢令處理が扱う番号 (`番号 等於 N 則`) と、
docs/abi-aarch64.md の漢令表の番号が一致するかを調べる (docs/principles-map.md 令出必行)。
未知の番号の許可リスト (`番号 不等 N`) の番号は、処理にも文書にもあること。食い違いがあれば表示して 1 で終わる。"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
kernel = (root / "kernel/kernel.mkn").read_text()
abi = (root / "docs/abi-aarch64.md").read_text()

handled = {int(n) for n in re.findall(r"番号 等於 (\d+) 則", kernel)}
m = re.search(r"若 \(番号 大於 16\)[^\n]*", kernel)
allowed = {int(n) for n in re.findall(r"番号 不等 (\d+)", m.group(0))} if m else set()
# 文書の漢令表: 行頭が「| 番号 | 名」の行。末尾の 511 などは例外コード表なので、表の見出しの範囲 (0〜400) に限る。
documented = {int(n) for n in re.findall(r"^\s*\|\s*(\d+)\s*\|\s*\S", abi, re.M) if int(n) < 400}

bad = 0
for name, a, b in (("処理にあるが文書に無い", handled, documented),
                   ("文書にあるが処理に無い", documented, handled),
                   ("許可リストにあるが処理に無い", allowed, handled),
                   ("許可リストにあるが文書に無い", allowed, documented)):
    diff = sorted(a - b)
    if diff:
        print(f"漢令番号 {name}: {diff}")
        bad += 1
print(f"漢令番号: 処理 {len(handled)} 件、文書 {len(documented)} 件、許可リスト {len(allowed)} 件")
sys.exit(1 if bad else 0)
