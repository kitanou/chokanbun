/* セルフホスト第 6 段 (バックエンドとリンカ) の試験用ホスト殻。LLVM IR の文章 (機械漢文のコンパイラが作る) を
 * 機械漢文のバックエンド (selfhost/backend.mkn) とリンカ (selfhost/linker.mkn) で機械語にして、ファイルへ書く。
 * 使い方: kld 方式 基 入力.ll 出力 [漢像の目録]   (方式 1 = 核の ELF、2 = 漢像 KBN1、3 = 単体 ELF。基は 16 進)
 *   漢像の目録 (核の ELF に漢像を埋め込むとき): 1 行 1 像で「名前<TAB>TC の 80 桁 16 進<TAB>漢像のファイル」。
 *   核には image_table_addr / image_count_fn (像表の址と個数を返す関数) を足す (tools/gen-images.sh と同じ)。
 * 失敗したら理由を標準エラーへ出して終了コード 1。 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

extern uint64_t backend_mod(const char *ir, uint64_t len, char *work, uint64_t workcap, uint64_t extra);
extern uint64_t link_mod(uint64_t mach, uint64_t mode, uint64_t base, char *out, uint64_t outcap, uint64_t images, uint64_t nimages);

static char *slurp(const char *path, long *n) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); exit(2); }
    fseek(f, 0, SEEK_END); *n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = calloc(*n + 64, 1);
    if (fread(b, 1, *n, f) != (size_t)*n) exit(2);
    fclose(f);
    return b;
}

int main(int argc, char **argv) {
    if (argc != 5 && argc != 6) { fprintf(stderr, "usage: %s mode base in.ll out [images.txt]\n", argv[0]); return 2; }
    uint64_t mode = strtoull(argv[1], 0, 10), base = strtoull(argv[2], 0, 16);
    long n;
    char *ir0 = slurp(argv[3], &n);
    /* 漢像の目録 */
    uint64_t *desc = 0; uint64_t nimg = 0;
    char *extra = strdup("");
    if (argc == 6) {
        FILE *f = fopen(argv[5], "r");
        if (!f) { perror(argv[5]); return 2; }
        char line[4096];
        desc = calloc(256, 40);
        while (fgets(line, sizeof line, f)) {
            char *t1 = strchr(line, '\t'); if (!t1) continue; *t1++ = 0;
            char *t2 = strchr(t1, '\t'); if (!t2) continue; *t2++ = 0;
            char *nl = strchr(t2, '\n'); if (nl) *nl = 0;
            long dl; char *data = slurp(t2, &dl);
            char *tc = 0; /* TC は機械漢文のリンカが名前から作る (selfhost/linker.mkn の TC作) */
            (void)t1;
            desc[nimg * 5 + 0] = (uint64_t)strdup(line);
            desc[nimg * 5 + 1] = strlen(line);
            desc[nimg * 5 + 2] = (uint64_t)tc;
            desc[nimg * 5 + 3] = (uint64_t)data;
            desc[nimg * 5 + 4] = (uint64_t)dl;
            nimg++;
        }
        fclose(f);
        char buf[1024];
        snprintf(buf, sizeof buf,
            "\ndefine dso_local i64 @image_table_addr(\n) naked noinline nounwind {\nentry:\n"
            "call void asm sideeffect \"adrp x0, image_table\\0Aadd x0, x0, :lo12:image_table\\0Aret\", \"~{memory}\"()\nunreachable\n}\n\n"
            "define dso_local i64 @image_count_fn(\n) naked noinline nounwind {\nentry:\n"
            "call void asm sideeffect \"mov x0, #%llu\\0Aret\", \"~{memory}\"()\nunreachable\n}\n\n", (unsigned long long)nimg);
        extra = strdup(buf);
    }
    size_t tot = n + strlen(extra);
    char *ir = calloc(tot + 64, 1);
    memcpy(ir, ir0, n); memcpy(ir + n, extra, strlen(extra));
    uint64_t workcap = (uint64_t)tot * 300 + (64u << 20);
    char *work = malloc(workcap);
    uint64_t roextra = 4096;
    for (uint64_t i = 0; i < nimg; i++) roextra += desc[i * 5 + 4] + desc[i * 5 + 1] + 128;
    if (getenv("KLD_NOREUSE")) roextra |= (1ull << 40);
    uint64_t be = backend_mod(ir, (uint64_t)tot, work, workcap, roextra);
    uint64_t *st = (uint64_t *)be;
    if (st[176 / 8]) {
        fprintf(stderr, "backend error %llu at: %.*s\n", (unsigned long long)st[176 / 8], (int)st[192 / 8], (const char *)st[184 / 8]);
        return 1;
    }
    uint64_t mach = st[0];
    uint64_t *m = (uint64_t *)mach;
    if (m[160 / 8]) { fprintf(stderr, "assembler error %llu\n", (unsigned long long)m[160 / 8]); return 1; }
    uint64_t outcap = (uint64_t)tot * 8 + (64u << 20);
    char *out = malloc(outcap);
    uint64_t r = link_mod(mach, mode, base, out, outcap, (uint64_t)desc, nimg);
    if (r == UINT64_MAX) {
        uint64_t s = m[184 / 8];
        if (s) fprintf(stderr, "link error: %.*s\n", (int)*(uint64_t *)s, (const char *)(s + 8));
        else fprintf(stderr, "link error\n");
        return 1;
    }
    FILE *o = fopen(argv[4], "wb");
    fwrite(out, 1, r, o);
    fclose(o);
    /* 記号の地図 (out.map): 16 進のアドレスと名前 */
    char mp[4096]; snprintf(mp, sizeof mp, "%s.map", argv[4]);
    FILE *mf = fopen(mp, "w");
    uint64_t nsym = m[144 / 8]; uint64_t *tab = (uint64_t *)m[136 / 8];
    for (uint64_t i = 0; i < nsym; i++) {
        uint64_t *e = tab + i * 5; uint64_t nm = e[0];
        fprintf(mf, "%016llx %.*s\n", (unsigned long long)e[4], (int)*(uint64_t *)nm, (const char *)(nm + 8));
    }
    fclose(mf);
    return 0;
}
