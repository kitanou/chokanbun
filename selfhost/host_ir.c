/* セルフホスト第 4 段の試験用ホスト殻 (docs/selfhost-plan.md)。機械漢文の IR 生成器 (selfhost/irgen.mkn) を
 * ホストで動かし、C++ 版 -ir と出力を比べるための入出力だけを持つ。IR 生成そのものはここには無い。
 * 使い方: irgen_host 源.mkn  (IR は標準出力。型検査・IR 生成の診断は標準エラーへ出して終了コード 1、字句・構文の誤りは 2) */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

extern uint64_t irgen_mod(const char *src, uint64_t len, char *work, uint64_t workcap, char *out, uint64_t outcap, uint64_t *status);

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s source.mkn\n", argv[0]); return 3; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 3; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *src = malloc(n + 1);
    if (fread(src, 1, n, f) != (size_t)n) { fprintf(stderr, "read error\n"); return 3; }
    fclose(f);
    uint64_t workcap = (uint64_t)n * 1500 + (4 << 20);
    char *work = malloc(workcap);
    uint64_t outcap = (uint64_t)n * 400 + (1 << 20);
    char *out = malloc(outcap);
    uint64_t status = 0;
    uint64_t r = irgen_mod(src, (uint64_t)n, work, workcap, out, outcap, &status);
    if (r >= (UINT64_MAX - 1)) return 2;
    if (status) { fwrite(out, 1, r, stderr); return 1; }
    fwrite(out, 1, r, stdout);
    return 0;
}
