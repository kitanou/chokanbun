#!/usr/bin/env python3
# 核の ELF から、独立ブートローダー「導」(boot/loader.mkn) が読む KBL1 イメージを作る。
# 使い方: mkkernelimg.py kernel.elf kernel.img
# 形式: 区画 0 = ヘッダ { +0 魔 'KBL1' (u32 LE), +4 段数 (u32), +8 入口 (u64), +16 から 32 B ずつの段:
#   p_paddr, 区画の位置 (イメージの先頭から), filesz, memsz (各 u64) }。各段の中身は 512 B 境界から始まり、境界まで 0 で埋める。
import struct
import sys


def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, 'rb').read()
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        sys.exit('ELF64 リトルエンディアンではない')
    entry = struct.unpack_from('<Q', data, 0x18)[0]
    phoff = struct.unpack_from('<Q', data, 0x20)[0]
    phentsize, phnum = struct.unpack_from('<HH', data, 0x36)
    segs = []
    for i in range(phnum):
        p_type, _flags, p_offset, _vaddr, p_paddr, p_filesz, p_memsz, _align = struct.unpack_from(
            '<IIQQQQQQ', data, phoff + i * phentsize)
        if p_type == 1 and p_memsz > 0:
            segs.append((p_paddr, p_offset, p_filesz, p_memsz))
    if not segs or len(segs) > 8:
        sys.exit('段の数が不正: %d' % len(segs))
    body = b''
    table = []
    sector = 1
    for paddr, off, filesz, memsz in segs:
        chunk = data[off:off + filesz]
        pad = (-len(chunk)) % 512
        table.append((paddr, sector, filesz, memsz))
        body += chunk + b'\0' * pad
        sector += (len(chunk) + pad) // 512
    head = struct.pack('<4sIQ', b'KBL1', len(segs), entry)
    for t in table:
        head += struct.pack('<QQQQ', *t)
    head += b'\0' * (512 - len(head))
    open(dst, 'wb').write(head + body)
    print('KBL1: 段 %d、入口 0x%x、%d 区画' % (len(segs), entry, sector))


main()
