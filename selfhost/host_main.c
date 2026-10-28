/* セルフホスト第 1 段の試験用ホスト殻 (docs/selfhost-plan.md)。
 * 機械漢文の字句解析器 (selfhost/lexer.mkn) をホストで動かし、C++ 版 -tokens と出力を比べるための入出力だけを持つ。
 * 字句解析そのものはここには無い。使い方: lexer_host 源.mkn  (結果は標準出力。失敗は終了コード 1) */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

extern uint64_t lex_tokenize(uint64_t *state, const char *src, uint64_t len, char *out, uint64_t cap);

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s source.mkn\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 2; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *src = malloc(n + 1);
    if (fread(src, 1, n, f) != (size_t)n) { fprintf(stderr, "read error\n"); return 2; }
    fclose(f);
    uint64_t cap = (uint64_t)n * 40 + 4096;
    char *out = malloc(cap);
    uint64_t state[32] = {0};
    uint64_t r = lex_tokenize(state, src, (uint64_t)n, out, cap);
    if (r >= (UINT64_MAX - 1)) return 1;
    fwrite(out, 1, r, stdout);
    return 0;
}
