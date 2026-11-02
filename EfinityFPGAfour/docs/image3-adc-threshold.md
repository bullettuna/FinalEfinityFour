# image3：ADC 旋钮调 Canny 阈值

2026-10-20：当前源码及下载文件已升级为 [上半身姿态匹配版](image3-upper-body.md)，
继续保持 ADC 关闭、Canny 默认 0/0。本次未上板；以下保留此前阈值修改和 JTAG 下载记录。

## 当前状态：2026-10-20 保存串口调节后的默认阈值

根据用户提供的连续减号操作记录，将 image3 Canny 的默认高/低阈值设为 0/0。
从之前的 45/22 连续执行减号，45 次即可降到 0/0，再减保持 0/0；
低阈值在高阈值下降到其范围后同步收紧。T 及回复 2 属于显示模式切换，不是阈值。

上电配置初始化和 R 命令都恢复 0/0。ADC 继续关闭，H/L 与加减命令继续有效，
人体背景差分 N 阈值及相机/DDR/显示路径没有改动。image1、image2 保持原样。
修改前源码为已推送的 `eacc17e`，原 image3 bit/hex 另存于：
`E:/Efinity_Project/bit_hex_archive/Image3_before_zero_defaults_eacc17e_20261020_174229.zip`。
本次验证复现 H45/L22 后连续减号到下限，检查加号和 R 恢复 0/0，
并检查 N 人体差分阈值不会被 Canny 操作修改。零默认值与原 45/22 配置的 UART 回归均通过。

2026-10-20 17:44 完整编译、实际网表和全部 28 条约束内 Setup/Hold 检查通过。
最小余量 +0.021 ns，像素 Setup/Hold +0.849/+0.035 ns；资源 19,635 XLR / 228 RAM10 / 13 DSP。
保持 TIMING_2 / seed=6 / effort=2，ADC 分支没有综合进 image3。
已完成 Ti60 `0x10660A79` 的临时 JTAG 下载，工具返回 0 并报告完成，没有写入 Flash。
下载日志：`work_sim/image3_zero_defaults_jtag_download.log`。

当前 bit 长度 2,423,709 字节，SHA256：
`B8B405D5DB512E99003A7AAA14ACE3CA5B1CC32334545D2F9C7D23BA92213DB0`。
对应 hex 长度 2,423,769 字节，SHA256：
`03A3EE57FF6BF584F1DFEA42C46616B21131050667EF034E2319004A866C5E05`。

## 历史：2026-10-20 关闭 ADC（当时默认 45/22）

按用户要求，image3 包装层改为 `ENABLE_ADC=0`。本次仅关闭旋钮 ADC，
没有改动默认 E 显示、T 切换、F 冻结、相机、DDR、R 人体候选及 U6 预览。
SPI 时钟和 MOSI 保持低电平，ADC CS 保持高电平；实际网表要求 ADC 分支完全消失。
高/低阈值直接来自原串口控制器，默认 45/22。
`H数字+回车`、`L数字+回车`、`+`、`-` 和 `R` 继续有效，旋钮不会再接管。
帧边界阈值握手保留；N 仍独立控制人体背景差分阈值。
image1 的 ADC 及共享驱动源码未修改。

修改前源码为已推送的 `0580a7e`；原 image3 bit/hex 已另存于工程外：
`E:/Efinity_Project/bit_hex_archive/Image3_before_ADC_disable_0580a7e_20261020_171659.zip`。
2026-10-20 17:19 新构建通过：网表没有 `g_adc`，保留 UART、帧边界握手和原 R/ROI/Canny。
资源 19,498 XLR / 228 RAM10 / 13 DSP，比开启 ADC 时减少 681 XLR。
接线负向测试和 image3 UART 回归通过；全部 28 条约束内 Setup/Hold 非负，最小余量 +0.018 ns。
像素 Setup/Hold +0.829/+0.030 ns，系统 Setup +3.942 ns。保持 TIMING_2 / seed=6 / effort=2。

最新 bit 长度 2,420,061 字节，SHA256：
`E889118DBDA51029FCF1A3D795AC4827DEA2B9FF07F1847CF41C15208C0F3C0E`。
对应 hex 长度 2,420,121 字节，SHA256：
`7DBA2F6547C7D1A27E64979D88159021BD0FAD3A3BA40B664BB02C89BCD040E9`。
已通过 FT232H / 6 MHz JTAG 临时下载到器件 `0x10660A79`，下载工具返回 0 并报告完成。
日志为 `work_sim/image3_adc_disabled_jtag_download.log`，没有写入 Flash。
本次关闭 ADC 不代表已确认或修复此前报告的顶部花屏与画面静止，效果仍需实板观察。

下方为 2026-10-14 开启 ADC 阶段的历史记录。

## 历史：2026-10-14 ADC 移植

image3 的独立平台开启 `ENABLE_ADC=1`，复用 image1 的现有模块：
`mcp3202_spi`、`adc_input_ctrl`、`adc_threshold_ctrl` 和 `edge_threshold_cdc`。
image1 的实现和下载文件保持原样。

## 接线与阈值

MCP3202 接线与 image1 相同：SCLK=A4、MOSI=A3、MISO=A13、CS=C3。
96 MHz 系统时钟产生 500 kHz SPI；两个通道交替采集，每路 1 kHz。
CH0 是旋钮，取八点移动平均；此次只接入阈值控制，没有增加按键串口输出。
OLED CS 保持高电平。

高阈值 = CH0 均值 / 2，范围 0～2047；低阈值 = 高阈值 / 2，范围 0～1023，向下取整。
保留 8 个 ADC 码的变化死区；均值有效后按当前旋钮位置接管。
高低阈值通过冻结邮箱和跨时钟域握手，在 RGB 帧边界成对生效。
例如 ADC 90 对应 45/22，ADC 2048 对应 1024/512。
高阈值越大，能保留的边缘越少。

## 影响的显示与串口操作

- `E`：普通 Canny 二值边缘，使用旋钮阈值。
- `U6`：R 候选 ROI 内的 Canny 预览，使用同一份边缘掩码和旋钮阈值。
- `H数字+回车`、`L数字+回车`、`+`、`-`、`R`：保留原 Canny 手动控制。
  手动提交时获得控制权；R 恢复 45/22；旋钮随后变化超出死区会再接管。
- `N数字+回车`：继续设置人体 RAW 背景差分阈值，独立于 Canny/旋钮控制。

ADC 不自动输出数值，原串口命令回复照常发送。
先用 E 观察旋钮效果；U6 需要按 image3 原流程在无人画面发送 b 采集背景，
Q 确认就绪后，进入人体候选区域并通过 U 切换预览。
原版本号 V=8、R 差分定位、掩膜修补、ROI 和 U1～U5 操作保持原样。

## 本地构建与检查

运行 `tools/test-image3-wiring.ps1`，检查独立平台、ADC 开关、UART 接管、有效阈值连接和 U6 接线；
错误接线的负向测试必须被拒绝。
运行 `tools/test-adc.ps1 -Tests adc_threshold_ctrl,adc_threshold_image3`，
覆盖两个 UART 配置下的旋钮映射、死区、R/H/L 接管和异步帧边界阈值更新；
image3 配置另外检查 N 与 U6 不抢占 Canny 控制。
运行 `tools/test-person-roi.ps1 -Tests uart_person_raw_extra,person_canny_roi_view`，
检查原 image3 UART 与 Canny ROI 预览。

本地完整构建使用 `tools/build-image.ps1 -Image 3`，实际网表必须保留 ADC 驱动、
CH0 滤波、阈值选择、帧边界握手、原 R/ROI/Canny，全部约束内 Setup/Hold 必须通过。
下载文件统一为 `images/image3_pose/outflow/Ti60_Image3_Pose_checked.bit`。
构建成功后保留对应 `Ti60_Image3_Pose.hex`，不另存重复命名的 bit。

修改前源码备份为 `00a5a38`，已推送 GitHub。
修改前 image3 bit/hex 保存在工程外：
`E:/Efinity_Project/bit_hex_archive/Image3_before_ADC_00a5a38_20261014_173912.zip`。

此次本地构建结果见下方记录；实板 JTAG 下载情况见文末。

2026-10-14 17:41 本地完整编译通过。旋钮控制在 image1/image3 两种 UART 配置下的测试、
image3 N/U6 独立性、原 UART/U6 预览回归以及接线负向测试全部通过。
实际网表保留 ADC 驱动 112 XLR、CH0 滤波 221 XLR、阈值选择 98 XLR、
帧边界握手 81 XLR，这四个模块均未占用 RAM。
全工程使用 20,179 XLR / 228 RAM10 / 13 DSP；保留原 R/ROI/Canny，未启用被裁剪的分支。

TIMING_2 / seed=6 / effort=2，时钟约束保持原样。
全部 28 条约束内 Setup/Hold 非负，最小余量 +0.021 ns。
系统 Setup +4.587 ns，像素 Setup/Hold +0.912/+0.033 ns，DDR core→twd Setup +0.085 ns。
构建期间 RTL 指纹一致，checked.bit 与同次原始 bit 的 SHA256 一致。

最新 bit 长度 2,435,052 字节，SHA256：
`1078B4C590B72FAC5A0EDC037DF1AE1484DF1976DAD4F08BB957F407EDE13449`。
对应 hex 长度 2,435,112 字节，SHA256：
`D4BE11C15EFAB1F5D21F1DB083781BB3AE366E91AB2DF945C7384DC7B01CEB03`。

## 实板 JTAG 下载

2026-10-14 17:50 已完成 image3 临时 JTAG 下载。下载前 SHA256 与上述记录一致，
探测到单个 Ti60，器件 ID `0x10660A79`，IR 长度 5。
使用 FT232H 下载器、`Generic Board Profile Using FT232` 配置和 6 MHz JTAG，
Efinity 输出 `... finished with JTAG programming`，进程返回 0。
这是 FPGA 临时配置，没有执行 Flash 写入。

下载日志：`work_sim/image3_adc_jtag_download.log`。
本轮实现源码保存为提交 `3f1964e`，已推送 GitHub。
尝试以 COM12 / 115200 / 8N1 读取 V/I/?，打开串口时被拒绝访问，
因此未发送这些查询，也没有关闭占用串口的程序。
2026-10-14 用户在现有串口工具完成实板确认：V 回复 8，发送 E 后，
边缘随旋钮转动发生变化。由用户现场观察确认，已下载的 image3 旋钮调 Canny 阈值功能生效。

在已连接单个 FT232H 下载器时，可使用以下本地命令重新临时下载：

```bat
call "E:\Efinity\bin\setup.bat"
call "E:\Efinity\pgm\bin\ftdi_pgm.bat" --list_usb
call "E:\Efinity\pgm\bin\ftdi_pgm.bat" --mode jtag --board_profile "Generic Board Profile Using FT232" --url "ftdi://0x0403:0x6014:2:2f/1" "E:\Efinity_Project\EfinityFPGAfour\images\image3_pose\outflow\Ti60_Image3_Pose_checked.bit"
```

命令先加载 Efinity 环境，以确保其 Python 运行库路径正确；
FT232H 下载器需显式选择 FT232 配置，否则默认下载器接口选择可能失败。
上述 URL 为 2026-10-20 实际探测值，插拔后可能改变，应替换为 `--list_usb` 列出的当前 URL；
此安装的默认 URL 接口选择存在索引错误，因此同时显式指定 `--url`。
