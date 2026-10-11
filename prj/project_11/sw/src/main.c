/* ============================================================================
 * prj11 B1: MicroBlaze hello + axi_lite_regs self-test (Q3 soft-core control)
 *
 * Address map (create_bd_b.tcl):
 *   AXI UARTLite 0x40600000  (9600 8N1, CH340 on COM7)
 *     +0x0 RX, +0x4 TX, +0x8 STATUS (bit3 = TX_FULL)
 *   axi_lite_regs 0x44A00000 (W5 register semantics over AXI4-Lite):
 *     +0x00 MODE    W  bit0: 0=SEQ 1=RND            (= SET_MODE)
 *     +0x04 RD_SLOT W  [7:0]: slot; forces RND + ONE read trigger
 *     +0x08 WM_WR   R  [15:0] u_wr_frame
 *     +0x0C WM_RD   R  [15:0] u_rd_frame
 *     +0x10 WM_DROP R  [15:0] u_buf_drop
 *     +0x14 SLOTMAP R  [31:24]=rule 1, [23:16]=wr slot ptr
 *     +0x18 STATUS  R  [17]=ctl_owner (0 UDP / 1 soft-core), [16]=0, [15:0]=trig cnt
 *     +0x1C ID      R  0x50314231 ("P1B1")
 *
 * Self-test cases (offline + on-board identical):
 *   T1 ID magic == 0x50314231
 *   T2 after boot ctl_owner == 0 (UDP default) and trig cnt == 0
 *   T3 MODE=1 then RD_SLOT=0x5A -> owner flips to 1, trig cnt == 1
 *      (the owner flip + counter is the observable proof of J_B1-3:
 *       the soft core actually drives the W5 register semantics)
 *   T4 read-only registers print live values (frame counters)
 * Verdict line (terminal capture): "[B1-SELFTEST] PASS (0 errors)"
 * After the verdict: heartbeat prints every ~2 s for the board session.
 * ==========================================================================*/

#define UART_BASE 0x40600000u
#define REGS_BASE 0x44A00000u

#define UART_RX   (*(volatile unsigned *)(UART_BASE + 0x0))
#define UART_TX   (*(volatile unsigned *)(UART_BASE + 0x4))
#define UART_ST   (*(volatile unsigned *)(UART_BASE + 0x8))

#define R_MODE    (*(volatile unsigned *)(REGS_BASE + 0x00))
#define R_SLOT    (*(volatile unsigned *)(REGS_BASE + 0x04))
#define R_WM_WR   (*(volatile unsigned *)(REGS_BASE + 0x08))
#define R_WM_RD   (*(volatile unsigned *)(REGS_BASE + 0x0C))
#define R_WM_DRP  (*(volatile unsigned *)(REGS_BASE + 0x10))
#define R_SMAP    (*(volatile unsigned *)(REGS_BASE + 0x14))
#define R_STAT    (*(volatile unsigned *)(REGS_BASE + 0x18))
#define R_ID      (*(volatile unsigned *)(REGS_BASE + 0x1C))

static void uputc(char c)
{
    while (UART_ST & 0x8u)          /* wait !TX_FULL */
        ;
    UART_TX = (unsigned char)c;
}

static void uputs(const char *s)
{
    while (*s)
        uputc(*s++);
}

static void uputh(unsigned v)       /* 8 hex digits */
{
    static const char hex[] = "0123456789abcdef";
    int i;
    uputs("0x");
    for (i = 28; i >= 0; i -= 4)
        uputc(hex[(v >> i) & 0xfu]);
}

static void uputd(unsigned v)       /* decimal (u16 range is enough) */
{
    char buf[8];
    int i = 0;
    if (v == 0) { uputc('0'); return; }
    while (v && i < 7) { buf[i++] = '0' + (v % 10u); v /= 10u; }
    while (i)
        uputc(buf[--i]);
}

static void busy_ms(unsigned ms)    /* ~100 MHz: 100 cycles/us, crude */
{
    volatile unsigned n = ms * 100u * 33u;
    while (n)
        n--;
}

/* M01 read-path flush (J_B1 2026-10-11 board evidence): an axi_lite_regs
 * read issued directly after UART (M00) traffic returns the data of the
 * PREVIOUS M01 read; a WRITE preceding the read makes it fresh (diag: 8/8).
 * A dummy write to the ignored-offset window (OKAY response, no register
 * effect, no counter side effect) flushes the path. Double-read does NOT
 * (second consecutive read was still stale on board). */
static unsigned rd_reg(volatile unsigned *r)
{
    *(volatile unsigned *)(REGS_BASE + 0x2Cu) = 0u;  /* ignored offset */
    busy_ms(1);                                      /* let the write land */
    return *r;
}

int main(void)
{
    int fail = 0;
    unsigned id, st0, st1, wm, rd, dr, sm;

    busy_ms(50);                    /* let the UART side settle */
    uputs("\r\n=== prj11 B1: MicroBlaze control plane ===\r\n");

    /* T0 bus-pipeline drain: the axi_interconnect M01 conversion may leave
     * up to two stale R beats queued across a master idle/handoff (J_B1
     * 2026-10-11: the first reads after a JTAG<->CPU handoff returned
     * one-behind data; steady-state reads were always correct). Read the
     * CONSTANT ID register until two consecutive reads return the magic --
     * self-synchronizing, no fixed drain depth assumed. */
    {
        int consec = 0, n = 0;
        while (n < 8 && consec < 2) {
            if (R_ID == 0x50314231u) consec++;
            else                     consec = 0;
            n++;
        }
        uputs("[T0] drain = "); uputd((unsigned)n); uputs(" reads\r\n");
    }

    /* T1: ID magic */
    id = rd_reg(&R_ID);
    uputs("[T1] ID reg   = "); uputh(id);
    if (id == 0x50314231u) uputs("  PASS\r\n");
    else                   { uputs("  FAIL\r\n"); fail++; }

    /* T2: boot defaults -- owner = UDP(0), trig = 0 */
    st0 = rd_reg(&R_STAT);
    uputs("[T2] boot STAT= "); uputh(st0);
    if (((st0 >> 17) & 1u) == 0u && (st0 & 0xffffu) == 0u)
        uputs("  PASS (owner=UDP, trig=0)\r\n");
    else { uputs("  FAIL\r\n"); fail++; }

    /* T3: soft-core takes over: MODE=1 then RD_SLOT=0x5A
     *     -> owner flips to 1, one read trigger fired */
    R_MODE = 1u;
    R_SLOT = 0x5Au;
    busy_ms(2);                     /* mailbox round trip is ~us scale */
    st1 = rd_reg(&R_STAT);
    uputs("[T3] after MODE+RD_SLOT: STAT = "); uputh(st1);
    uputs("  owner=");  uputd((st1 >> 17) & 1u);
    uputs(" trig=");    uputd(st1 & 0xffffu);
    if (((st1 >> 17) & 1u) == 1u && (st1 & 0xffffu) == 1u)
        uputs("  PASS (owner=soft, trig=1)\r\n");
    else { uputs("  FAIL\r\n"); fail++; }

    /* T4: live read-only registers (frame counters, rule/ptr) */
    wm  = rd_reg(&R_WM_WR);  rd = rd_reg(&R_WM_RD);  dr = rd_reg(&R_WM_DRP);  sm = rd_reg(&R_SMAP);
    uputs("[T4] wm_wr=");   uputd(wm & 0xffffu);
    uputs("  wm_rd=");      uputd(rd & 0xffffu);
    uputs("  wm_drop=");    uputd(dr & 0xffffu);
    uputs("  rule=");       uputd((sm >> 24) & 0xffu);
    uputs("  wr_slot=");    uputd((sm >> 16) & 0xffu);
    uputs("\r\n");

    /* verdict */
    if (fail == 0)
        uputs("[B1-SELFTEST] PASS (0 errors)\r\n");
    else {
        uputs("[B1-SELFTEST] FAIL ("); uputd((unsigned)fail); uputs(" errors)\r\n");
    }

    /* diagnostic: deterministic data marker via trig counter (RD_SLOT
     * writes increment [15:0] of STATUS). After a ~ms idle gap following
     * a WRITE, read STATUS three times back-to-back: fresh path must
     * return the same trig value on all three (J_B1 2026-10-11). */
    for (unsigned k = 0; k < 8; k++) {
        unsigned a, b, c;
        R_SLOT = 0x5Au;             /* trig++ (deterministic marker) */
        busy_ms(1);                 /* idle gap before first read */
        a = R_STAT;
        b = R_STAT;
        c = R_STAT;
        uputs("[DG] trig a="); uputd(a & 0xffffu);
        uputs(" b=");               uputd(b & 0xffffu);
        uputs(" c=");               uputd(c & 0xffffu);
        uputs("\r\n");
    }

    /* heartbeat: live counters every ~2 s (board session observation) */
    for (;;) {
        busy_ms(2000);
        wm = rd_reg(&R_WM_WR); rd = rd_reg(&R_WM_RD);
        uputs("[HB] wm_wr="); uputd(wm & 0xffffu);
        uputs(" wm_rd=");     uputd(rd & 0xffffu);
        uputs(" trig=");      uputd(rd_reg(&R_STAT) & 0xffffu);
        uputs("\r\n");
    }
}
