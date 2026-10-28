/* セルフホスト第 5 段の試験用ホスト殻 (docs/selfhost-plan.md)。機械漢文のコンパイラ (selfhost/driver.mkn) をホストで動かす。
 * ファイルの読み込み (file_read) と結果の出力だけを持つ。取込の展開もコンパイルも機械漢文の側にある。
 * 使い方: cc_host 根.mkn  (IR は標準出力。診断は標準エラーへ出して終了コード 1、字句・構文の誤りは 2) */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

extern uint64_t chokanbun_compile(const char *root, uint64_t rootlen, char *work, uint64_t workcap, char *out, uint64_t outcap, uint64_t *status);

uint64_t file_read(const char *path, uint64_t len, char *dst, uint64_t cap) {
    char *p = malloc(len + 1);
    memcpy(p, path, len); p[len] = 0;
    FILE *f = fopen(p, "rb");
    free(p);
    if (!f) return UINT64_MAX;
    uint64_t n = fread(dst, 1, cap, f);
    int more = fgetc(f) != EOF;
    fclose(f);
    return more ? cap + 1 : n;
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s root.mkn\n", argv[0]); return 3; }
    uint64_t workcap = 512ull << 20;
    char *work = malloc(workcap);
    uint64_t outcap = 64ull << 20;
    char *out = malloc(outcap);
    uint64_t status = 0;
    uint64_t r = chokanbun_compile(argv[1], strlen(argv[1]), work, workcap, out, outcap, &status);
    if (r >= (UINT64_MAX - 1)) return 2;
    if (status) { fwrite(out, 1, r, stderr); return 1; }
    fwrite(out, 1, r, stdout);
    return 0;
}
