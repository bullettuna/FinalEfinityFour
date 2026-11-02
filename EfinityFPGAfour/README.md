# EfinityFPGAfour

image1已按最终P4扩展板配置独立键、MCP3202旋钮和分压键；接线与验收见 [image1 P4输入](docs/image1-p4-inputs.md)。

### main 直接使用 image1（2026-10-24）

拉取 `main` 后，将 [image1 预编译 bit](releases/image1/Ti60_Image1_Vision_checked.bit) 加载到 Efinity Programmer 即可使用；
同目录附带hex和SHA256清单，无需先编译、无需Git LFS。
完整源码、工程、菜单、中值及显示同步修复均已包含。
[拉取、下载与菜单操作](docs/image1-main-quickstart.md)；可运行 `python tools/check-image1-release.py` 校验文件和源码一致性。

image2 新增最终 960×540 Canny 二值照片的 UART 导出与电脑动作分类 PNG 采集：
[操作、固件和验证说明](docs/image2-uart-capture.md)。
另支持 [旧 P3 MCP3202 旋钮调阈值](docs/image2-adc-p3.md)，采图期间无需另开串口助手。

### 当前下载文件（2026-10-14 清理后）

工作机本地outflow保留五个镜像的下载文件；本仓库云端提供的预编译文件为上方 `releases/image1/` 中的image1版本。
下载路径与历史文件归档位置见 [下载文件清单](docs/download-files.md)。
历史阶段说明中的专用 bit、失败构建和旧多镜像文件均已归档，当前下载以此清单为准。

### image2：彩色、灰度与完整 Canny 去斑拍照（2026-10-22）

V 回复 2；C/G/E 选择照片类型，小写 b 拍照。G/E 先做 2×2 灰度均值采样，
支持中值滤波；E 在 DDR 中完成整帧强弱边缘连接及小连通域去斑，然后保存
960×540 黑白 RGB565 BMP。M 开关中值，D 循环去斑级别，N20/H60/L30 加回车
分别设置小连通域像素数、高/低阈值。保存后自动查看新照片，x 退出，原双确认删除保留。
使用、处理时间和测试说明见 [image2 Canny 拍照](docs/image2-canny-photo.md)。

### image5：去噪灰度 Canny

从 image1 移植摄像头、灰度和 Canny 通路，新增 Canny 前置中值滤波及两级碎边清理，
上电显示黑底白边，默认阈值 60/30。V 回复 5；C/G/E 查看彩色、灰度、二值边缘；
M/D 分别切换中值和碎点清理，H/L 加回车调阈值。
保留自然轮廓，不做人形补画或姿态匹配，较长背景轮廓仍可能保留。
操作、处理细节和验证见 [image5 灰度 Canny](docs/image5-canny.md)。
FT232H 已按最终交接包接入 image5：P3 用于异步 FIFO，SPI/SD/KEY 约束迁到 P4；
`!1` 计数测试、`!2` 灰度、`!3` 1bpp 边缘、`!0` 停止，支持 320/640/1920 三档。
电脑端工具和联调步骤见 [image5 FT232H 通信](docs/image5-ft232h.md)。
2026-10-26 已开启按键和 ADC 采集；`!A` 单次查询，旋钮不改阈值，OLED/SD 关闭，
详见 [image5 外设接入](docs/image5-inputs.md)。

### image4：白背景上半身骨架

独立 image4 保留白背景分割、选区、120×68 掩膜细化和短枝清理，
第二部分加入躯干主路径及每侧至多一条手臂路径的结构约束；背景细节/进一步去影留待第三部分。
U3/U4/U5 查看同快照掩膜、原始骨架及叠加，新增 U6 以绿/青/紫红显示躯干/画面左臂/右臂。
V 回复 4，SKEL 状态新增 BODY/ARM；上电静默，U6 开启后每约 2 秒报告，退出 U6 停止，# 随时查询一次。
关闭 N/2 弱前景补回，默认 N24，测试可发 N60 加回车。
结构路径只取现有骨架像素，不补画缺失部位；尚未增加肩肘腕关节点和动作判定。
26,559 XLR / 222 RAM10 / 33 DSP；仿真和全部 28 项 setup/hold 检查通过，本次串口修改尚未上板。
操作、限制与回退见 [image4 骨架说明](docs/image4-skeleton.md)。
image1～image3 的源码和下载文件保持原样，多镜像 Flash 配置未扩展。

### image1：边缘检测前置中值滤波

2026-10-23 将 `M` 正式接到Canny入口，`E`、识别和分屏右侧现在使用可开关的
3×3中值预滤波；RGB梯度输入与原始灰度分屏同步对齐，`O` 同时支持RGB逐通道中值。
操作、验证和回退见 [image1前置中值说明](docs/image1-median-canny.md)。
实板花屏反馈后的固定延迟与显示同步修复见 [image1显示修复](docs/image1-display-fix.md)。

### image1：屏幕左上角文字菜单

长按 KEY1 打开/关闭菜单，KEY2/KEY3 上下选择，短按 KEY1 进入/确认；
数字项用 KEY2/KEY3 ±1 细调、旋钮粗调。菜单直接复用串口同一组参数寄存器，
叠加在最终 HDMI 画面之前，VS/HS/DE/RGB 统一延迟三拍，不改行宽和场周期。
image1 默认 Canny 25/8、白平衡 R/G/B=496/416/313、Gamma ON 强度 255；
旋钮不再直连 Canny，只有菜单里的 CANNY 项进入 EDIT 后才调阈值。
操作、实现和验证见 [image1 屏幕菜单](docs/image1-menu.md)。

### image1：检测框中文标签

开启 `D` 形状识别后，两个目标按各自分类在检测框旁显示“检测到圆形”
或“检测到矩形”，文字颜色跟随框色，使用深色底并在屏幕边缘自动避让。
实现、验证与备份见 [image1 中文标签说明](docs/image1-shape-labels.md)。

### image1：ADC 旋钮与分压按键

MCP3202 两路各采样 1 kHz：CH0 旋钮八点平均后用于菜单滚动和菜单内数值调节；
image1 已关闭旋钮直连 Canny（`KNOB_DIRECT=0`），上电保持高 25 / 低 8，
只有菜单 `CANNY`/`CANNY H`/`CANNY L` 进入 EDIT 后才通过菜单写入调阈值；
ADC 数值不自动发串口。
CH1 分压按键中值滤波和 20 ms 消抖；SW2/SW3/同时按下分别单次输出
`key  2` / `key  3` / `key  2+3`，原独立 GPIO 按键仍输出 `key  1`。
操作、原理图、参考项目和验证见 [image1 ADC 说明](docs/image1-adc.md)。

### image1：按键消抖与串口单次显示

外接按键 `key`（P4-37 / A2 / GPIOL_N_18）按下稳定 20 ms 后，串口发送一行 `key  1`。
长按不重复，松开稳定 20 ms 后可再次触发，沿用 115200 / 8N1。
见 [image1 按键测试说明](docs/image1-key-uart.md)。

### image3：串口调 Canny 阈值（ADC 已关闭）

2026-10-20 按用户要求关闭 image3 的 `ENABLE_ADC`。旋钮不再控制阈值，
Canny 默认高/低阈值为 0/0，保留 H/L、加减及 R 串口调节和帧边界更新；R 恢复 0/0。
人体 R 背景差分仍由 N 命令设置；image1 的 ADC 功能保持开启。
开关状态和此前移植记录见 [image3 阈值控制说明](docs/image3-adc-threshold.md)。

### image3：固定背景与人体候选 ROI

当前为上半身匹配版：镜头只需拍颈部以下至腰部附近，保留双臂与手，不要求头和腿入镜。
原差分模式增加颜色/光照处理：Bayer 颜色差异、边缘带整体曝光估计和适度灰影抑制，默认开启，`~` 切换 0/1。
新增白布模式：`%` 切换，回复 1 启用、0 返回原差分；白布模式自动估计边缘白布，无需先 b 采集背景，仍使用填充掩膜匹配。
五类上半身填充掩膜 IoU 为主、同快照 Canny 边界覆盖辅助确认，
连续三个完成快照确认后通过 UART 立即报告，并每 0.5 秒重复发送当前姿态及分数；
识别丢失时报告一次 POSE:0 后停止循环，`#` 可查询，V 回复 P（此前白布版回复 W，光照版回复 L，上半身版回复 U，全身版回复 9）。
HDMI 继续显示原有诊断画面，尚未增加骨架/姿态文字；未执行本次板上下载。
当前五类模板已替换为用户实拍照片的实心上半身轮廓，来源、限制和操作见 [image3 实拍模板](docs/image3-photo-templates.md)。
固定彩色背景、投影处理和现场对照见 [image3 光照与阴影抑制](docs/image3-lighting.md)。
白布取景、无需背景采集的操作和资源评估见 [image3 白背景分割与掩膜匹配](docs/image3-white-background.md)。
匹配架构与此前全身版验证见 [image3 姿态匹配](docs/image3-pose-matching.md)。

此前 R 优化版大写 V 回复 8：R 定位、双阈值连接、小孔洞修补、U6 显示 ROI 内真实 Canny。
关闭 E 背景差分和灰度显示中值滤波，保留普通 Canny、彩色/灰度预览、冻结和 R 的 U1～U5。
最新文件为 `Ti60_Image3_Pose_checked.bit`，包含 R 优化，ADC 已关闭；资源裁剪对照版 V=7 已归档。
操作、资源和验证见 [R 优化与 Canny ROI 预览](docs/image3-r-refine.md)。
X/O/S/M 在这两个 R 配置中回复 `!`；普通 E 边缘显示继续工作。
历史 V6 E 读回修复见 [E 读回复位修复](docs/image3-e-read-reset.md)，V5 CRC 字段见
[冻结 E 差分定位](docs/image3-e-static-audit.md)。
此前容差版本记录见 [E 背景边缘容差与操作](docs/image3-edge-tolerance.md)。
此前 `u1` 加回车误改 Canny 阈值的修复仍保留，阶段记录见
[U 命令修复与操作](docs/image3-u-command-fix.md)。
独立 `image3_platform.v`、I 查询实际入口、J 查询 E 差分像素/流错误仍保留，
此前接线修复记录见 [E 接线修复与现场诊断](docs/image3-e-wiring-repair.md)。

此前阶段增加 RAW / E 二值边缘双入口，默认 RAW；串口 `X` 回复 `R/E` 切换，
`b/Q` 分别采集/查询当前入口背景，`U` 保留五个诊断视图。
历史说明见 [RAW/E 双入口](docs/image3-dual-input.md)，阶段下载文件为
`images/image3_pose/outflow/Ti60_Image3_RAW_E_checked.bit`。
下方单 RAW 记录保留作阶段追溯。

独立入口 `images/image3_pose/Ti60_Image3_Pose.xml` 现在增加固定 RAW 背景采集、
差分去噪、前景片段选择/合并、候选掩膜、稳定 ROI 与掩膜边界显示。
保留原相机、DDR、RGB、Canny、HDMI、UART、冻结和测试图；该段为此前无匹配阶段的历史记录。
见 [image3人体候选ROI操作与验证](docs/image3-person-roi.md)。
构建使用 `tools/build-image.ps1 -Image 3`；本轮下载文件为
`images/image3_pose/outflow/Ti60_Image3_PersonROI_checked.bit`。

### 独立工程入口

镜像 1 使用 `images/image1_vision/Ti60_Image1_Vision.xml`，保留当前图形识别；
镜像 2 使用 `images/image2_photo/Ti60_Image2_Photo.xml`，开启 TF 初始化、
DDR 拍照保存和相册读取，排除 Canny/图形识别。
镜像 3 使用 `images/image3_pose/Ti60_Image3_Pose.xml`，当前为 Canny、固定背景候选 ROI 与五类姿态匹配。
三个工程共用基础代码，但各自
编译、检查时序并生成独立 `*_checked.bit`，不能用串口直接切换。
本阶段只做 JTAG 测试，不烧写板载 Flash。原工程作为兼容入口保留。
见 [独立镜像的编译、下载和测试说明](docs/dual-images.md)。

镜像 1 新增串口 `|` 切换同画面左灰度/右 Canny 边缘分屏（返回 1/0）；
C/G/E/S/O/T/D 返回原有全屏模式。用少量行缓存对齐高斯前原始灰度，不新增帧缓存。
O 模式新增顶部启动假边缘保护：保留背景和完整时序，顶部少量行不做边缘着色。

镜像 2 支持小写 d 删除当前相册照片，完整确认提示发出后 5 秒内再次 d 才执行。
翻页/退出/超时取消，忙时拒绝；部分修改失败锁定存储。
见 [照片删除说明](docs/photo-delete.md)。本功能真实修改 TF 文件，实板测试前先备份。

镜像 2 已修复 generated scope 内未驱动的 Gamma 视频输入，正确保留照片
采样器和 13 RAM 的捕获 FIFO。请使用修复后的 checked.bit；旧错误文件已
移到镜像 2 outflow/invalid_937fcfb/，不要下载。镜像 2 现在使用 seed=4，
不是旧的 seed=3；资源为 21,422 XLR / 94 RAM10，完整网表及时序检查通过。

以下资源/时序描述是拆分前兼容工程的历史记录；新镜像以各自报告为准。

### Current profile: legacy Canny / shape-only test (2026-10-11)

#### Video tearing diagnostics (compiled and timing-checked)

Pre-change checkpoint `3488b5b` was pushed to GitHub. A new `Z/z` command
toggles an independent HDMI test generator (`1`=test, `0`=normal). It generates
fixed red/green/blue/yellow quadrants, a white outer border and a white centre
cross, with its own 1920x1080 / 2200x1125 counters. RGB, DE, HS and VS switch
together during common vertical blanking; normal video gets no extra latency.
This bypasses camera, DDR and all vision algorithms but still uses the pixel
PLL, TMDS encoder and physical HDMI output. C/G/E/D/F do not exit test mode;
send Z again to return. This is a diagnostic, not a claim that tearing is fixed.

If the fixed pattern is stable while normal video moves, investigate acquisition
and DDR read/write/frame/FIFO alignment. If the fixed pattern also moves, inspect
PLL, HDMI timing/serializer/output and board connections. A short relock while
changing video sources is possible; sustained movement is the fault of interest.

Use `tools/build-video-checked.ps1` with Efinity's GUI project closed. It rejects
an unexpected PNR recipe, stale reports, compile failures or any negative
constrained setup/hold slack, and only then exports a separate
`outflow/Ti60_Demo_video_checked.bit`. The generic `.bit` may be overwritten by
GUI recompilation, including a run with failed timing; do not substitute it
for the checked file. A failed run does not overwrite a previous checked file.
The diagnostic build passed full compile/export with TIMING_2, seed 3, effort 2:
45,563 / 60,800 XLR (74.94%), 177 / 256 RAM10 (69.14%), 12 / 160 DSP (7.50%).
At the unchanged 148.810 MHz pixel constraint, setup slack is +0.093 ns and
hold slack +0.028 ns; all listed constrained setup/hold relationships pass.
The checked image matches the exported bitstream byte-for-byte. UART/freeze
and 32x24 plus full 1920x1080 diagnostic tests pass, including six full frames,
exact DE counts and common-blanking-only entry/exit. The Canny/shape algorithms
are unchanged from checkpoint 3488b5b. Real-board tearing diagnosis remains
pending: first test Z=1, then Z=0/C, and report which picture is unstable.

This comparison image restores the saved legacy vision chain from checkpoint
`1cb7be0` (vision logic matches `938d3f6`, with games removed).
There is no exact 12:17 Git checkpoint: this is the saved nearby algorithm,
not a claim that the entire old bitstream is reproduced.

Top-level defaults are `PHOTO_TF_BUILD=0` and `ENABLE_PHOTO_TF=0`.
Native SD4 initialization, FAT32 save/read, photo capture/staging and gallery
display are excluded by generate gates. The SD clock is held low and CMD/DAT
output drivers are disabled. No card files are deleted or formatted.
Live camera RAW DDR buffering, HDMI, freeze and AXI video recovery remain.

- Download the checked `outflow/Ti60_Demo_video_checked.bit` through temporary JTAG.
  Send `E`, then `D` once to test grayscale Canny recognition.
- Default display is E; shape overlay starts off. `C/G/E/O/T`, white balance,
  Gamma, thresholds `H/L`, line support `K0..K3`, `Q` and freeze `F` remain.
- Standalone Sobel stays compile-disabled; `A/V` always reply `C`.
- `i/I`, lowercase `b`, `x/X`, `<` and `>` each return `!` without requests.
- Legacy `M` controls the G-mode grayscale display median only, not Canny.
  Canny retains its fixed Gaussian stage. In G/E, its RGB inputs all contain Y;
  in C/O, the legacy colour-gradient behavior remains display-dependent.
- Closing, central ROI, two-object CCL/classification and SHAPE/SHAPE2 reporting
  remain. Hough x-only sampling and combinational tolerance match the reference.
  Classification criteria are not retuned; the reference score/result-valid
  timing behavior is also retained for this comparison, not repaired.
- Games, background subtraction and person segmentation remain excluded.

Tests: `tools/test-controls.ps1` and `tools/test-canny-vision.ps1`.
The newer histogram pair-sampling fixture and gray/M-to-Canny fixtures are not
applicable to this rollback; they are not claimed as passing legacy tests.
Generic storage source/tests are retained for recovery but are not instantiated
in the current image. This is a single JTAG image, not a multi-image Flash build.

Pre-diagnostic legacy-profile build: 45,191 / 60,800 XLR (74.33%), 177 / 256 RAM10
(69.14%), 12 / 160 DSP (7.50%). At the unchanged 148.810 MHz pixel constraint,
setup slack is +0.277 ns and hold slack +0.027 ns. All listed constrained
setup/hold relationships pass. PNR uses TIMING_2, seed 3, effort 2; seed 1
TIMING_1 had -0.096 ns setup slack. UART/freeze and eight vision regressions
passed. Board programming and real-scene recognition remain user tests.

Pre-change local checkpoint: `4079ba7`. GitHub push failed; the user approved
continuing with the local backup. The extra gray/M-to-Canny module and its
two fixtures were removed for rollback and can be recovered from this checkpoint.
Everything below documents historical versions, not this current profile.

2026.9.2
当前状态是精简了代码，删掉了官方例程里面没用的外设接口与内部一些看不懂的东西。然后加上了板载uart，实现串口通信。当前状态是能够做到显示器直接显示摄像头拍到的画面+0

2026.9.3.  17：28
实现了灰度显示，且可以通过串口发送t来进行彩色模式和灰度模式的切换。接下来加边缘检测，加边缘检测之前commit了一次。

2026.9.3   18：16
实现边缘检测了，然后可以调节阈值，通过串口发+与-来调节，也可以直接发数字直接实现阈值的更改。

2026.9.3
增加了 Debayer 后的 RGB 白平衡模块。上电默认增益均为 256（1.0 倍），因此默认画面与修改前一致。串口命令如下：

- `WR384` 后按回车：红色增益设为 384（1.5 倍）
- `WG256` 后按回车：绿色增益设为 256（1.0 倍）
- `WB224` 后按回车：蓝色增益设为 224（0.875 倍）
- `WD`：三个通道恢复为当前工程默认值 335/248/280

白平衡增益采用 Q8.8 格式，支持 0～2047，数值 256 代表 1.0 倍。设置成功时串口返回 `K`，`WD` 返回 `W`。

同日增加可调强度的 Gamma 2.2 校正模块，位置为“白平衡之后、灰度与 Sobel 之前”。经实机调试后，上电默认白平衡设为 `WR335 / WG248 / WB280`，Gamma 默认打开，强度为 `P42`。

- `Y`：切换 Gamma 2.2 开关；串口返回 `1` 表示已打开，返回 `0` 表示已关闭
- `P0`～`P256` 后按回车：设置 Gamma 强度，返回 `K`；0 为不校正，256 为完整 Gamma 2.2
- Gamma 强度上电默认值为 42，Gamma 开关默认为打开
- 可发送 `C` 切到彩色画面，再用 `WR`、`WG`、`WB` 命令继续微调（每条数字命令后按回车）
- 可用 `P0`～`P256` 调整 Gamma 强度；`Y` 用于临时关闭或重新打开 Gamma
- `WD` 可随时把三个白平衡增益恢复为 335/248/280

上述 384/256/224 只是根据当前偏青照片给出的起始调试值，不是最终标定值。最终增益需要在同一光源、同一显示器设置下观察白色或灰色物体后确定。

2026.9.4
增加了可选的灰度 3×3 中值滤波，放在灰度转换之后、Sobel 之前。算法使用固定比较网络和三级流水线，每时钟可处理一个像素；代码拆分为排序单元、中值核和视频流封装，便于阅读与复用。当前工程上电默认打开，可通过串口关闭后进行效果对比。

- `M`：切换中值滤波；串口返回 `1` 表示打开，`0` 表示关闭
- 灰度模式下可直接观察去椒盐噪声效果；Sobel 模式会使用滤波后的灰度图作为输入
- 普通彩色直通模式 `C` 不经过中值滤波；彩色边缘叠加模式 `O` 在 2026.9.5 的后续版本中增加了 RGB 中值预滤波
- 新增文件：`median3x3_sort3.v`、`median3x3_kernel.v`、`median3x3_filter.v` 和自检测试 `median3x3_kernel_tb.v`

2026.9.5
增加基于现有四帧 DDR 缓冲的单帧冻结功能。冻结时只锁定显示端使用的完整帧索引，摄像头采集和 DDR 写入仍继续运行；解除冻结后在下一显示帧边界恢复最新完整帧，避免半帧切换。

- `F` 或 `f`：切换冻结/实时显示
- 返回 `1`：已经进入冻结状态
- 返回 `0`：已经恢复实时显示
- `F` 不占用现有 `M`、`Y`、`P`、`W*`、模式和阈值命令
- 当前版本只包含单帧冻结，不包含回放、多帧选择或分屏对比

同日将模式 `O` 的固定红色边缘叠加升级为 RGB 彩色边缘叠加。模块使用一个 24 位共享 3×3 窗口，分别对 R/G/B 三通道执行 Sobel 检测，并将三路边缘合并后叠加到原始彩色图像：涉及黑色的边界显示为白色，强色差边界显示为黄色，其余边界显示中心像素的补色。阈值继续使用原有 0～2047 的 UART 设置；彩色判决采用分级流水线，避免在 148.5 MHz 像素时钟下形成过长组合路径。

随后为模式 `O` 增加 RGB 三通道 3×3 中值预滤波。三个通道共用一套 24 位行缓存以保证像素严格对齐，再分别使用精确中值核；滤波结果进入彩色 Sobel 与叠加模块。`M` 现在同时控制灰度/Sobel 分支和彩色边缘叠加分支的中值滤波，上电默认打开；关闭时彩色分支保持原始直通输入。

同日增加一套与现有 Sobel 并存的流式 Canny 边缘检测链路，便于实机对比后再决定是否删除 Sobel。Canny 链路按照“3×3 Gaussian 滤波、Sobel 梯度幅值与四方向量化、非极大值抑制、双阈值分类、3×3 八邻域滞后连接”分级流水实现；不使用除法器、反正切、平方根或厂商专用 CORDIC。梯度幅值保持 11 位 `|Gx|+|Gy|`，高、低阈值可通过 UART 分别设置，并自动维持低阈值不大于高阈值。

- 上电仍默认使用原有 Sobel，确保原功能不变
- `A`：切换模式 `E/S` 的灰度边缘算法；返回 `C` 表示 Canny，返回 `S` 表示 Sobel
- `V`：切换模式 `O` 的彩色叠加算法；返回 `C` 表示亮度 Canny，返回 `S` 表示 RGB 三通道 Sobel
- `A` 和 `V` 互相独立，算法选择与其他图像参数一样只在帧边界生效
- `H120` 加回车：把 Sobel/Canny 高阈值设为 120；裸数字加回车仍兼容为高阈值设置
- `L40` 加回车：把 Canny 低阈值独立设为 40；若输入值高于高阈值则自动钳位到高阈值
- `+`、`-` 调整高阈值，`R` 同时恢复高、低阈值默认值（image1 当前为 17、8；本节早期版本为 45、22）
- Sobel 与 Canny 彩色叠加采用相同着色规则：黑色相关边界为白色、强色差边界为黄色，其余边界为中心像素补色；Canny 固定红色叠加已取消
- Canny 使用标准 Gaussian 预滤波，不与 `M` 控制的中值滤波串联；Gaussian 会对灰度与 R/G/B 三通道同时平滑，随后以三通道中最强梯度判定边缘与方向，因此可检测亮度相近的纯色差边界；Sobel 分支继续保留原有中值滤波行为
- 当前滞后连接是适合实时视频的单遍3×3局部八邻域版本，不是需要整帧迭代的递归连通版本
- 新增 `gaussian3x3_filter.v`、`canny_gradient.v`、`canny_nms.v`、`canny_double_threshold.v`、`canny_hysteresis.v`、`canny_edge.v`、`rgb_edge_colorizer.v` 以及对应自检测试

2026.9.20
增加白纸黑线形状识别链路，并按赛题要求以边缘检测作为正式入口。处理流程为“灰度预处理、Sobel/Canny边缘检测、3×3短缺口闭运算、流式连通域分离、轮廓几何特征分类、灰度/彩色背景上的红色细边缘与彩色框显示”。连通域采用LinkRunCCA派生的单遍游程/链表结构，不需要保存完整1080p帧；形状识别没有绕过已有边缘检测链路。

- `D`：打开或关闭形状识别显示；返回 `1` 表示打开，`0` 表示关闭
- `A` 同时决定形状识别采用Sobel还是Canny边缘图；`H` 调整公共高阈值，Canny模式还可用 `L` 调整低阈值
- `B96` 黑色阈值命令为早期阈值分割实验保留，当前正式的边缘形状识别链路不使用该参数
- 连续3帧识别为同一种图形后，串口会立即上报，并以每秒2次的频率重复发送 `SHAPE=RECT` 或 `SHAPE=CIRCLE`
- `Q` 或 `q`：立即查询识别状态；可能返回 `SHAPE=RECT`、`SHAPE=CIRCLE`、`SHAPE=NONE`（没有包围框）或 `SHAPE=WAIT`（有目标但尚未稳定分类）
- 自动上报仅在 `D` 已打开时工作；查询命令始终可用。每条消息都以回车换行结束，VOFA+应使用原始文本接收显示
- 识别处理画面中央三分之二区域，即 `x=320..1599、y=180..899` 的1280×720 ROI；ROI边缘保留4像素余量，HDMI上的紫色框显示识别范围
- 检出的原始细边缘显示为红色；绿色框表示矩形，青蓝色框表示圆形，黄色框表示首帧尚未完成分类
- 上电默认关闭形状识别，不改变原来的 `C/G/E/O` 显示模式
- LinkRunCCA会分别输出各个边缘连通域；目标选择器过滤碰边和过小轮廓，并选择包围框面积最大的有效轮廓，独立黑点不会再把主目标包围框拉大
- 空场景抑制会过滤接触ROI边缘的轮廓、尺寸小于24×24的轮廓和填充率超过50%的实心干扰；不能确认形状时保持 `SHAPE=WAIT`
- 圆形/矩形分类使用连通域包围框和轮廓特征；圆形要求近似等宽高、径向一致且各方向均有轮廓，矩形统一使用四路并行Hough四线拟合；稳定图形仍经过类型防抖
- 直线拟合模式的每边最小支持量可通过串口设置：发送 `K0`、`K1`、`K2` 或 `K3` 后回车，分别选择包围框短边的 `1/2`、`3/8`、`1/4` 或 `1/8`；默认 `K0` 保持原行为，45°长方形建议先测试 `K2`，`K3` 过宽松时可能增加误识别
- 连通域与圆形/矩形几何判定统一使用3×3闭运算修复后的轮廓，避免斜边断点只被CCL修复、却仍让直线跨度和角点闭合判定失败；HDMI红色边缘显示继续使用未加粗的原始边缘
- 矩形检测采用多边缘点的四路并行Hough/投影拟合：16组候选法向量按交错方式分给4条通道，每条通道每帧扫描1组，并在块RAM直方图中寻找两组平行边；选出最佳方向后再用1帧验证边缘支持长度和交点闭合，两组法向量严格垂直。完整搜索和复核约需5帧；串口 `J0/J1` 仅为兼容保留且均使用该检测器
- 分类结果带有效期：目标消失、处理关闭、连通域包围框明显跳变时立即清除旧类型；连续8帧没有收到新的四路分类结果也会清除，避免识别一次矩形后一直锁存在 `RECT`
- 新增 `linkruncca_core.v`，并更新 `binary_morph3x3.v`、`shape_frame_analyzer.v`、`shape_overlay.v`、`shape_recognition_pipeline.v` 和自检测试 `shape_stage1_tb.v`；LinkRunCCA派生代码遵循LGPL-3.0-or-later并保留原作者和论文信息
- 当前四路检测器版本已通过Vivado Verilog完整顶层编译、45°矩形/圆形判别仿真以及Efinity 2025.2映射和布局布线；映射资源为5933个EFX_ADD、23131个EFX_LUT4、14563个EFX_FF和198个EFX_RAM10，seed=1时`clk_pixel_2x`建立余量为+0.067 ns、保持余量为+0.034 ns，最高分析频率150.308 MHz
### Rectangle detector selection

The shape path now contains four interleaved Hough/projection lanes.  UART
`J0` and `J1` are retained as protocol-compatible aliases and both select the
same detector.  The proven circle geometry is
arbitrated independently and takes priority over the deliberately tolerant
rectangle score, preventing noisy circle tangent peaks from winning RECT.
The lanes evaluate four of the sixteen orientations in parallel per video
frame, fit two parallel line pairs in `a*x+b*y=rho` form, and validate each
lane's winning family on one final frame.  Three sufficiently long, span-derived
closed sides confirm a rectangle.  This restores the field-tested J=0
rectangle tolerance; the separate circle geometry resolves the former circle
false-positive instead of making rectangle acceptance depend on fragile corner
pixels.
Disabling shape recognition with `D` stops and clears the detector.  Target
loss, a significant bounding-box change, or an eight-frame result timeout also
invalidates the published type so a stale result cannot remain latched.  The 3x3
close result is used for CCL and geometric classification, while the HDMI red
overlay retains the original thin edge.  Published shape type uses two-frame
switch hysteresis and a three-frame UNKNOWN hold.  Circle validation requires its outer
radius band to cover at least seven of eight centre-relative sectors.  At least
half of all edge samples must lie in the outer +/-12.5 percent band; this keeps
a thick ring valid when Canny also detects its shorter inner contour.  Radius
is approximated as `max(dx,dy)+3/8*min(dx,dy)`, so the pixel-rate path uses only
subtractors, comparisons and shifts.  This rejects rotated rectangles whose
side-centre and corner radii vary strongly instead of classifying them as a
circle merely because rectangle fitting was inconclusive.

### DDR / TF photo capture and gallery

The live RAW camera ring occupies `0x00000000..0x00ffffff`. Background
subtraction and its RAW background capture/read path have been removed;
`0x01000000..0x013fffff` is now unreserved, not erased. Gallery RGB565 buffers
remain at `0x01400000` / `0x01500000`, and photo capture/save buffers remain at
`0x01600000` / `0x01700000`.

Send lowercase `i` to initialize/check the native 4-bit SD card. Send lowercase
`b` to capture RGB565 into DDR and save a FAT32 BMP: completion replies remain
`DDR_OK` then `tfOK`. Send `x` to enter/leave the TF gallery, and `<` / `>` to
browse saved files. `b` no longer diverts a live RAW frame into a background slot.
`F` still toggles live frame freeze; uppercase `B<number>` is the independent
black-threshold command, not photo capture.

Retired `U/u` returns `!`. Retired `N<number>` is consumed and rejected on
Enter, without accidentally changing the edge threshold. See
[SD4 photo guide](docs/sd4-photo-debug.md) for remaining commands and tests.
