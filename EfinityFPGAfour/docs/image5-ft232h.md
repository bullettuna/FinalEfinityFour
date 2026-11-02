# image5：FT232H 异步 FIFO、三档图像与 1bpp 边缘

2026-10-26：已接入独立 GPIO 按键和 MCP3202 CH0/CH1 采集，旋钮不修改图像阈值。
`!A` 单次查询 ADC，按键单次上报，OLED/SD 仍关闭。操作见 [image5 外设](image5-inputs.md)。

2026-10-24 按 `image5_FT232H异步FIFO交接包_20261024.zip` 改为 **FT245 异步 FIFO**。
目标工程 `images/image5_canny/Ti60_Image5_Canny.xml`。此说明替代 2026-10-21 的同步 FIFO 说明。
本版不依赖 U2、AC5/CLKOUT 或 FT 专用 PLL；禁止用旧同步 bit 和旧 PC 的 0x40 配置混合测试。

## 画面选择

HDMI 仍为 1920×1080，原中值去噪、Canny、碎点清理和串口阈值/冻结控制保留。
下面的尺寸选择控制 **USB 实际传输的完整图像尺寸**，不是把小图在电脑上放大。
灰度继续为 8bpp；!3 默认将二值边缘按 MSB-first 打包为 1bpp，!7 保留原有 8bpp 边缘对照。

- `!4` → `4`：320×180，默认；灰度取每个 6×6 区块的中心，边缘做 6×6 OR 保留细线。
- `!5` → `5`：640×360；灰度取每个 3×3 区块的中心，边缘做 3×3 OR。
- `!6` → `6`：1920×1080；发送原尺寸灰度或原尺寸二值 Canny。
- `!R` → `4/5/6`：查询当前尺寸。

每幅图来自同一帧，存入独占 DDR 区域 `0x01800000..0x019FA3FF`。
发送完前不覆盖；USB 停顿时跳过后续摄像头帧。没有多帧条带拼接，不暂停 HDMI。
片内只保留 16KiB 捕获 FIFO、行池化存储和短读缓存，不新增第二个完整帧缓存。
AXI 复用现有带事务归属和视频紧急优先的仲裁器；每次读取八个 128 位 beat，读完即释放 DDR，再慢速向 USB 序列化。

发送器以 96MHz 系统时钟工作，数据建立、WR 低电平、WR 拉高后保持、恢复各 10 周期，WR 下降沿间隔至少 96 个周期。
约 1MB/s 是设计限速，不是已经测得的吞吐量。灰度/8bpp 边缘的载荷发送时间分别约 0.058、0.230、2.074 秒；
1bpp 边缘的载荷分别为 7,200、28,800、259,200 字节，对应约 0.0072、0.0288、0.2592 秒；
实际还包含采集、CRC 包头、调度与 USB 等待。1920 档是低帧率快照，不能承诺实时视频。

## 串口命令

原 FPGA 控制串口：115200、8N1；以下 `!` 命令不需要回车，可以一起发两个 ASCII 字符，也可以依次发送。
每条命令收到回复后再发下一条。

- `V` → `5`：image5。
- `!V` → `A`：异步固件标识。旧同步固件回复 F，应更换 bit。
- `!?` → `A` 或 `N`：内部异步逻辑就绪；**不是 USB 已连接或 EEPROM 正确的证明**。
- `!0` → `0`：停止。仅在写脉冲、数据保持和在途 DDR 事务收尾并释放总线后回复。
- `!1` → `1`：连续计数测试包，载荷 4096 字节，00～FF 重复 16 次。
- `!2` → `2`：连续灰度快照。
- `!3` → `3`：连续 **1bpp** 二值边缘快照，8 像素/字节，bit7 为最左侧像素。
- `!7` → `7`：连续原有 **8bpp** 二值边缘快照，每像素一个 0/255 字节。
- `!P` → `1`：查询支持 1bpp 的新固件能力；旧异步版仍回复 !，不能用它运行新边缘命令。
- `!S` → `0/1/2/3`：查询当前请求模式；两种边缘格式都属于模式 3。
- `!4/!5/!6`：选择尺寸，见上。

尺寸或模式改变会先安全停止旧会话，再应用新配置并重启序号；忙于收尾时收到额外配置命令回复 B。
为了让 PC 的序号检查清楚，建议 `!0` 后重新启动接收程序，再选尺寸和图像模式。
原 C/G/E/T/M/D/H/L/R/F/Z 命令继续控制 HDMI/Canny；原 H/L 数值命令仍需回车。
USB 灰度/边缘选择独立于 HDMI C/G/E。ADC 采集和按键已开启，旋钮不调图像阈值；OLED、SD 保持关闭。

## 接线与 EEPROM

交接包中的最终 P3/P4 映射保留；硬件清单 `images/image5_canny/ft232h-hardware.json` 将 AC5 标记为 inactive。
活动 FT 总线为 3.3V：
D0..7=A4/A3/C4/B5/B14/A14/D12/A12，WR#=C3，TXE#=A13，公共地。
P4 原 SPI/SD/KEY 位置仍为 1.8V，不恢复旧 P3 位置。
B8/P3-7 不再生成 GPIO 时钟接口，不把它改成输出。无需焊接 U2，不短接缓冲或分压。
RD#/SIWU# 等上拉及 22Ω 串阻装配按交接包核对，保证 FT 不驱动 AD。

先只连接 FT232H 的 USB、暂不连接 26P，使用 FT_PROG 读取并完整备份目标模块 EEPROM。
确认/设置为 **FT245 FIFO**，断电重枚举后读回核对，保持原 VID/PID/序列号。此操作没有由本次代码自动执行。
下载本次异步 checked.bit、确认电源和排线方向后连接 26P。默认停止，AD 高阻，WR 不写。
模块未供电时不要启动发送；未布置 USB_PRESENT，固件不能自动证明 USB 连接或识别所有拔线故障。
停止和断开前先 `!0` 并等 `0`。

## PC 接收：先计数，再图像

以下命令在仓库根目录运行。用 `--list` 找到 **type=8 的 FT232H serial**，不能填 CH340 COM 号或默认打开第 0 个下载器。
驱动使用官方 D2XX/CDM。默认只需 Python 标准库；预览需要 tkinter；`--uart` 还需要 pyserial。

```powershell
python tools/ft232h_receive.py --list
python -m pip install pyserial
python tools/ft232h_receive.py --transport async --serial 实际FT序列号 --uart 实际FPGA串口 --fifo-eeprom-confirmed --mode counter --seconds 60
```

`--fifo-eeprom-confirmed` 表示已经按上节读回确认 EEPROM，不代表程序代你配置过 EEPROM。
自动流程：`!V=A` → 边缘模式确认 `!P=1` → `!0=0` → 按 serial 打开 D2XX → `FT_SetBitMode(0,0x00)` → USB 65536、超时 100ms、延迟 2ms、清旧数据 → `!?=A` → 选尺寸 → 启动。
0x00 恢复 EEPROM 选择的异步 FIFO；它不能把 UART EEPROM 改成 FIFO。程序不使用 0x40、bit-bang、MPSSE 或 FT_Write。

计数测试必须 frames>0，头 CRC、载荷 CRC 和序号断续为 0。通过后分别运行：

```powershell
python tools/ft232h_receive.py --transport async --serial 实际FT序列号 --uart 实际FPGA串口 --fifo-eeprom-confirmed --mode gray --width 320 --seconds 60 --preview --save-last gray.pgm
python tools/ft232h_receive.py --transport async --serial 实际FT序列号 --uart 实际FPGA串口 --fifo-eeprom-confirmed --mode edge --width 640 --seconds 60 --preview --save-last edge640.pgm
python tools/ft232h_receive.py --transport async --serial 实际FT序列号 --uart 实际FPGA串口 --fifo-eeprom-confirmed --mode edge --width 1920 --seconds 60 --preview --save-last edge1920.pgm
```

`--edge-format packed` 是边缘默认值，自动发 !3；`--edge-format byte` 自动发 !7。
例如在上面的 edge 命令增加 `--edge-format byte`，即可对比旧的 8bpp 载荷。
预览会把大画面缩放到桌面可查看大小；保存的 PGM 保持完整所选尺寸。
1bpp 在电脑端无损解包为 0/255 后显示和保存 PGM，因此 PGM 仍是每像素 8 位，不代表 USB 没有压缩。无需安装 numpy/pillow。
USB 读线程与 GUI 分开；按实际读回的 4096 字节以下片段解析，不假设一次 FT_Read 是一帧。
只显示通过双 CRC 校验的完整图像，输出有效帧数、fps 和有效载荷 MB/s。初次手动等待也计入统计，不能把这些数值当峰值吞吐量。

不使用 `--uart` 时，先在原串口发 `!V` 确认 A，边缘模式再发 `!P` 确认 1，然后发 `!0` 等 0；运行时添加 `--stopped-confirmed`。
脚本显示 D2XX async ready 后，在串口依次发 `!?`、尺寸命令、`!1/!2/!3/!7`。
此时 `--width`/`--mode` 是接收校验选择，实际 FPGA 由手工命令设置。退出前手动 `!0`，确认停止后再断开。

## 数据、时序与验证边界

保留 FT5! v1：24 字节小端头 `<4sBBBBIHHII`，带类型、序号、宽高、载荷长度与前 20 字节 CRC32；
随后是载荷和 4 字节载荷 CRC32。CRC 与 Python zlib 一致。灰度/旧边缘三档载荷为 57600、230400、2073600 字节；
新增 type=3 的 1bpp 边缘三档为 7200、28800、259200 字节。type=0/1/2 原义不变，flags=0、version=1。
帧头布局、CRC 范围与位序详见 [FT5! 协议](image5-ft5-protocol.md)。
当前在 DDR 读出后打包，仍保存一帧 8bpp 快照；MSB-first 打包和解包不改变原二值像素。
每个上游 valid/ready 握手仅将一字节转交给私有 pending 寄存器；WR 下降沿写一次，随后 TXE 变高不会触发重发。
TXE 经 RTL 两级同步和连续四拍低电平资格判断；停止可以放弃尚未写入的 pending 字节，但不会截断已开始的 WR 脉冲。
重新开始按新包头/CRC 同步，硬复位中途的半包不能当有效帧。

AD/WR 的 IO 输出寄存器使用 clk_sys；保留原摄像头 6ns、像素、DDR 时序约束。
只有 raw TXE 到第一级 txe_meta 的 D 端设置异步例外，第二级和状态机仍检查时序。
实际 IO 时钟网络与 Tco 报告用于异步引脚建立/低脉宽/保持预算；走线 0..5ns 和抖动 1ns 是待实测假设。
仿真和数字时序通过不能代替示波器及 USB 实收测试。

```powershell
& tools/test-ft232h.ps1 -FullSize
& tools/test-image5.ps1 -FullSize
& tools/build-image.ps1 -Image 5
```

异步 PHY 测试按带寄存器及不同延迟的实际 pad WR 下降沿收字节，覆盖 TXE 1/14ns 延迟、49ns 恢复、背压和各阶段停止。
小尺寸链路通过真实发送器逐字节测试三个缩放比例和双 CRC；完整 1080p 输入的 DDR/分包测试加速包字节握手，
独立验证三档灰度、1bpp 边缘和 8bpp 边缘的像素、宽高、CRC 和帧所有权，不将加速仿真速度当作物理 USB 速度。
原 Canny 另跑连续四帧 1080p 回归。最终资源/时序/文件哈希以构建产物和下载清单为准。

本轮开始时工作区为较早 main，缺少 image5 源码；已从本地 `acc4f2b` 恢复 image5，
并将所需 UART/禁用视觉分支兼容实现留在 image5 私有目录，避免替换 image1～image4 的共享实现。
修改前本地标签 `codex/backup-before-image5-async-20261024`；旧同步源及 bit/hex 归档到
`E:/Efinity_Project/bit_hex_archive/Image5_sync_before_async_20261024.zip`。
没有写 EEPROM、下载板卡、烧写 Flash 或推送 GitHub；真实异步收数、画面和帧率仍待硬件验证。

## 8bpp 异步基线历史构建结果（打包前）

- JTAG：`images/image5_canny/outflow/Ti60_Image5_Canny_checked.bit`
- HEX：`images/image5_canny/outflow/Ti60_Image5_Canny.hex`
- 工程：`images/image5_canny/Ti60_Image5_Canny.xml`
- 版本查询：V → 5，!V → A；不使用 AC5/U2/FT PLL。
- USB 可选 320×180 / 640×360 / 1920×1080，灰度或二值 Canny；HDMI 保持 1080p。
- 16,498/60,800 XLR、104/256 RAM10、11/160 DSP；28 项建立/保持检查全部通过。
- 像素 setup/hold +1.401/+0.026 ns，系统 +3.232/+0.022 ns，全局最小 +0.019 ns。
- 条件异步 pad 最小建立/低脉宽/保持各约 95.190 ns；走线/抖动边界尚未实测。
- checked.bit SHA256：`F57B60CB3A00B0C60549F5E3A8DB1DEEF46416006E4DAAFF14D24F9B80B90749`
- hex SHA256：`DCD8D2114E1A344691E4E66D67BC38067F52B6A17D0E1D59B6D341E878F0D3FF`
- 16:22 编译产物，未下载板卡、未写 Flash/EEPROM，真实 USB 通信和帧率待测。
- 串口、EEPROM 和 PC 接收命令见 上文。旧同步文件已在工程外归档，不能混用旧 PC 0x40 配置。


验证日志位于 `work_sim/ft_async_20261024/build_final.log`、`full_test.log`、`canny.log`；异常收尾补测为 `work_sim/ft_async_abort/run.log`。

2026-10-24 打包前源码标签：`codex/backup-before-image5-1bpp-20261024`（39d33a1）。旧 bit/hex、通信源和接收工具归档：`E:/Efinity_Project/bit_hex_archive/Image5_async_8bpp_before_packing_20261024.zip`。

## 当前 1bpp 编译结果

- JTAG：`images/image5_canny/outflow/Ti60_Image5_Canny_checked.bit`
- HEX：`images/image5_canny/outflow/Ti60_Image5_Canny.hex`
- 工程：`images/image5_canny/Ti60_Image5_Canny.xml`
- 查询：V → 5，!V → A，**!P → 1**；不使用 AC5/U2/FT PLL。
- !3 默认发送 MSB-first 1bpp 边缘（type=3）；!7 为原有 8bpp 边缘（type=2），!2 为 8bpp 灰度（type=1）。
- !4/!5/!6 选择 320×180 / 640×360 / 1920×1080；HDMI 仍为 1080p。
- 1bpp 三档载荷分别为 7200 / 28800 / 259200 字节，FT5! v1 的 24 字节帧头与双 CRC 保留。
- 16,777/60,800 XLR、104/256 RAM10、11/160 DSP；28 项建立/保持时序通过。
- 像素 setup/hold +1.449/+0.026 ns，系统 +3.396/+0.019 ns，全局最小 +0.019 ns。
- checked.bit SHA256：`6AE3F6F69C0AD73FF3E26B91643CCA772B7F802EBD59D3F0720C2A683EBCA6FA`
- hex SHA256：`43E81B9BB3AAAE105B68B96A3450E7ED033BD4303E3B685FB9325871BD869EDE`
- 构建时间：2026-10-24T17:01:03；未下载板卡、未写 Flash/EEPROM，真实 USB 通信和帧率待测。
- 必须使用配套更新的接收器；默认 --edge-format packed，--edge-format byte 用于 !7 对照。
- 运行命令见 [image5 异步说明](image5-ft232h.md)，字段定义见 [FT5! 协议](image5-ft5-protocol.md)。
- 旧 8bpp 异步版已归档到 `E:/Efinity_Project/bit_hex_archive/Image5_async_8bpp_before_packing_20261024.zip`。

验证日志：`work_sim/ft_1bpp_20261024/test.log`、`canny.log`、`build.log`。

本次已通过：独立位序/等待/背压/末字节单元测试；小尺寸真实 WR 下降沿收数；完整 1080p 输入生成三档灰度、1bpp、8bpp 边缘的像素与双 CRC 校验；AW/W/B 中途停止、写错误/溢出丢帧及恢复；原 Canny 四帧 1080p 回归。
实际 RTL 640/1920 的 1bpp 流经配套 PC 程序保存 PGM 后也逐像素通过参考比对。上述均为本地仿真/离线验证，不是实板 USB 帧率测量。
