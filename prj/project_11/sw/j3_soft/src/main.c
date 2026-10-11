/* ============================================================================
 * prj11 B2: 软核版 J3 随机读驱动 (j3_soft)
 *
 * 角色互换: prj10 J3 里 PC 走 UDP 命令通道 (SET_MODE/READ_SLOT)；B2 里这些
 * 控制命令全部改由 MicroBlaze 经 AXI-Lite (axi_lite_regs @0x44A00000) 下发,
 * UDP 命令通道降级为对照。PC 只剩两个角色:
 *   1. 数据面: 写 N 帧到板:1234 (源 PC:1236), 收读出帧回显
 *   2. 场次编排: 经 COM5@9600 给 C 发单字符命令, 读 C 的进度/计数行
 *
 * UART 协议 (PC→C 单字符; C→PC 行, \r\n 结尾):
 *   'M' 第1次 = 本轮类型 M(主轮) : SET_MODE(SEQ)          -> "[B2] SEQOK t=M"
 *       (PC 在 SEQ 窗口做 UDP 预热: RND 下板卡无法发 ARP 应答, PC 邻居表
 *        会老化 -> 单播数据帧被 PC 丢弃 —— j3_random_read.py 2026-10-08 实证)
 *   'M' 第2次 = GO: SET_MODE(RND) + 稳定基线 -> "[B2] READY t=M wr0=%u rd0=%u"
 *       然后本轮自动跑完 (无需再交互):
 *         等 wm_wr 增量==N(10s超时) -> 逆序 255..0 逐槽 RD_SLOT,
 *         每槽等 wm_rd 增量到位(300ms超时)再发下一条 -> 完成打印 DONE
 *   'A' 同上两段, 负向 A: 跳过 1 槽 sA=(wr0+100)%256 (帧#100 的槽)
 *   'B' 同上两段, 负向 B: 256 槽读完后重读 sB=(wr0+50)%256 (预期无数据)
 *   'S' 任何时候: 恢复 SET_MODE(SEQ) -> "[B2] SEQRESTORED"
 *   'I' ID/计数快照
 *
 * 判据对应 (契约 §4.1/§4.2, 由 PC 侧 j3_soft_verify.py 判):
 *   主轮 M: J3 逆序对>0 + 逐帧对应 + J3' 集合相等; wr+=256 rd+=256
 *   负向 A: 恰缺 1 帧(帧#100); rd+=255
 *   负向 B: 命令 257 实收 256; 重读槽无数据(rd 不增)
 *
 * 读冲刷 (坑 #39): 每次读寄存器前向被忽略偏移 0x2C 哑写一笔 (OKAY 零副作用,
 * 板上实证不进任何计数), 治愈 M01 读"休眠边界后首笔落后一笔"。
 * 基线口径 (契约 §4.1 步0): SET_MODE 在取基线**之前**完成 —— SET_MODE 自身
 * 对 u_wr_frame 的 +1 (板上实测) 被基线吸收; 轮末恢复 SEQ 在 DONE 打印**之后**,
 * 不污染本轮计数对账。
 * ==========================================================================*/

#define UART_BASE 0x40600000u
#define REGS_BASE 0x44A00000u

#define UART_RX   (*(volatile unsigned *)(UART_BASE + 0x0))
#define UART_TX   (*(volatile unsigned *)(UART_BASE + 0x4))
#define UART_ST   (*(volatile unsigned *)(UART_BASE + 0x8))
#define UART_ST_RX_VALID 0x1u
#define UART_ST_TX_FULL  0x8u

#define R_MODE    (*(volatile unsigned *)(REGS_BASE + 0x00))
#define R_SLOT    (*(volatile unsigned *)(REGS_BASE + 0x04))
#define R_WM_WR   (*(volatile unsigned *)(REGS_BASE + 0x08))
#define R_WM_RD   (*(volatile unsigned *)(REGS_BASE + 0x0C))
#define R_WM_DRP  (*(volatile unsigned *)(REGS_BASE + 0x10))
#define R_SMAP    (*(volatile unsigned *)(REGS_BASE + 0x14))
#define R_STAT    (*(volatile unsigned *)(REGS_BASE + 0x18))
#define R_ID      (*(volatile unsigned *)(REGS_BASE + 0x1C))

#define MODE_SEQ 0u
#define MODE_RND 1u

#define NSLOTS    256u
#define WR_WAIT_POLLS 10000u    /* ~1ms/次 rd_reg -> 等 256 帧写齐 10s 上限 */
#define RD_WAIT_POLLS 300u      /* 单槽读出 300ms 上限 (Lr 实测 <37.7us, 极宽) */
#define DUP_WAIT_POLLS 120u     /* 负向 B 重读槽 120ms 观察窗 (预期无数据) */
#define SKIP_FRAME 100u         /* 负向 A 跳过 帧#100 的槽 */
#define DUP_FRAME  50u          /* 负向 B 重读 帧#50 的槽 */

static void uputc(char c)
{
    while (UART_ST & UART_ST_TX_FULL)
        ;
    UART_TX = (unsigned char)c;
}

static void uputs(const char *s)
{
    while (*s)
        uputc(*s++);
}

static void uputd(unsigned v)
{
    char buf[8];
    int i = 0;
    if (v == 0) { uputc('0'); return; }
    while (v && i < 7) { buf[i++] = '0' + (v % 10u); v /= 10u; }
    while (i)
        uputc(buf[--i]);
}

static void busy_ms(unsigned ms)
{
    volatile unsigned n = ms * 100u * 33u;
    while (n)
        n--;
}

/* 坑 #39 读冲刷: 哑写被忽略偏移(OKAY 零副作用, 不进计数)再读 */
static unsigned rd_reg(volatile unsigned *r)
{
    *(volatile unsigned *)(REGS_BASE + 0x2Cu) = 0u;
    busy_ms(1);
    return *r;
}

static unsigned d16(unsigned now, unsigned base)
{
    return (unsigned)(unsigned short)(now - base);
}

static int urx_poll(void)          /* 0 = 无字节 */
{
    return (UART_ST & UART_ST_RX_VALID) ? 1 : 0;
}

static char urx_get(void)
{
    return (char)(UART_RX & 0xffu);   /* 读 RX 即清 FIFO */
}

/* ---------------------------------------------------------------------------
 * 一轮 J3 (主轮 M / 负向 A / 负向 B)。进入时模式已是 RND、基线已取好。
 * 返回 0 = 正常跑完; 1 = 等写超时; 2 = 读停摆。
 * ------------------------------------------------------------------------ */
static int run_round(char type, unsigned wr0, unsigned rd0)
{
    unsigned wr, rd, issued = 0, stalls = 0;
    unsigned skip_slot, dup_slot;
    unsigned i, s;

    skip_slot = (type == 'A') ? ((wr0 + SKIP_FRAME) & 0xffu) : 0x100u; /* 0x100=不可能槽 */
    dup_slot  = (type == 'B') ? ((wr0 + DUP_FRAME)  & 0xffu) : 0x100u;

    uputs("[B2] WRWAIT t=");
    uputc(type); uputs(" want+"); uputd(NSLOTS); uputs("\r\n");
    for (i = 0; i < WR_WAIT_POLLS; i++) {
        wr = rd_reg(&R_WM_WR);
        if (d16(wr, wr0) >= NSLOTS)
            break;
    }
    wr = rd_reg(&R_WM_WR);
    if (d16(wr, wr0) < NSLOTS) {
        uputs("[B2] WAITWR-FAIL t="); uputc(type);
        uputs(" got+"); uputd(d16(wr, wr0)); uputs("\r\n");
        return 1;
    }
    if (d16(wr, wr0) > NSLOTS) {         /* 多发: 记警告不中止 (j3 先例口径) */
        uputs("[B2] WR-OVERFLOW +"); uputd(d16(wr, wr0)); uputs(" (warn)\r\n");
    }
    uputs("[B2] WRDONE t="); uputc(type); uputs("\r\n");

    for (i = 0; i < NSLOTS; i++) {       /* 逆序 255..0: 读序!=写序, 逆序对满格 */
        s = (NSLOTS - 1u) - i;
        if (s == skip_slot)
            continue;                    /* 负向 A: 跳过 1 槽 -> 恰缺 1 帧 */
        R_SLOT = s;
        issued++;
        for (wr = 0; wr < RD_WAIT_POLLS; wr++) {
            rd = rd_reg(&R_WM_RD);
            if (d16(rd, rd0) == issued)
                break;
        }
        if (d16(rd, rd0) != issued) {
            stalls++;
            uputs("[B2] STALL t="); uputc(type);
            uputs(" s="); uputd(s);
            uputs(" issued="); uputd(issued); uputs("\r\n");
            return 2;                    /* 真停摆: 中止本轮 (负向 B 重读除外) */
        }
        if ((issued & 63u) == 0) {
            uputs("[B2] RD "); uputd(issued); uputs("/256\r\n");
        }
    }

    if (type == 'B') {                   /* 重读 sB: 预期无数据 (读完即退休) */
        R_SLOT = dup_slot;
        for (wr = 0; wr < DUP_WAIT_POLLS; wr++) {
            rd = rd_reg(&R_WM_RD);
            if (d16(rd, rd0) != issued)
                break;
        }
        if (d16(rd, rd0) == issued) {
            uputs("[B2] B-DUP-NODATA s="); uputd(dup_slot);
        } else {
            uputs("[B2] B-DUP-UNEXPECTED s="); uputd(dup_slot);
            return 2;
        }
        uputs("\r\n");
    }

    wr = rd_reg(&R_WM_WR);
    rd = rd_reg(&R_WM_RD);
    uputs("[B2] DONE t="); uputc(type);
    uputs(" wr+");   uputd(d16(wr, wr0));
    uputs(" rd+");   uputd(d16(rd, rd0));
    uputs(" stall="); uputd(stalls);
    uputs("\r\n");
    return 0;
}

/* 一条轮命令的两段处理。phase0: SEQ 预热窗; phase1: RND+基线+自动跑轮 */
static void round_command(char type)
{
    unsigned wr0, rd0, prev, stable;

    R_MODE = MODE_SEQ;                   /* 段0: SEQ 窗 (PC 预热 ARP) */
    uputs("[B2] SEQOK t="); uputc(type); uputs("\r\n");
    (void)rd_reg(&R_WM_WR);              /* 等段1 字符期间不做事 */
    while (!urx_poll()) { }              /* 等 PC 预热后回送同一字符 = GO */
    if (urx_get() != type) {             /* 协议约定: GO 字符 = 类型字符 */
        uputs("[B2] GO-CHAR-MISMATCH\r\n");
        return;
    }

    R_MODE = MODE_RND;                   /* 段1: RND + 稳定基线 (契约步0) */
    stable = 0;
    prev = rd_reg(&R_WM_WR);
    wr0 = prev; rd0 = rd_reg(&R_WM_RD);
    for (unsigned k = 0; k < 8u && stable < 2u; k++) {
        unsigned w2 = rd_reg(&R_WM_WR);
        if (w2 == prev) stable++;
        else            stable = 0;
        prev = w2; wr0 = w2;
        rd0 = rd_reg(&R_WM_RD);
    }
    uputs("[B2] READY t="); uputc(type);
    uputs(" wr0="); uputd(wr0);
    uputs(" rd0="); uputd(rd0); uputs("\r\n");

    run_round(type, wr0, rd0);

    R_MODE = MODE_SEQ;                   /* 恢复 SEQ (在 DONE 打印之后, 不污染对账) */
    uputs("[B2] SEQRESTORED t="); uputc(type); uputs("\r\n");
}

int main(void)
{
    unsigned id;
    int consec = 0, n = 0;

    busy_ms(50);
    uputs("\r\n=== prj11 B2: soft-core J3 driver (j3_soft) ===\r\n");

    /* T0 排空 + ID 自检 (坑 #39: 常量寄存器读到稳定魔数再继续) */
    while (n < 8 && consec < 2) {
        if (rd_reg(&R_ID) == 0x50314231u) consec++;
        else                              consec = 0;
        n++;
    }
    id = rd_reg(&R_ID);
    uputs("[T0] drain="); uputd((unsigned)n);
    uputs(" ID="); uputd(id); uputs("\r\n");
    if (id != 0x50314231u) {
        uputs("[B2-SOFT] ID-FAIL, halt\r\n");
        for (;;) { }
    }

    uputs("[B2-SOFT] WAITCMD (M/A/B/S/I)\r\n");
    for (;;) {
        char c;
        while (!urx_poll()) { }
        c = urx_get();
        if (c == 'M' || c == 'A' || c == 'B')
            round_command(c);
        else if (c == 'S') {
            R_MODE = MODE_SEQ;
            uputs("[B2] SEQRESTORED (cmd S)\r\n");
        } else if (c == 'I') {
            uputs("[B2] ID=");   uputd(rd_reg(&R_ID) & 0xffffu);
            uputs(" wr=");       uputd(rd_reg(&R_WM_WR) & 0xffffu);
            uputs(" rd=");       uputd(rd_reg(&R_WM_RD) & 0xffffu);
            uputs(" drop=");     uputd(rd_reg(&R_WM_DRP) & 0xffffu);
            uputs("\r\n");
        }
        /* 其余字符 (\r\n 等) 忽略 */
    }
}
