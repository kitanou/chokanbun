/* Provisional UART routine for QEMU virt / AArch64
 * This will be replaced by a machine-kanbun MMIO driver in a later milestone.
 *
 * UART (PL011) at 0x09000000
 *   0x000: UARTDR (data)
 *   0x018: UARTFR (flag) - bit 5 = TX full
 */
#include <stdint.h>

#define UART_BASE 0x09000000
#define UART_DR   (*(volatile uint32_t *)(UART_BASE + 0x000))
#define UART_FR   (*(volatile uint32_t *)(UART_BASE + 0x018))
#define FR_TXFF   (1 << 5)

void main(void) {
    /* This is a placeholder; the real main is in machine-kanbun */
}

void putstr(const uint8_t *s, uint64_t len) {
    for (uint64_t i = 0; i < len; i++) {
        while (UART_FR & FR_TXFF)
            ;
        UART_DR = s[i];
    }
}
