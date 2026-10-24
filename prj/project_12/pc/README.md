# prj12 · PC 侧脚本（P1 双板链路/数据面可见性）

> 板卡不在场时，三个脚本都可以 **dry-run**：`twin_send.py --dry-run`、`twin_recv.py --from-pcap <现成 pcap>`、`static_arp.ps1 -DryRun`。
> 现场判据见 `../out/twin_link_test.ps1` 的 STEP 3/4（以及草案 §4.2 P1-02/P1-03）。

## 0. 先钉死两件事

| 项 | 板 A/PC1 | 板 B/PC2 |
|---|---|---|
| 板卡 IP / MAC | `192.168.1.10` / `00:11:22:33:44:55` | 同（P1 两板同一位流，各自独立 L2） |
| PC IP | `192.168.1.102/24` | `192.168.1.102/24`（两 PC 直连各自板卡，不共交换域） |

P1 的预期现象（**不是故障**）：PC1 发的 UDP 被板 A 回显，回显帧经光纤到板 B、从板 B 的 GE1 出去；
所以 **PC2 的网口能看到目的 = PC1 的帧**，而 PC1 收不到回包。`eth.dst != PC2 的 MAC` 是预期。

## 1. 静态 ARP（可选但推荐）

```powershell
# 只演练：
powershell -NoProfile -ExecutionPolicy Bypass -File static_arp.ps1 -DryRun
# 真绑（管理员）：
powershell -NoProfile -ExecutionPolicy Bypass -File static_arp.ps1 -Apply -InterfaceAlias "Ethernet"
# 解除：
powershell -NoProfile -ExecutionPolicy Bypass -File static_arp.ps1 -Apply -Remove -InterfaceAlias "Ethernet"
```

## 2. PC1 发送

```powershell
py twin_send.py --dst-ip 192.168.1.10 --dst-port 1234 --count 20 --len 100
py twin_send.py --dry-run          # 只看计划与前 3 帧 payload
```

payload 自带结构：`"TWIN"|seq(2)|count(2)|run_id(4)|fill(...)`，PC2 侧逐字节校验。

## 3. PC2 抓包 + 判据

```powershell
# 现场抓（dumpcap 来自 Wireshark；filter 只收板卡发出的帧）
dumpcap -D                                   # 查网卡编号
dumpcap -i 3 -f "ether src 00:11:22:33:44:55" -a duration:30 -w pc2.pcap
# 解析
py twin_recv.py --from-pcap pc2.pcap --board-mac 00:11:22:33:44:55 --port 1234 --expect-count 20
# 或者一条命令（内部调 dumpcap）：
py twin_recv.py --live --iface "Ethernet" --seconds 30 --out pc2.pcap --expect-count 20
```

判据（PASS 条件）：`matched > 0`、`fill` 全 ok、`expect-count` 满足；输出会打印每帧 `seq/total/run_id`。
如果 `matched=0`：先看 `other` 计数——`other` 也不动 ⇒ 网卡/混杂模式/filter 问题；`other>0` 但 matched=0 ⇒ MAC 或端口判据不对。

## 4. 反向（P1-04）

把两端的角色对调：PC2 发（`twin_send.py` 在 PC2 上跑）、PC1 抓（`twin_recv.py` 在 PC1 上跑）。
payload 的 `--run-id` 换一个值，便于区分方向。
