#!/usr/bin/env python3
"""JIS X 0208 (1983) -> Unicode の対応表から user/btron/jis0208.mkn を生成する。

出典: Python 標準の euc_jp コーデック (JIS X 0208 の区点 → Unicode の対応)。
JIS X 0208:1990 で足された 84 区 5・6 点 (0x7425・0x7426) は、TRON コード体系 (共有データ編 2.2.2) が
6,877 字 (漢字 6,353) と書く 1983 年版に合わせて除く。
表は 94 区 × 94 点 = 8,836 項を、区点の昇順に 1 項 4 桁の 16 進で並べた文字列 (割当なしは 0000)。
使い方: python3 tools/gen-jis0208.py > user/btron/jis0208.mkn
"""
import sys

EXCLUDE = {0x7425, 0x7426}
HEADER = """註 JIS X 0208 (1983) → Unicode の対応表。tools/gen-jis0208.py が生成する (手で編集しない)。
註 TRON コード体系の第 1 ブロック (A ゾーン) は JIS X 0208 とコードの位置が同じ (共有データ編 2.3.3)。
註 出典は Python の euc_jp コーデック。割当は %d 字 (漢字 %d)。84 区 5・6 点 (1990 年版の追加) は除く。
註 注意: 0x2140 は U+FF3C (全角の逆斜線)。JIS0208.TXT の U+005C ではない。
"""

def main():
    cells = []
    n = kanji = 0
    for a in range(0x21, 0x7F):
        for b in range(0x21, 0x7F):
            code = (a << 8) | b
            u = 0
            if code not in EXCLUDE:
                try:
                    c = bytes([a | 0x80, b | 0x80]).decode("euc_jp")
                    if len(c) == 1:
                        u = ord(c)
                except UnicodeDecodeError:
                    pass
            if u:
                n += 1
                if 0x3021 <= code <= 0x7426:
                    kanji += 1
            cells.append("%04X" % u)
    sys.stdout.write(HEADER % (n, kanji))
    sys.stdout.write("\n術曰「JIS表址」 返 指標〈無符八〉\n")
    sys.stdout.write("    歸 取址(『%s』)\n終術\n" % "".join(cells))

main()
