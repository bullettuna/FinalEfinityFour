# image1：屏幕左上角文字菜单

2026-10-26已迁移到最新P4扩展板，按键/ADC接线见 [P4输入说明](image1-p4-inputs.md)。下方旧构建日期为历史记录。

在 1080p HDMI 画面的左上角增加一个纯文字菜单，用现有的 MCP3202 旋钮、
ADC CH1 分压按键 2/3 和独立按键 KEY1（P4-37 / GPIOL_N_18 / A2）操作。菜单项直接对应
串口已有功能，不新增第二套参数寄存器。

## 操作

| 输入 | 菜单关闭 | 菜单打开（BROWSE） | 编辑中（EDIT） |
|---|---|---|---|
| KEY1 长按 ≥800 ms | 打开菜单 | 关闭菜单 | 关闭菜单（已生效值保留） |
| KEY1 短按 <800 ms | 无动作 | 数字项进入 EDIT；开关翻转；枚举下一值；动作执行 | 确认并退出 EDIT |
| KEY2 短按 | 原串口 `key 2` 上报 | 光标上移（到顶循环到底） | 数值 −1 |
| KEY3 短按 | 原串口 `key 3` 上报 | 光标下移（到底循环到顶） | 数值 +1 |
| 旋钮 | 无动作（不再直接调 Canny） | 滚动列表，每 256 个原始码值一项 | 粗调数值 |

- 一屏显示 8 项；光标走出窗口时窗口跟随移动。17 项首尾循环。
- KEY2/KEY3 每次只改变一个最小分度值；旋钮提供快速粗调。
- 进入 EDIT 时重新记录旋钮基准，切换菜单项不会让数值跳变。
- **旋钮死区 16 个原始码值**，并且进入 EDIT 后先等 8 个 ADC 平均样本
  （约 8 ms）再开始调节。CH0 八点平均值的几 LSB 抖动不会造成 WB/Gamma
  数值“自动递减”；这是对实板反馈的修复。
- **image1 的旋钮不再直接连接 Canny**：`adc_threshold_ctrl` 使用
  `KNOB_DIRECT=0`，上电保持高 25 / 低 8，第一个 ADC 平均样本不会再把
  阈值覆盖成旋钮位置。只有菜单里的 `CANNY`、`CANNY H`、`CANNY L`
  进入 EDIT 后，旋钮才会通过菜单写入调整阈值。
- image2 仍使用 `KNOB_DIRECT=1`，保留原来的旋钮直调阈值行为。

## 菜单项

| # | 菜单名 | 类型 | 范围/状态 | 串口等价 |
|---|---|---|---|---|
| 1 | `VIEW` | 枚举 | COLOR / GRAY / EDGE / EDGE-RGB | `C` `G` `E` `O`（`T` 的四个状态） |
| 2 | `SPLIT` | 开关 | ON / OFF | `\|` |
| 3 | `SHAPE` | 开关 | ON / OFF | `D` |
| 4 | `FREEZE` | 开关 | ON / OFF | `F` |
| 5 | `TEST` | 开关 | ON / OFF | `Z` |
| 6 | `CANNY` | 数字联动 | 高 0～2047，低=高/2 | `H<v>` + `L<v/2>` |
| 7 | `CANNY H` | 数字 | 0～2047 | `H<v>` |
| 8 | `CANNY L` | 数字 | 0～高阈值 | `L<v>` |
| 9 | `CANNY RST` | 动作 | — | `R` |
| 10 | `MEDIAN` | 开关 | ON / OFF | `M` |
| 11 | `WB R` | 数字 | 0～2047（Q8.8） | `WR<v>` |
| 12 | `WB G` | 数字 | 0～2047 | `WG<v>` |
| 13 | `WB B` | 数字 | 0～2047 | `WB<v>` |
| 14 | `WB RST` | 动作 | — | `WD` |
| 15 | `GAMMA` | 开关 | ON / OFF | `Y` |
| 16 | `GAMMA P` | 数字 | 0～256 | `P<v>` |
| 17 | `BLACK` | 数字 | 0～255 | `B<v>` |

- `RECT`、`LINE SUP` 暂不进菜单，保持默认 `LINE-FIT` 和 `K0=1/2`，仍可用
  串口 `J`/`K0..K3` 修改。
- image1 的 Canny 默认值为 **高 25、低 8**；`CANNY RST` 和串口 `R` 恢复这两个值。
  `CANNY` 联动项仍按 高=旋钮/2、低=高/2 的比例调整。
- image1 默认白平衡为 **R=496、G=416、B=313**，Gamma 默认 ON、强度 **255**；
  `WB RST` 和串口 `WD` 恢复 496/416/313，`GAMMA P` 显示 255。
- `Q`、`?` 是串口查询，不是设置项，不占菜单。
- image1 不支持拍照/相册/person/Sobel，相应命令本来就会被拒绝，不列入菜单。

## 显示实现

- 菜单区域：左上角 `(8,8)` 起，30 列 × 12 行，每格 18×24 像素，
  总计 **540×288** 像素。字体为手写 5×7 ASCII，**3 倍放大**（15×21 像素）。
- 行 0 标题和当前位置；行 1～8 为可见菜单项；行 9 分隔线；行 10～11 操作提示。
- 颜色：白字、选中行黄字、EDIT 行青字、深色底衬。
- 叠加位置在 `video_diagnostic_mux` 之后、`rgb2dvi` 之前，因此菜单对 live、
  相册、person 和 `Z` 测试图都可见。

### 为什么不会影响 HDMI 时序

`menu_text_render` 的三级流水同时携带 VS、HS、DE 和 RGB：

1. 第 0 级：x/y 计数、字符选择；
2. 第 1 级：字体行查找；
3. 第 2 级：像素选择与 RGB 替换；
4. 输出寄存器。

四根信号经过完全相同的三个寄存器，行宽、场周期、极性和相对相位不变。
菜单关闭时 `region=0`，输出就是输入延迟三拍，逐位相同。菜单区域之外
只替换 RGB 的条件不成立，所以像素也与输入完全一致。仿真直接断言：

- 输出 VS/HS/DE/RGB 相对输入统一延迟 3 拍；
- 菜单关闭时整帧逐位相同；
- 菜单打开时区域外逐位相同、区域内只出现底衬/文字颜色；
- 选中行 `>` 标记和 EDIT 方括号均可见。

## 时钟域与控制通路

- `menu_ctrl` 全部在 `clk_sys`（96 MHz），与 ADC、按键同域。
- image1 的 `adc_threshold_ctrl` 用 `KNOB_DIRECT=0` 关闭旋钮直连阈值路径；
  阈值只由串口命令或菜单写入更新。这样上电后 Canny 稳定在 25/8，不会被
  旋钮当前位置覆盖。
- 原设计的 `knob_ready` 置 1 后一直保持，是电平而不是脉冲。菜单使用
  `adc_input_ctrl` 新增的 `knob_sample` 单周期脉冲，每个平均样本（1 kHz）一次，
  所以 EDIT 的 8 个样本稳定期是真实的约 8 ms，滚动的相对位移也按样本累计。
- 124 位显示记录经两级 `async_reg` 同步，只在 `!w_hdmi_vsync` 消隐期整体提交，
  与现有 `r_video_mode_*` 的帧边界提交方式一致。
- 菜单不解析 ASCII，也不注入串口字节；它通过
  `menu_write_valid/addr/value` 直接写 `uart_vision_ctrl` 内部同一组 request
  寄存器。串口和菜单最后写入者生效，不存在影子状态。
- 菜单总线上写的是**目标绝对值**，不是 toggle；开关项和 `Z` 不会因为丢一次
  回复而反向。
- `MENU_BUILD` 默认 0，只在 `image1_top.v` 置 1；image2 以及 image3～5 的
  控制/显示路径完全不变。

## 文件

新增：

- `src/ui/menu_defs.vh`：菜单项编号、显示记录位域。
- `src/ui/key_press_debounce.v`：20 ms 消抖 + 800 ms 长按单次触发。
- `src/ui/menu_ctrl.v`：状态机、滚动、EDIT、BCD 显示记录、绝对控制写。
- `src/ui/menu_font_8x8.v`：5×7 ASCII 字形 ROM（生成文件）。
- `src/ui/menu_text_rom.v`：17 项静态标签 + 4 行提示文字（生成文件）。
- `src/ui/menu_text_render.v`：像素域三级流水叠加。
- `src/ui/menu_ctrl_tb.sv`、`src/ui/menu_text_render_tb.sv`。
- `tools/generate-menu-font.py`：字体与静态文字 ROM 生成器。
- `tools/check-image1-menu.py`：顶层接线/隔离/流水静态检查。
- `tools/test-image1-menu.ps1`：两个仿真回归。

修改：

- `src/adc/adc_input_ctrl.v`：新增 `knob_sample` 单周期脉冲（每个 1 kHz
  平均样本一次）；原有 `knob_ready` 电平保持不变。
- `src/adc/adc_threshold_ctrl.v`：增加 `KNOB_DIRECT` 和 `knob_enable`；image1
  用 `KNOB_DIRECT=0` 综合裁掉旋钮直调分支，image2 保留原直调行为。
- `src/vision/uart_vision_ctrl.v`：增加菜单绝对写端口和 17 项写分支。
- `example_top.v`：`MENU_BUILD` 参数、菜单实例、显示记录 CDC、三级流水叠加。
- `images/image1_vision/image1_top.v`：`MENU_BUILD=1`。
- `tools/build-image.ps1`：Image 1 构建前执行菜单静态检查。
- 三个 `adc_threshold_ctrl` 测试平台补上 `knob_enable(1'b1)`。
- `tools/test-adc.ps1`：补齐菜单头文件搜索路径；增加 image1 菜单写入与旋钮
  隔离的集成回归，保留 image2 直调回归。

## 验证

```powershell
python tools/check-image1-menu.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-image1-menu.ps1
& ./tools/test-adc.ps1 -Tests adc_threshold_image1,adc_threshold_image2,uart_vision_ctrl,adc_uart_reporter
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-image.ps1 -Image 1
```

已通过：

- 静态检查：隔离、绝对写、三级流水、消隐期 CDC、构建图。
- `menu_ctrl_tb`：长按开关、KEY2/KEY3 上下与循环、窗口滚动、VIEW 枚举、
  EDIT 进入/确认、KEY2/KEY3 ±1、旋钮粗调（死区 16）、开关/动作写、
  关闭后忽略输入，以及 **WB 值对 ±4 码值抖动不响应**（自动递减回归）。
- `menu_text_render_tb`：菜单关闭 608000 像素逐位直通；BROWSE 155520 个菜单
  像素（540×288；底衬/文字/63 像素的 `>` 标记）；EDIT 方括号 99 像素可见；
  再次关闭逐位直通。
- `adc_threshold_image1`：上电后全部 4096 个旋钮码值均保持 25/8；菜单 H/L、
  联动和复位，以及 UART 设置/复位经过实际参数寄存器和帧边界握手生效；
  ADC 已就绪时再次复位仍保持 25/8。`adc_threshold_image2` 保留原旋钮直调验证。

### 最终构建：2026-10-24 03:49:53

- 保留 17 项菜单、5×7 字体 3 倍放大、540×288 窗口和三级 HDMI 同步流水。
  默认值为 Canny H25/L8、WB 496/416/313、Gamma ON/255；image1 使用
  `KNOB_DIRECT=0`，旋钮只在相应菜单 EDIT 中通过菜单写入调整数值。
- `tools/build-image.ps1 -Image 1` 完整执行 map / interface / pnr / pgm /
  bitstream export，并通过实际网表、源文件未变化和全部 **28 项 setup/hold** 检查。
  只有完成这些检查后才复制 `_checked.bit`。
- 最终配方 **TIMING_2 / seed=14 / placer effort=2**，XML 和构建脚本期望值一致。
  本轮 seed=13/effort=2 的 pixel setup −0.073 ns、DDR setup −0.042 ns，
  被脚本拒绝；seed=14 同时收敛后停止搜索，未修改任何 RTL 时序流水或 SDC。
- 综合资源：**35,279 LUT4 / 17,870 FF / 197 RAM10 / 12 DSP**
  （9 DSP48 + 3 DSP24）；P&R 占用 52,404 / 60,800 XLR。
- `clk_pixel_2x` 约束仍为 **6.720 ns**，setup **+0.060 ns**、hold **+0.026 ns**；
  DDR `core_clk→twd_clk` setup **+0.023 ns**、hold **+2.099 ns**。
  14 项 setup 和 14 项 hold 全部非负，全局最小 **+0.022 ns**（CSI hold）。
- 下载文件：`images/image1_vision/outflow/Ti60_Image1_Vision_checked.bit`，
  修改时间 **2026-10-24 03:49:53（Asia/Shanghai）**，**2,995,605 字节**。
  SHA256：`f5c1c3acdd6b9b8aef14697085e099d0c0b7955fc47f5e4ea8767b28d7d017c9`。
  已与同次 `.bit` 逐字节核对一致。
- 同次 hex：`images/image1_vision/outflow/Ti60_Image1_Vision.hex`，2,995,665 字节，
  SHA256：`a082e44c25caffa14dc3f8cf2b257b0f95a91a94d910ea8d85fd8d2c1321935b`。
- 证据：`work_sim/image1_timing_sweep/results.json` 和
  `work_sim/image1_timing_sweep/seed14_effort2/build.log`；同目录保存本轮报告。
  最终源码、下载文件与报告另存于
  `E:/Efinity_Project/bit_hex_archive/Image1_final_menu_seed14_20261024_034953.zip`，
  旁边 manifest 记录每个文件的长度、时间和 SHA256。
- 菜单静态/仿真、image1 旋钮隔离集成回归、image2 直调及原 UART/按键串口回归
  均通过。相对接手时的快照，功能 RTL 与各镜像 SDC 均未修改；image2～image5
  项目配置和既有下载文件未更新。尚未上板，未写 Flash，未提交或推送。

### 历史对照：2026-10-24 02:22 完整构建结果

此构建使用旧默认值 H17/L8、WB 335/248/280、Gamma 42，旋钮直调仍开启，
仅作为历史对照，不满足本次最终默认值和旋钮隔离要求。

- `tools/build-image.ps1 -Image 1` 的 map / interface / pnr / pgm / bitstream
  全部 PASS，并通过 28 项 setup/hold 与网表检查。
- P&R 配方：TIMING_2 / **seed=8** / placer effort=2。Canny 默认值改为
  17/8 后，seed=7 的 DDR `core_clk→twd_clk` 出现 -0.029 ns；seed=8 为
  **+0.019 ns**，因此当时采用 seed=8；当前最终配方见上一节。
- 资源：35,192 LUT4 / 17,884 FF / 197 RAM10 / 12 DSP。
- 时序：像素时钟 Setup **+0.088 ns**、Hold **+0.030 ns**；
  全局最小 **+0.019 ns**（core_clk→twd_clk Setup），所有关系非负。
- 当时的下载文件：`images/image1_vision/outflow/Ti60_Image1_Vision_checked.bit`
  （2026-10-24 02:22:49，SHA256
  `819f71e8810e1e29d5ffeb7cb6ec0031c3e45613e221b1044e0e8947daca7b46`）。
- 此历史 bit 已保存在接手时的本地快照中；当前下载路径已由上一节最终版本替换。

## 上板检查顺序

1. 下载最终 `_checked.bit`，上电确认菜单默认关闭；Canny 为 25/8，WB 为
   496/416/313，Gamma 为 ON/255。转动旋钮不能直接改变 Canny。
2. 长按 KEY1 约 1 秒，确认左上角出现菜单；短按 KEY3/KEY2 上下移动，确认首尾循环。
3. 选中 `VIEW` 短按 KEY1，确认在 COLOR/GRAY/EDGE/EDGE-RGB 间切换，串口也可用 `T`。
4. 选中 `CANNY H` 短按 KEY1 进入 EDIT，用 KEY2/KEY3 ±1、旋钮快调，再短按确认。
5. 逐项检查 SPLIT、SHAPE、FREEZE、TEST、MEDIAN、GAMMA、WB、BLACK。
6. 长按 KEY1 关闭菜单，确认画面恢复、已设置参数保留；再转动旋钮不能直接
   改变 Canny。重新上电确认恢复本节第 1 项默认值。
7. 若异常，记录菜单状态、LED0～3 和串口 `?`/`Q` 回复，区分菜单逻辑与
   DDR/摄像头/HDMI 链路问题。
