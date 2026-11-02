# image5：独立按键、MCP3202 旋钮与分压按键

2026-10-26，按用户选择接入采集和按键，**CH0 不控制 Canny 阈值**。
OLED 和 SD 不启用。FT232H 仍为已实板验证过的异步 FIFO 架构，
支持 320×180、640×360、1920×1080 和默认 1bpp 边缘打包。
本次新增外设版本的实际板上结果须重新验收；旧版 USB 成功不等于 ADC 已经实测。

## 接线依据

采用 `FT232H_硬件接入交接包_20261021.zip` 的最终扩展板引脚表，
并保留 `image5_FT232H异步FIFO交接包_20261024.zip` 的异步 FT 接线。
另已逐页核对 `E:/unfloding/SCH_Schematic1_2026-10-24.pdf`（扩展板）及
`E:/unfloding/SCH_Schematic1_2026-10-24 (1).pdf`（FT 转接板）。
这两份 10 月 24 日导出的图签均为 10 月 18 日更新，与交接包的最终引脚一致。
P4 外设侧 3.3V，经板上电平转换接 FPGA 侧 1.8V；不能恢复旧 P3 的 SPI 引脚。

- 独立 KEY/SW1：P4-37，A2，低电平按下。
- ADC SCLK：P4-13，G4。
- ADC DIN / SPI MOSI：P4-14，G3。
- ADC DOUT / SPI MISO：P4-17，G2。
- ADC CS#：P4-18，H2。
- OLED CS#：P4-19，F5，保持高电平不选中；DC=P4-20/G5，保持低。
- SD 不初始化、不读写；CLK 保持低，CMD/DAT 输出使能关闭。

MCP3202 的 CH0 为旋钮，CH1 为 SW2/SW3 分压键。
最新扩展板图为 R15=10k 上拉，SW2 下拉 R26=10k，SW3 下拉 R27=3.3k；
独立键 SW1 由 R16=10k 上拉。此前局部截图中的电阻位号不同，阻值和接法一致。
ADC VDD/VREF 与分压 VCC 相同时，12 位理论码值：
释放 4095、SW2 2048、SW3 1016、同时按下约 814；最终以 !A 实测为准。

## 采集、滤波与按键消息

- SPI Mode 0，500kHz，每次 24 个时钟，CH0/CH1 各每秒 1000 次。
- CH0 使用八点移动平均，收满八点后 ready=1。
- CH1 使用三点中值滤波，连续 20 个有效样本稳定后确认状态。
- 独立 GPIO 按键使用两级同步和约 20ms 按下/释放消抖。
- 长按不连发。分压键须稳定松开后才能再次触发；按住过程中换为组合键不重复触发。
- 采集本身无周期性串口输出，也不改变 Canny 的高低阈值。

115200/8N1，ASCII 接收，每次按下输出一行（两个空格，CRLF 结尾）：

```text
key  1
key  2
key  3
key  2+3
```

分别对应独立键、SW2、SW3、两个分压键同时按下。
各消息整行仲裁，命令回复不会插入半行按键或 ADC 查询结果。

## !A：单次 ADC 快照查询

串口发送两个 ASCII 字符 `!A`，不用回车，例如收到：

```text
adc0=0x800 adc1=0xFFF knob=0x800 key=0xFFF ready=1
```

数值均为三位十六进制，0x000～0xFFF 对应十进制 0～4095。
adc0/adc1 是最近一次原始采样；knob 是 CH0 八点均值；key 是 CH1 中值结果。
ready=0 表示旋钮滤波尚未收满八点，ready=1 才可用于稳定数值检查。
这是寄存器快照，不是与查询时刻同时启动的两路转换。
一条结果在排队时冻结所有字段，发送途中旋钮变化不会把一行拼成不同采样的数值。
最多保留一条发送中、一条等待中的查询；继续过快查询会回复 B，等待后重试。
FT 启停/重配置尚未完成时 !A 也会回复 B。

`!A` 属于 FPGA 原有 UART，**不是 FT232H 收图命令**。
两台电脑分别连接 UART/FT232H 时，在 UART 电脑查看按键和查询结果，
FT232H 电脑仍运行 `tools/ft232h_receive.py` 看图。

## 上板验收

1. 下载本次新生成的 image5；原异步固件的 `!A` 不支持本查询。
2. `V` → 5、`!V` → A、`!P` → 1，确认图像固件和打包能力。
3. 保持旋钮不动，上电图像阈值仍为高 60 / 低 30；原 H/L/+/-/R 命令仍有效。
4. 发送 !A，转动旋钮后再发 !A，检查 adc0/knob 改变、Canny 阈值不被旋钮改写。
5. 不按键时 adc1/key 应接近 0xFFF；分别按 SW2/SW3 检查约 0x800/0x3F8，组合约 0x32E。
6. 检查独立键及分压键的单次消息；长按无重复，松开后再次按下有新消息。
7. 按原步骤测试 640/1920 FT 边缘图，在串口按键/查询期间画面仍更新。

`!0` 仍只停止 FPGA 的 FT 数据发送，按键和 ADC 采集继续工作。
它不会关闭另一台电脑的 Python 接收窗口；窗口退出仍由 Ctrl+C 或 --seconds 计时控制。
不要用 !A 的 ready=1 代替硬件接线验证：MISO 悬空或错误供电也可能产生有效采样时序。

## 构建与回退

- 工程：`images/image5_canny/Ti60_Image5_Canny.xml`。
- 独立构建：`tools/build-image.ps1 -Image 5`，使用 image5 异步专用检查流程。
- 输入集成测试：`tools/test-image5-inputs.ps1`，检查实际 UART 线上快照、队列和按键。
- 原 SPI/滤波测试：`tools/test-adc.ps1 -Tests mcp3202_spi,adc_input_ctrl,mcp3202_production`。
- 修改前 main 源码标签：`codex/backup-before-image5-inputs-20261026`。
- 已验证异步 image5 基线：`codex/image5-async-fifo-20261024`（286a939）；
  上述 main 标签包含旧同步 image5 RTL，不能用它重新编译后当成异步版烧录。
- 修改前 bit/hex 和配置：`E:/Efinity_Project/bit_hex_archive/Image5_before_inputs_20261026.zip`。

当前 main 的旧同步 image5 RTL 已先按本地 `codex/image5-async-fifo-20261024` 恢复；
保留最新 main 的 image1～image4、共享 ADC 模块及修订后的 AXI 控制器。
此次不推送 GitHub，不操作 FT EEPROM，不自动下载板卡或写 Flash。

2026-10-26 19:21:37 最终完整构建通过：17,714 XLR、104 RAM10、11 DSP，
28 项 setup/hold 全部通过，最小余量 +0.017ns；系统 setup/hold +3.894/+0.027ns，
像素 setup/hold +1.200/+0.026ns。实际网表确认 ADC/GPIO 双级同步器存在，
OLED 片选保持高、SD 输出关闭，没有旋钮阈值控制实例。
文件哈希见 [下载清单](download-files.md)。

仿真全部通过：输入集成实际 UART 字节校验、500kHz SPI 生产参数与延迟 MISO、
GPIO 消抖/按住/松开重按、FT 命令和回复归属、异步 PHY 引脚时序/背压/正常停流、
1920×1080 输入的三档灰度/1bpp/8bpp 边缘 CRC 和像素独立校验，
以及连续四帧 1080p Canny 去噪/清理回归。
全尺寸 FT 包测试使用 FAST=1 加速包级验证，物理 WR 时序在小尺寸测试中单独检查，
不把仿真处理速度写成 USB 实测帧率。
日志目录为 `work_sim/image5_inputs_20261026/`，未改动其他四个镜像的源码和下载文件。
