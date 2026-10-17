/* Provisional UART routine for QEMU virt / AArch64.
 *
 * This is bootstrap glue only; it will be replaced by a machine-kanbun MMIO
 * driver in a later milestone (see docs/roadmap.md, Phase 2).
 *
 * PL011 UART at 0x09000000:
 *   0x000: UARTDR (data register)
 *   0x018: UARTFR (flag register) - bit 5 = TX FIFO full
 *
 * The symbol name matches the 外術曰 declaration in tests/uart.txt so that
 * the machine-kanbun caller 核外輸出 resolves at link time.
 */

#define UART_BASE 0x09000000UL
#define UART_DR   (*(volatile unsigned int *)(UART_BASE + 0x000))
#define UART_FR   (*(volatile unsigned int *)(UART_BASE + 0x018))
#define FR_TXFF   (1u << 5)

void 核外輸出(const unsigned char *s, unsigned long len) {
    for (unsigned long i = 0; i < len; i++) {
        while (UART_FR & FR_TXFF) {
        }
        UART_DR = s[i];
    }
}
