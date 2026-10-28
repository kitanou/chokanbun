/* a64.mkn (AArch64 アセンブラ) の試験用ホスト殻: asm の文章のファイルを機械語にして 16 進で出す (llvm-mc との比較用)。
 * 使い方: asm_host 文章.s  (1 語 1 行の 8 桁 16 進。解釈できなければ終了コード 1、再配置が要れば 2) */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

extern uint64_t asm_test(const char *src, uint64_t len, char *work, uint64_t workcap, char *out);

int main(int argc, char **argv) {
    if (argc != 2) return 3;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 3;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *src = malloc(n + 1);
    if (fread(src, 1, n, f) != (size_t)n) return 3;
    fclose(f);
    uint64_t workcap = 8u << 20;
    char *work = malloc(workcap), *out = malloc(1 << 20);
    uint64_t r = asm_test(src, (uint64_t)n, work, workcap, out);
    if (r == UINT64_MAX) return 1;
    if (r == UINT64_MAX - 1) return 2;
    for (uint64_t i = 0; i + 3 < r + 3; i += 4)
        printf("%02x%02x%02x%02x\n", (unsigned char)out[i+3], (unsigned char)out[i+2], (unsigned char)out[i+1], (unsigned char)out[i]);
    return 0;
}
