/* セルフホスト第 6 段 (バックエンドとリンカ) の試験用ホスト殻。LLVM IR の文章 (機械漢文のコンパイラが作る) を
 * 機械漢文のバックエンド (selfhost/backend.mkn) とリンカ (selfhost/linker.mkn) で機械語にして、ファイルへ書く。
 * 使い方: kld 方式 基 入力.ll 出力   (方式 1 = 核の ELF、2 = 漢像 KBN1、3 = 単体 ELF。基は 16 進)
 * 失敗したら理由を標準エラーへ出して終了コード 1。 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

extern uint64_t backend_mod(const char *ir, uint64_t len, char *work, uint64_t workcap);
extern uint64_t link_mod(uint64_t mach, uint64_t mode, uint64_t base, char *out, uint64_t outcap);

int main(int argc, char **argv) {
    if (argc != 5) { fprintf(stderr, "usage: %s mode base in.ll out\n", argv[0]); return 2; }
    uint64_t mode = strtoull(argv[1], 0, 10), base = strtoull(argv[2], 0, 16);
    FILE *f = fopen(argv[3], "rb");
    if (!f) { perror(argv[3]); return 2; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *ir = calloc(n + 64, 1);
    if (fread(ir, 1, n, f) != (size_t)n) return 2;
    fclose(f);
    uint64_t workcap = (uint64_t)n * 300 + (64u << 20);
    char *work = malloc(workcap);
    uint64_t be = backend_mod(ir, (uint64_t)n, work, workcap);
    uint64_t *st = (uint64_t *)be;
    /* 後 の後失 (+176) と 後誤行 (+184)・後誤長 (+192) */
    if (st[176 / 8]) {
        fprintf(stderr, "backend error %llu at: %.*s\n", (unsigned long long)st[176 / 8], (int)st[192 / 8], (const char *)st[184 / 8]);
        return 1;
    }
    uint64_t mach = st[0];
    uint64_t *m = (uint64_t *)mach;
    if (m[160 / 8]) { fprintf(stderr, "assembler error %llu\n", (unsigned long long)m[160 / 8]); return 1; }
    uint64_t outcap = (uint64_t)n * 8 + (8u << 20);
    char *out = malloc(outcap);
    uint64_t r = link_mod(mach, mode, base, out, outcap);
    if (r == UINT64_MAX) {
        uint64_t s = m[184 / 8];
        if (s) fprintf(stderr, "link error: %.*s\n", (int)*(uint64_t *)s, (const char *)(s + 8));
        else fprintf(stderr, "link error\n");
        return 1;
    }
    FILE *o = fopen(argv[4], "wb");
    fwrite(out, 1, r, o);
    fclose(o);
    return 0;
}
