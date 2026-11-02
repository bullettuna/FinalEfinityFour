# image1 最新扩展板按键与 ADC

2026-10-26，将image1从旧P3外设接线迁移到最终P4扩展板；保留原有菜单、
中值、Canny、分屏、冻结、双目标中文标签及固定HDMI同步路径。

## 接线依据

本机最新交接表：
`C:/Users/zhang/Documents/image5_FT232H异步FIFO交接包_20261024/01_最终硬件引脚表_含未使用AC5.csv`。
其中13项P4映射与2026-10-21硬件接入交接包一致；仓库镜像为
`images/image1_vision/p4-inputs.json`，记录源表SHA256、封装管脚、方向与电平。
前次已核对的扩展板原理图为 `E:/unfloding/SCH_Schematic1_2026-10-24.pdf`。

- MCP3202 SCLK：P4-13 / GPIOL_N_12 / G4。
- MCP3202 DIN（MOSI）：P4-14 / GPIOL_P_12 / G3。
- MCP3202 DOUT（MISO）：P4-17 / GPIOL_N_10 / G2。
- MCP3202 CS#：P4-18 / GPIOL_P_10 / H2。
- 独立SW1/KEY1：P4-37 / GPIOL_N_18 / A2，低电平按下。
- OLED迁移到P4-19/F5、P4-20/G5，但保持不选中。
- 未启用的SD引脚也按最终P4表迁移，CLK低、CMD/DAT输出关闭。

以上FPGA管脚使用1.8V LVCMOS；扩展板外设侧为3.3V，使用板上已有电平转换。
P4物理针号与表中的User_IO编号不同，接线应使用这里的P4物理针号。

## 按键和旋钮功能

长按独立KEY1约800ms打开/关闭菜单；短按进入或确认编辑。
ADC CH1连接SW2/SW3分压键：KEY2上移/减1，KEY3下移/加1。
ADC CH0连接旋钮：菜单浏览时滚动列表，编辑时粗调当前数值。
菜单关闭时旋钮不直接修改Canny，默认H25/L8、白平衡496/416/313、Gamma开启/255保持不变。

SPI为Mode0、500kHz，每通道1000次/秒；CH0八点均值，CH1三点中值及20个稳定样本消抖。
独立键约20ms消抖，长按不连发。分压键须稳定释放后才能再次触发。

CH1理论12位码值（与ADC相同3.3V参考）：释放4095、SW2约2048、SW3约1016、
同时按下约814。对应现有判定窗口3900～4095、1900～2200、940～1100、740～890。
这些是理论值和配置窗口，实际码值须上板验证。串口115200/8N1保留原按键报告。

## 构建和检查

```powershell
python tools/check-image1-inputs.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-image1-menu.ps1
& ./tools/test-adc.ps1 -Tests mcp3202_spi,adc_input_ctrl,adc_uart_reporter,adc_threshold_image1,mcp3202_production
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-image.ps1 -Image 1
python tools/package-image1-release.py
python tools/check-image1-release.py
```

构建先重新生成接口和管脚时序，再保留既有时钟域约束；未放宽像素时钟或DDR约束。
检查器同时核对实际外围XML、生成的封装管脚报告和网表中的ADC同步器、按键消抖及菜单控制器。
ADC、CH1滤波/串口消息、菜单参数隔离、菜单显示、独立键抖动/短按/长按回归均已通过。

## 上板检查

下载本次P4版checked.bit；旧P3版本无法通过改接线说明变成P4版。
先确认C/G/E画面稳定，再长按KEY1打开菜单；测试KEY2/KEY3光标与数值步进，
随后进入CANNY H或WB项编辑，转动旋钮观察数值。退出菜单后转旋钮不应直接改阈值。
最后确认长按不重复触发、松开后可再次操作，并测试M、分屏和中文标签显示。
软件和时序检查不能替代本次新接线的实板验收。

## 备份

修改前源码已推送分支 `codex/backup-image1-before-p4-20261026`，基线提交 `1d049fd`。
旧bit/hex、工程、外围和时序配置：
`E:/Efinity_Project/bit_hex_archive/Image1_before_P4_inputs_20261026.zip`。
旁边manifest记录长度与SHA256，压缩包逐项校验通过。
本次修改在 `codex/image1-p4-inputs-20261026` 分支进行。

## 最终文件与实现结果

2026-10-26 23:48:07导出P4版，TIMING_2 / seed17 / effort2。
28项setup/hold全部通过：像素+0.022/+0.027ns，DDR core_clk→twd_clk setup +0.064ns，
全局最小余量+0.020ns。资源52,404 XLR / 197 RAM10 / 12 DSP。
14/15/16三个候选的DDR setup分别为−0.018/−0.035/−0.004ns，均被拒绝，失败产物单独归档。
后两轮只改变布局种子，复用已完成全量编译的seed15映射结果；源码/配置及映射网表哈希均检查稳定，
仅忽略Efinity GUI自动更新的工程last_change时间戳。seed17的完整检查证据在
`work_sim/image1_p4/build_seed17_route.log` 及对应checkpoint JSON。

- 直接下载：`releases/image1/Ti60_Image1_Vision_checked.bit`，2,997,987字节。
  SHA256：`b83befafdb88c5bf8654772ef9a74313ca462b70b8ade3a647083b585b2ca97e`。
- 同次hex：2,998,047字节，SHA256：
  `7e5fdac82413de12dd3bb548bb6e68ad86b2fd317f4bf9cdbeeb5e02e1e5f979`。
- 本机outflow中的checked.bit与发布文件逐字节相同。
- 发布清单核验100个实际源码/配置依赖，并记录全部28项时序关系。
  `last_change`仅是GUI时间戳，校验时不作为功能参数；管脚、I/O标准、构建配方及其他配置仍参与校验。
- 对照修改前快照，image2～image5的工程、约束、源文件和既有bit/hex哈希均未改变。
- 最终文件与报告另存 `E:/Efinity_Project/bit_hex_archive/Image1_P4_inputs_seed17_20261026.zip`。

本次未自动下载JTAG或写Flash；新P4接线的按键/ADC实际操作仍须按上文验收。
