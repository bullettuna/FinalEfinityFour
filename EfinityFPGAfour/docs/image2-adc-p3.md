# image2：旧 P3 ADC 旋钮调阈值与串口收图

按用户确认使用旧版 MCP3202 的 P3 接线，复用已经在 image1/image3 使用的驱动。
image2 保留完整 960×540 Canny 照片、UART 收图、TF 保存和相册。
新版 FT232H 交接包中的 P4 SPI 接线不用于本固件。

## 旧版接线

- MCP3202 CLK/SCLK → FPGA A4，`spi_sclk`，GPIOL_09。
- MCP3202 DIN → FPGA A3，`spi_mosi`，GPIOL_03。
- MCP3202 DOUT → FPGA A13，`spi_miso`，GPIOR_12。
- MCP3202 CS/SHDN → FPGA C3，`cs_adc`，GPIOL_06。
- 旋钮滑动端接 MCP3202 CH0；电源、地和原旧版电路相同，保持共地。

以上为 FPGA 焊球编号；对应现有旧 P3 排线，不是排针第 A4 脚。
这四路 IO 使用 3.3 V LVCMOS，外围约束未迁移、未改电压。
旧 P3 ADC 接线与 FT232H 的 P3 FIFO 信号重叠，使用本方案时不能同时连接该 FT FIFO 排线。
新版 P4 方案的 SCLK/MOSI/MISO/CS 为 G4/G3/G2/H2，应使用对应 P4 固件。

## 调节规则

SPI Mode 0、500kHz，MCP3202 双通道轮询，CH0 每秒采样 1000 次。
旋钮用八点移动平均；平均值变化至少 8 个 ADC 码才更新阈值。

高阈值 `H = CH0平均值 >> 1`，范围 0～2047；低阈值 `L = H >> 1`。
例如 ADC=120 对应 H60/L30；ADC=200 对应 H100/L50。
阈值升高通常会减少保留边缘；低阈值与高阈值联动。
平均值还未准备好时使用 image2 默认 H60/L30，准备好后由当前旋钮位置接管。

H/L 串口设置、加减和 R 继续保留：串口提交优先于同周期旋钮变化，并重新建立旋钮死区。
下一次旋钮移动超过死区后再接管。R 恢复 image2 的 H60/L30；M/D/N 不受旋钮影响。
旋钮不控制 N 连通域面积门限，也不控制 Gamma/白平衡。

预览高低阈值通过原握手邮箱在帧边界成对生效。UART `@` 或 TF `b` 接受采集时，
照片锁定同一 ADC/UART 有效阈值源；采集、处理和传输期间继续转动旋钮，不改变这张照片。
UART 图片附带 JSON 的 high/low 是该张照片实际使用的值。
预览与照片各自的采样尺度及局部/完整 Canny 差别仍见 [image2 拍照说明](image2-canny-photo.md)。

## 如何采集

1. 使用旧版 P3 ADC 板和原来的 USB 串口连接。
2. 通过 JTAG 下载下方本次 ADC P3 固件。
3. 关闭 VOFA+/串口助手，运行已经准备好的收图脚本：

```powershell
python "E:\Efinity_Project\EfinityFPGAfour\tools\image2_uart_receive.py" --port COM5 --label pose1 --output "E:\Efinity_Project\edge_picture"
```

COM5 换成实际 FPGA UART 端口。该命令不带 `--high/--low`，沿用旋钮当前阈值。
脚本自动进入 E 模式。先看 HDMI 画面调旋钮、摆好动作，再在电脑按一次 Enter。
等 `Saved ... CRC OK` 后得到 `E:\Efinity_Project\edge_picture\pose1` 中的 PNG 和 JSON。
下一张重新按 Enter，q 退出；换动作可重新以 `--label pose2` 启动。
电脑串口由一个收图程序占用，旋钮调节直接在 FPGA 上完成，不需额外打开串口助手。

采图无需 TF 卡。原 b/i/x/d 命令和 TF 回执保留；ADC 按键上报在 image2 中不启用，
因此不会挤掉 TF 状态消息。image1 的按键上报保持原行为。

## 两个可回退版本

- 本次旧 P3 ADC＋UART 版：编译验证通过后更新
  `images/image2_photo/outflow/Ti60_Image2_Photo_checked.bit`。
- 上一版仅 UART 调阈值和收图：
  `images/image2_photo/outflow/before_adc_p3_20261022/Ti60_Image2_Photo_checked.bit`，
  SHA256 `49FAB6DC99AFBE959D46622BA5E60206C222620BF89425E053A11C33EDE98A76`。

修改前源码 ec2e437 已推送 GitHub。

## 验证

```powershell
python "E:\Efinity_Project\EfinityFPGAfour\tools\check-image2-adc.py"
& "E:\Efinity_Project\EfinityFPGAfour\tools\test-adc.ps1" -Tests mcp3202_production,adc_input_ctrl,adc_threshold_ctrl,adc_threshold_image2,adc_uart_reporter
& "E:\Efinity_Project\EfinityFPGAfour\tools\test-image2-uart.ps1"
& "E:\Efinity_Project\EfinityFPGAfour\tools\build-image.ps1" -Image 2
```

检查包含旧版引脚/IO 电压、TF 消息归属及负向接线用例；96MHz/500kHz SPI 真实引脚模型、
CH0 滤波、死区、image2 H/L/R 与旋钮接管、帧边界阈值对齐；真实采样/DMA/整帧
Canny/串口联合仿真在采集后转动旋钮，检查数据包参数和每个图像像素仍使用已锁定值。
原 UART 包和 TF 保存、失败重试、相册、删除继续回归。

2026-10-22 21:08，Efinity 2025.2，TIMING_2 / effort=2 / seed=4，原约束不变。
上述接线与功能仿真通过，实际网表保留 MCP3202 驱动、CH0 均值、阈值选择和帧边界握手，
同时保留 TF 状态报告器与 UART 图片导出，移除 image2 中不使用的 ADC 按键上报器。
全部 28 项约束内 setup/hold 非负，最小 +0.020ns；像素时钟 +1.033/+0.026ns，
系统时钟 +2.198/+0.026ns，DDR core_clk→twd_clk setup +0.153ns。
资源 34,988 / 60,800 XLR、127 / 256 RAM10、32 / 160 DSP，没有新增 RAM。

当前旧 P3 ADC 固件：

- `images/image2_photo/outflow/Ti60_Image2_Photo_checked.bit`，2,694,522 字节，
  SHA256 `2CA5E869463A8F5396914E9AD114A725E1989430AC9AAAEC2163496F01F1A5E8`。
- `images/image2_photo/outflow/Ti60_Image2_Photo.hex`，2,694,582 字节，
  SHA256 `B9851800D3C6EC09E955F7F1CBFE0079DD0060F349BDD4C0E4CE0EA95B6A78ED`。

checked.bit 与同次原始 bit 一致；源码指纹、原 P3 引脚和配置检查通过。
本次尚未下载实板、未写 Flash，旋钮实物方向、阈值效果及串口实拍仍需上板确认。
日志：`work_sim/image2_adc_controls.log`、`work_sim/image2_adc_uart_regression.log`、
`work_sim/image2_adc_p3_build.log`。
