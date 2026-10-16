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
 *   'E' B3-1b: 读引擎切 DMA(引擎位=1) -> RND 逐帧服务 {slot,len} 请求
 *       (SA=槽基址对齐读, LEN=len+50 前导补, shim 丢 50 前导) -> 引擎位=0
 *       -> "[B2] E-DONE rd=N stall=N"
 *   'E' B3-1b: read engine -> DMA round; serves {slot,len} requests via
 *       MM2S aligned reads (LEN=len+50, shim drops the 50B prefix)
 *       -> "[B2] E-DONE served=N rd+=N stall=0"
 *   'd' B3-1c: 切换读出引擎 (DMA 描述符 / 桥硬件读) —— 切换后 'M'/'A'/'B' 四条
 *       链都在所选引擎上跑 -> "[B2] DMAMODE now=DMA|bridge"
 *   'F' B3-1b v4: DMA 流起点取证 —— 槽基址 SA-64/SA/SA+64 三点各做一笔 MM2S(64B),
 *       回读 dma_sink q1(流首拍 4 字节 LE) -> "[B2] F slot=n q1[-64]=.. q1[0]=.. q1[+64]=.."
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
/* B3-1b: 读引擎选择 (+0x0C 写 engine 位) / DMA 请求 (+0x34 读) */
#define R_ENGINE  (*(volatile unsigned *)(REGS_BASE + 0x0Cu))
#define R_DMAREQ  (*(volatile unsigned *)(REGS_BASE + 0x34u))

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

/* ---- B3-1a: AXI DMA MM2S (Lite @0x44A10000, 直通模式) ---- */
#define DMA_BASE 0x44A10000u
#define DMA_DMACR   (*(volatile unsigned *)(DMA_BASE + 0x00u))
#define DMA_DMASR   (*(volatile unsigned *)(DMA_BASE + 0x04u))
#define DMA_SA      (*(volatile unsigned *)(DMA_BASE + 0x18u))
#define DMA_LENGTH  (*(volatile unsigned *)(DMA_BASE + 0x28u))

static void uputh(unsigned v)          /* 8 位十六进制 */
{
    static const char hx[] = "0123456789abcdef";
    int i;
    for (i = 28; i >= 0; i -= 4)
        uputc(hx[(v >> i) & 0xfu]);
}

/* 坑 #39: 互联 Lite 读首笔可能陈旧 —— 读两次取第二值 */
static unsigned dread(volatile unsigned *r)
{
    (void)*r;
    return *r;
}

/* 坑 #39 读冲刷 + 双读 (2026-10-13 板上升级): interconnect 扩 3 MI 后
 * (NUM_MI 2->3, B3-1a) M01 读滞后从"休眠边界后首笔"恶化为"每笔落后一笔"
 * —— 0x2C 哑写疗法失效 (JTAG 18 笔对照实证: 读 N 返回事务 N-1)。
 * 现行疗法 = 先保留哑写冲刷管线, 再双读取第二笔 (dread 同型, 板上实证
 * JTAG 连续读第二笔恒新鲜; DMA 寄存器读全程正确即因此)。
 * 根治需换互联结构或 ILA 挂 AR/R 总线取证, 与 B3-2 合并排期。 */
static unsigned rd_reg(volatile unsigned *r)
{
    *(volatile unsigned *)(REGS_BASE + 0x2Cu) = 0u;
    busy_ms(1);
    (void)*r;
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

/* GO 等待: 只认类型字符, 其余字符 (串扰/DDR 周期校准窗在 RX 上的幻影字节,
 * 2026-10-12 板上实证: 每次打印突发期间 RX 会进 1 个非命令字节) 打印告警后
 * 继续等 —— 幽灵值恰好等于类型字符的概率极低, 且 PC 侧有整轮重试兜底。 */
static char wait_go(char type)
{
    unsigned ms = 0;
    for (;;) {
        char c, d;
        if (urx_poll()) {
            c = urx_get();
            if (c != type) {                 /* 非类型字符: 幽灵字节, 过滤 */
                uputs("[B2] RXGHOST ");
                uputc("0123456789abcdef"[(c >> 4) & 0xf]);
                uputc("0123456789abcdef"[c & 0xf]);
                uputs("\r\n");
                continue;
            }
            /* 类型字符到达: 等补码字节 */
            {
                unsigned k;
                for (k = 0; k < 30000u; k++) {
                    if (urx_poll()) break;
                    busy_ms(1);
                }
                if (!urx_poll())
                    return 0;
                d = urx_get();
                if ((unsigned char)d == ((~(unsigned char)c) & 0xffu))
                    return c;
                uputs("[B2] RXGHOST ");
                uputc("0123456789abcdef"[(d >> 4) & 0xf]);
                uputc("0123456789abcdef"[d & 0xf]);
                uputs("\r\n");
            }
            continue;
        }
        busy_ms(1);
        if (++ms >= 200000u)             /* 上限, 防永久卡死 */
            return 0;
    }
}

/* ---------------------------------------------------------------------------
 * B3-1c: DMA 读出引擎的「逐笔服务」原语 + 开关
 *
 * 桥 FSM 把每笔读命令转成 {slot,len} 请求 (sticky 位 25); 由软核编程 MM2S:
 *   SA/LEN 必须与位流的 shim DROP_BYTES 配对 (见下 macro), 等 DMASR Idle
 *   且请求电平落零(退休) 再返回。'E' 命令的服务循环与 'N'(RND+DMA) 共用本件。
 * ------------------------------------------------------------------------ */
static unsigned g_dma_service;          /* 1 = 本轮每笔读请求由软核服务 */
static unsigned g_dma_mode;             /* 0 = 桥读引擎服务(现役 v5-RTL 配对);
                                         * 1 = DMA 驻留服务(退役后置 1; 由 'd' 切换/默认值在此) */

static int serve_dma_once(void)
{
    unsigned v_req, slot, len, sa, sr, guard;

    v_req = rd_reg((volatile unsigned *)(REGS_BASE + 0x34u));
    if ((v_req & 0x02000000u) == 0u)
        return 0;                       /* 无待服务请求 */

    slot = (v_req >> 16) & 0xffu;
    len  = v_req & 0xffffu;
    sa   = 0x00100000u + slot * 4096u;

    DMA_DMACR = 0x4u;                   /* reset */
    guard = 0;
    while ((((sr = dread(&DMA_DMASR))) & 0x1u) == 0u)
        if (++guard > 4000000u) break;
    DMA_DMACR = 0x1u;                   /* RS=run */
    guard = 0;
    while ((((sr = dread(&DMA_DMASR))) & 0x1u) != 0u)
        if (++guard > 4000000u) break;

    DMA_SA     = sa;                    /* 配对 A: v5-RTL(DROP_BYTES=0) */
    DMA_LENGTH = len;
    guard = 0;
    do { sr = dread(&DMA_DMASR); }
    while (((sr & 0x2u) == 0u) && (++guard < 80000000u));

    guard = 0;                          /* 等退休(请求电平落零) 再取下一笔 */
    while ((rd_reg((volatile unsigned *)(REGS_BASE + 0x34u)) & 0x02000000u)
           && (++guard < 100000u))
        ;
    return 1;
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
            if (g_dma_service)
                serve_dma_once();        /* ★B3-1c: RND 也走 DMA 描述符 */
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
    (void)rd_reg(&R_WM_WR);
    if (wait_go(type) == 0) {            /* 段1 字符 = 类型字符; 幽灵字节过滤 */
        uputs("[B2] GOWAIT-FAIL t="); uputc(type); uputs("\r\n");
        return;
    }

    if (g_dma_mode) {                    /* ★B3-1c: RND 段起切 DMA 读引擎 */
        R_ENGINE      = 1u;
        g_dma_service = 1u;
        uputs("[B2] DMAMODE engine=DMA (RND via descriptors)\r\n");
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

    if (g_dma_mode) {                    /* ★B3-1c: 轮末切回桥引擎 (保持口径可比) */
        g_dma_service = 0u;
        R_ENGINE      = 0u;
        uputs("[B2] DMAMODE engine=bridge\r\n");
    }
    /* 不在此恢复 SEQ: 恢复写会使 u_wr_frame +1 污染轮后 'I' 对账; 且下一轮
     * 段0 本就先切 SEQ (预热窗需要)。脚本收尾显式发 'S' 恢复。 */
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

    uputs("[B2-SOFT] WAITCMD (M/A/B/S/I/L/D/E)\r\n");
    for (;;) {
        char c, d;
        while (!urx_poll()) { }
        c = urx_get();
        /* 串扰/延迟回声会在 RX FIFO 里进单字节幻影 (板上实证)。
         * 策略: 单字节命令 (S/I) 在「命令间」直接执行; 轮命令 M/A/B 要求
         * 紧跟补码字节 (~c) —— 幻影字节凑不齐补码对, 不会误触发整轮。 */
        if (c == 'M' || c == 'A' || c == 'B') {
            unsigned k;
            for (k = 0; k < 30000u; k++) {          /* 等补码字节, ~秒级 */
                if (urx_poll()) break;
                busy_ms(1);
            }
            if (!urx_poll()) {
                uputs("[B2] NOPAIR "); uputc(c); uputs("\r\n");
                continue;
            }
            d = urx_get();
            if ((unsigned char)d != ((~(unsigned char)c) & 0xffu)) {
                uputs("[B2] BADPAIR "); uputc(c); uputs("\r\n");
                continue;
            }
            round_command(c);                       /* 引擎由 g_dma_mode 决定 */
        }
        else if (c == 'd') {
            /* ★B3-1c: 切换读出引擎 (DMA 描述符 / 桥硬件读) —— 之后 'M'/'A'/'B'
             * 四条链都在所选引擎上跑, 供同一判据脚本复跑 (J3/J3′ + 负向 A/B)。 */
            g_dma_mode = !g_dma_mode;
            uputs("[B2] DMAMODE now=");
            uputs(g_dma_mode ? "DMA\r\n" : "bridge\r\n");
        }
        else if (c == 'S') {
            R_MODE = MODE_SEQ;
            uputs("[B2] SEQRESTORED (cmd S)\r\n");
        } else if (c == 'L') {
            /* B3-0 Lite 路: 回读 MIG 读写延迟观测寄存器 (先读后打, 坑 #44) */
            unsigned v_lw, v_lr;
            v_lw = rd_reg((volatile unsigned *)(REGS_BASE + 0x20u)) & 0xffffu;
            v_lr = rd_reg((volatile unsigned *)(REGS_BASE + 0x24u)) & 0xffffu;
            uputs("[B2] LAT w="); uputd(v_lw);
            uputs(" r=");        uputd(v_lr);
            uputs("\r\n");
        } else if (c == 'E') {
            /* B3-1b: DMA read-engine round - the soft core drives MM2S per
             * frame; the stream goes through dma_rd_shim (which drops the
             * provenance 50-byte prefix, board-measured) back into
             * frame_mem_if's read path. engine=1 -> RND -> serve {slot,len}
             * requests read from +0x34 -> SA = slot base (ALIGNED read),
             * LEN = len+50 -> wait DMASR idle -> close out -> engine=0. */
            unsigned rd0, rd, v_req, slot, len, sa, sr, guard;
            unsigned served = 0, stall = 0;

            R_ENGINE = 1u;                          /* read engine = DMA */
            R_MODE   = MODE_SEQ;                    /* SEQ: 顶层自动触发喂请求
                                                      * (RND 下无人发读命令, 服务
                                                      *  循环会等不到 sticky) */
            {   /* 置位确认门: 镜像 bit24 回读到 1 再继续 (关"引擎晚到"窗口) */
                unsigned k;
                for (k = 0; k < 3000u; k++) {
                    if (rd_reg((volatile unsigned *)(REGS_BASE + 0x34u)) & 0x01000000u)
                        break;
                    busy_ms(1);
                }
            }
            uputs("[B2] E-START (engine=DMA)\r\n");

            rd0 = rd_reg(&R_WM_RD);
            for (guard = 0; guard < 8000u; guard++) {
                rd = rd_reg(&R_WM_WR);
                if (d16(rd, 0) >= 1u) break;        /* wait first frame in */
                busy_ms(1);
            }
            {
                unsigned wr_last = 0, same = 0;
                for (;;) {
                    v_req = rd_reg((volatile unsigned *)(REGS_BASE + 0x34u));
                    if (v_req & 0x02000000u) {      /* sticky=bit25 ({1,1,slot[8],len[16]} 共 26 位拼接) */
                        slot = (v_req >> 16) & 0xffu;
                        len  = v_req & 0xffffu;
                        sa = 0x00100000u + slot * 4096u;
                        DMA_DMACR = 0x4u;           /* reset */
                        guard = 0;
                        while ((((sr = dread(&DMA_DMASR))) & 0x1u) == 0u)
                            if (++guard > 4000000u) break;
                        DMA_DMACR = 0x1u;           /* RS=run */
                        guard = 0;
                        while ((((sr = dread(&DMA_DMASR))) & 0x1u) != 0u)
                            if (++guard > 4000000u) break;
                        /* DMA 基址/长度口径 —— 必须与位流的 shim DROP_BYTES 配对:
                         *   · DROP_BYTES=8 位流(v3 a432addd / rdprobe 442ca75a):
                         *       SA = 槽基址-8, LEN = len+8;
                         *     前移 8B 让"被丢的 8B"落在前导之前 ⇒ 发射流 =
                         *     【8B 以太网前导+SFD】+ 完整帧(含 FCS), 与桥硬件引擎逐字节同构。
                         *   · DROP_BYTES=0 位流(v5 DROP=0): SA = 槽基址, LEN = len。
                         * 板上实证(2026-10-16 ILA 发射字节流比对): 槽存 =
                         *   【8B 前导+SFD (55×7,D5)】+【完整 ETH/IP/UDP 帧(含壳 4B FCS)】, 全长 = len;
                         * 旧口径(SA=基址, LEN=len+8, 配 DROP=8)把前导丢掉 ⇒ 上线无前导 ⇒
                         * 接收侧 MAC 无法定界 ⇒ 网卡静默丢弃(0 回显的真根因)。 */
                        DMA_SA     = sa;            /* 当前生效 = v5-RTL 配对(DROP_BYTES=0 位流) */
                        DMA_LENGTH = len;
                        guard = 0;
                        do { sr = dread(&DMA_DMASR); }
                        while (((sr & 0x2u) == 0u) && (++guard < 80000000u));
                        /* 等请求电平落零 (退休已发生) 再取下一笔, 防重服务 */
                        guard = 0;
                        while ((rd_reg((volatile unsigned *)(REGS_BASE + 0x34u))
                                & 0x02000000u) && (++guard < 100000u))
                            ;
                        served++;
                    } else {
                        busy_ms(1);
                    }
                    rd = rd_reg(&R_WM_RD);
                    {
                        unsigned wr = rd_reg(&R_WM_WR);
                        if (wr == wr_last) same++; else same = 0;
                        wr_last = wr;
                        if ((same >= 600u) && (d16(rd, rd0) == d16(wr, rd0))
                            && (served > 0u))
                            break;                  /* drained & stable & >=1 served:
                                                     * 板上实证(10-14): 无此门则循环
                                                     * 在 PC 首帧到达前(~50ms)即收口,
                                                     * engine 被切回 0, 帧走桥引擎 */
                        if (same >= 4000u) {        /* ~4s no request: stall */
                            stall = 1;
                            break;
                        }
                    }
                }
            }
            R_ENGINE = 0u;                          /* read engine = bridge */
            R_MODE   = MODE_SEQ;
            rd = rd_reg(&R_WM_RD);
            /* 取证: 最近一笔 DMA 线上 AR 地址 (定位 -50 侧别; 与 SA 对照) */
            uputs("[B2] E-ARL arl="); uputh(rd_reg((volatile unsigned *)(REGS_BASE + 0x38u)));
            uputs("[B2] E-EMIT emit="); uputh(rd_reg((volatile unsigned *)(REGS_BASE + 0x3Cu)));
            uputs("\r\n");
            uputs("[B2] E-DONE served="); uputd(served);
            uputs(" rd+");      uputd(d16(rd, rd0));
            uputs(" stall=");   uputd(stall);
            uputs("\r\n");
        } else if (c == 'D') {
            /* B3-1a DMA 冒烟: MM2S 读"最后一帧所在槽"(SA+0x40 预补偿) -> dma_sink 回读
             * 板上实证 (2026-10-13, 两次独立帧预测命中): axi_dma 512b MM2S 读地址 X
             * 返回 MIG 块 (X-64) 的内容 —— IP 内部数据通道装配偏移, 非地址错。
             * 故 SA = 槽基址 + 0x40 时流 = 槽基址块的内容; sink q1 = 块内字节
             * 14..17 的 LE 值 (PC 离线可算, dma_smoke.py 判据同步)。 */
            unsigned wm, sa, sr, guard;
            unsigned v_q0, v_q1, v_q2;
            wm = rd_reg(&R_WM_WR) & 0xffffu;               /* 最后帧槽 = (wm-1)%256 */
            sa = 0x00100000u + ((wm - 1u) & 0xffu) * 4096u + 0x40u;
            DMA_DMACR = 0x4u;                              /* 复位 */
            guard = 0;
            while ((((sr = dread(&DMA_DMASR))) & 0x1u) == 0u)
                if (++guard > 4000000u) break;
            DMA_DMACR = 0x1u;                              /* RS=运行 */
            guard = 0;
            while ((((sr = dread(&DMA_DMASR))) & 0x1u) != 0u)
                if (++guard > 4000000u) break;
            DMA_SA     = sa;
            DMA_LENGTH = 64u;                              /* 写长度即启动 */
            guard = 0;
            do { sr = dread(&DMA_DMASR); }                 /* 等 Idle=1 */
            while (((sr & 0x2u) == 0u) && (++guard < 80000000u));
            busy_ms(2);                                    /* sink 镜像稳定 */
            v_q0 = rd_reg((volatile unsigned *)(REGS_BASE + 0x28u));
            v_q1 = rd_reg((volatile unsigned *)(REGS_BASE + 0x2Cu));
            v_q2 = rd_reg((volatile unsigned *)(REGS_BASE + 0x30u));
            uputs("[B2] DMA sa=");  uputh(sa);
            uputs(" sr=");         uputh(sr & 0xffffu);
            uputs(" q0=");         uputh(v_q0);
            uputs(" q1=");         uputh(v_q1);
            uputs(" q2=");         uputh(v_q2);
            uputs("\r\n");
        } else if (c == 'F') {
            /* B3-1b v4 取证 (2026-10-16): 直接量「DMA 流起点相对槽基址的字节偏移」。
             * 现模型「流 = mem[SA-8..], shim 丢 8」只是推断, 从未在 base=SA 逐字节量过。
             * 做法: 以对齐槽基址 SA 为中心取三个 64B 对齐点各做一笔 MM2S(64B=1 拍),
             * 回读 dma_sink q1 = 该笔「流首拍低 32 bit」(= 流起点 4 字节, 小端)。
             * PC 侧用已知帧字节反解流起点 ⇒ (-8 / -50 / -64) 三说一次定案。
             * 纪律: 先读全部寄存器, 再纯打印 (坑 #44: 打印中穿插 AXI 读会毁 TX 行)。 */
            unsigned wm, base, sr, guard;
            unsigned q1b, q1m, q1p;
            unsigned k;
            wm = rd_reg(&R_WM_WR) & 0xffffu;
            base = 0x00100000u + ((wm - 1u) & 0xffu) * 4096u;
            for (k = 0u; k < 3u; k++) {
                unsigned a = (k == 0u) ? (base - 0x40u)
                                        : ((k == 1u) ? base : (base + 0x40u));
                DMA_DMACR = 0x4u;                          /* 复位 */
                guard = 0;
                while ((((sr = dread(&DMA_DMASR))) & 0x1u) == 0u)
                    if (++guard > 4000000u) break;
                DMA_DMACR = 0x1u;                          /* RS=运行 */
                guard = 0;
                while ((((sr = dread(&DMA_DMASR))) & 0x1u) != 0u)
                    if (++guard > 4000000u) break;
                DMA_SA     = a;
                DMA_LENGTH = 64u;                          /* 写长度即启动 */
                guard = 0;
                do { sr = dread(&DMA_DMASR); }
                while (((sr & 0x2u) == 0u) && (++guard < 80000000u));
                busy_ms(2);                                /* sink 镜像稳定 */
                if (k == 0u)      q1b = rd_reg((volatile unsigned *)(REGS_BASE + 0x2Cu));
                else if (k == 1u) q1m = rd_reg((volatile unsigned *)(REGS_BASE + 0x2Cu));
                else              q1p = rd_reg((volatile unsigned *)(REGS_BASE + 0x2Cu));
            }
            uputs("[B2] F slot=");   uputd((wm - 1u) & 0xffu);
            uputs(" q1[-64]=");      uputh(q1b);
            uputs(" q1[0]=");        uputh(q1m);
            uputs(" q1[+64]=");      uputh(q1p);
            uputs("\r\n");
        } else if (c == 'I') {
            /* 板上实证 (2026-10-12): 打印中途穿插 AXI 读 (rd_reg) 会使 TX 行
             * 中后段字节损坏 (PDRC-203 引脚组; READY/DONE 等纯打印行完好,
             * 唯 I 行必挂) —— 故先读完 4 个寄存器, 再一次性纯打印。 */
            unsigned v_id, v_wr, v_rd, v_dr;
            v_id = rd_reg(&R_ID)    & 0xffffu;
            v_wr = rd_reg(&R_WM_WR) & 0xffffu;
            v_rd = rd_reg(&R_WM_RD) & 0xffffu;
            v_dr = rd_reg(&R_WM_DRP) & 0xffffu;
            uputs("[B2] ID="); uputd(v_id);
            uputs(" wr=");     uputd(v_wr);
            uputs(" rd=");     uputd(v_rd);
            uputs(" drop=");   uputd(v_dr);
            uputs("\r\n");
        }
        /* 其余字符 (\r\n 等) 忽略 */
    }
}
