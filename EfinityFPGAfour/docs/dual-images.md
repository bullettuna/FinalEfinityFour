# 独立 JTAG 镜像

image1当前版本已在2026-10-23接入[Canny前置中值](image1-median-canny.md)：
M也控制E、识别、O及分屏右侧，分屏左侧仍为原始灰度。下方原先“M仅G”的说明为历史阶段记录。

image3 已在基础迁移后增加固定背景、前景候选掩膜/ROI/边界，当前操作说明见
[image3 人体候选 ROI](image3-person-roi.md)。下文 image3 基础阶段命令记录保留供追溯。

新增第三个工程入口 `images/image3_pose/Ti60_Image3_Pose.xml`，仅迁移基础Canny视频链路。
其功能、命令及构建说明见 [image3基础移植说明](image3-baseline.md)。下文两个应用
镜像的记录保留；image3当前不输出姿势或骨架。

本阶段不烧写板载 Flash，不支持串口切换镜像，也没有同时运行多个应用。
切换功能就是通过 JTAG 下载另一个镜像，FPGA、摄像头及 DDR 控制器重新启动。

## 工程入口

- 镜像 1：`images/image1_vision/Ti60_Image1_Vision.xml`，顶层 `image1_top`。
- 镜像 2：`images/image2_photo/Ti60_Image2_Photo.xml`，顶层 `image2_top`。
- 镜像 3：`images/image3_pose/Ti60_Image3_Pose.xml`，顶层 `image3_top`，基础移植阶段。
- 共用 `example_top.v` 平台和 `src/`、`pri/`、`ip/` 底层模块。
- 三套顶层使用同一份 112 信号端口和连接定义；外围引脚、PLL、SD4 接线一致。
- 每个工程独立保留外围配置/约束，独立输出到其 `outflow/` 和 `work_*`，互不覆盖。
  如果将来修改引脚或时钟，需要同步审查三个外围配置；不要只改其中一个。

编译前关闭对应的 Efinity GUI 工程，避免旧界面设置覆盖文件。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-image.ps1 -Image 1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-image.ps1 -Image 2
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-image.ps1 -Image 3
```

脚本检查各自的 TIMING_2/effort=2 配方、报告时间和全部列出的约束内 Setup/Hold。
镜像 2 使用 seed=4；镜像 1 顶部彩色边缘保护版使用 seed=6。
现在还必须通过实际综合网表检查：应用 RTL 不能有未驱动信号，拍照
采样器不能被优化掉，照片 FIFO 必须保留 RAM。检查只取 warn.log 中
最后一次综合段，避免 Efinity 追加的历史警告造成误判。
只有编译及非负 Slack 检查通过，才复制出独立的 `*_checked.bit`。
失败不会更新之前的 checked 文件；不要把旧文件当成本次新结果。

## 镜像 1：识别

固定参数 `PHOTO_TF_BUILD=0, ENABLE_PHOTO_TF=0, DEFAULT_VIDEO_MODE=2`。
保留当前灰度/Canny/闭运算/ROI/双目标识别、冻结和 Z 测试图。
识别算法文件保持与备份 78289c6 一致；没有改 Hough 采样或分类阈值。
独立 Sobel、游戏、人物轮廓、背景差分继续关闭。
TF 初始化、拍照 DMA、保存和相册模块在综合时排除。

下载 `images/image1_vision/outflow/Ti60_Image1_Vision_checked.bit`。
先用 C 验证实时彩色画面，再发 E、D（D 返回 1）检查识别；Q 查询。
i/I、b、x/X、<、> 返回 !。M 保持旧版行为：仅 G 灰度显示的中值滤波。

### 左灰度、右边缘分屏（2026-10-13）

串口发一个 `|`（ASCII 0x7C，竖线，不是字母 I）：返回 1 进入分屏，
再次发送返回 0 退出至 E 全屏边缘。C/G/E/S/O/T 或 D 会退出分屏并执行原命令。
进入分屏自动选择灰度 Canny，关闭图形识别叠加；D 可重新进入全屏识别。
上电默认不分屏；? 仍返回基础模式 2，Z 测试图优先，需再发 Z 退出测试图。

1920x1080 同一幅画面左侧 x=0..959 显示原始灰度，右侧 x=960..1919 显示
Canny 黑底白色边缘；不是把两份完整图像缩放排在两侧。左侧是高斯前的
原始灰度，经四级中心像素窗口及对应流水线与 Canny 对齐；现有 Canny
RGB 随路背景已经高斯平滑，不能把它当作原始灰度。新增少量 8-bit 行缓存，
不申请 DDR 或整帧缓存；在边缘流的垂直消隐切换显示。
不修改 Canny/闭运算/ROI/分类器，M 仍不影响 Canny，也不影响分屏左侧原始灰度。
此功能仅镜像 1 及兼容识别入口启用；镜像 2 不综合分屏模块，| 返回 !。
仿真覆盖完整 1920x1080 三帧、分界像素、逐行复位和帧中请求不撕裂。

本次修改前版本 6ee1417 已确认推送备份。新增的原始灰度对齐还分别在 32
和 1920 像素宽度下与实际 Canny 同步逐像素比对，验证三帧原始像素未被平滑。
原 Canny/闭运算/识别算法文件未改，相关回归、串口及冻结回归通过。
最终综合/布局资源：46,479 XLR（76.45%）、185 RAM10（72.27%）、12 DSP；
相对原镜像新增 8 RAM10。分屏选择器本身为 28.5 XLR/0 RAM，对齐器为 691 XLR/8 RAM。

2026-10-13 16:30 导出的最终文件使用 TIMING_2/seed=4/effort=2。seed=3
出现 DDR core_clk->twd_clk Setup -0.027 ns，已拒绝交付；没有放宽时钟约束。
seed=4 的像素 Setup/Hold 为 +0.192/+0.026 ns，DDR 该路径 Setup +0.149 ns，
全部 28 条关系均非负，最小 +0.024 ns。综合、PNR 和导出时间/源码匹配检查通过。
当时导出的 `Ti60_Image1_Vision_checked.bit` 与专用文件
`Ti60_Image1_GrayEdgeSplit_checked.bit` 内容相同，长度 2,889,483 字节，SHA256：
`DFABDBFEC41A7929CBD262E7D4921FB850183CEDC330FCA7E3B4C6DA248B3E5A`。
专用文件用于区分旧下载版本；正常构建脚本继续更新 Vision_checked.bit。
以上为 16:30 分屏版记录；这些下载文件现已由下方 17:02 顶部保护版更新。
旧可用镜像在 `outflow/baseline_6ee1417/` 保留，时序失败文件在
`outflow/rejected_split_seed3/` 标记 DO_NOT_DOWNLOAD。实板验证待 JTAG 下载后完成。
镜像 2 下载文件未改，SHA256 仍为 742C1C4669EBEA08FB3ED88B5074AE82C3AEE3543DFCEE906C02C5C0A74A2E30。

### O 彩色边缘顶部红带保护（2026-10-13）

修改前分屏版 2708c19 已推送备份。用户确认只有 O 有红带，C 普通彩色正常。
代码中 Bayer 前两行是中性灰回退，与后面的真实彩色图像存在边界过渡。
仿真用这个边界构造输入，在原版 Canny + 彩色边缘链路复现了整行红色假边缘：
彩色着色器会对普通边缘取中心 RGB 反色，青色背景的假边缘因此变成红色。
这是可复现的机制，并不是已通过照片/实板测量确认唯一硬件原因。

仅在 image1 的 Canny 彩色着色器开启 TOP_EDGE_GUARD=8：按有效行计数，
前八个 Canny 输出输入行的边缘标签置零，再送入原着色窗口。
该窗口有一行空间延迟，因此显示最上方九行保留原背景、不做边缘着色。
不黑屏/裁切这些行，不改 DE 宽度/高度或 HS/VS，不放宽时钟约束，也不改
Canny、图形识别、二值边缘 E、分屏或 Bayer 插值算法。代价是顶部这个
小区域的真实边缘同样不着色；真实红色背景仍会正常显示。
通用 rgb_edge_colorizer 默认保护关闭，image2 不综合此模块。

新增 canny_color_border_tb 对比保护关闭、保护开启和纯背景三个通路：
32 像素宽度三帧复现 96 个顶部红色像素；1920 像素宽度复现 5760 个。
保护后顶部像素逐一等于纯背景，九行之后逐一等于旧彩色边缘，保留
测试场景正常区域的 3858 个边缘像素，同步/每行像素数/整帧像素数不变。
相关 Canny、灰度、闭运算、Hough、着色和原始灰度对齐回归通过。

最终使用 TIMING_2/seed=6/effort=2，原时钟约束未变；seed=4/5 分别有
DDR Setup -0.002/-0.009 ns，均拒绝交付。seed=6 的像素 Setup/Hold 为
+0.168/+0.026 ns，DDR core_clk->twd_clk Setup +0.138 ns，全部 28 条约束
内 Setup/Hold 非负，最小 +0.020 ns；最新综合网表及源码/导出时间核对通过。
资源 46,317 XLR（76.18%）、185 RAM10（72.27%）、12 DSP，没有新增 RAM。

2026-10-13 17:02 导出 `Ti60_Image1_ColorEdgeTopFix_checked.bit`，长度
2,887,236 字节，SHA256：
`6C2CE01708B5F90D1349C46160B9D24D72CC3C25FF8948341910B07D0F0AAC0B`。
Vision_checked.bit、GrayEdgeSplit_checked.bit 已同步为相同内容，分屏依旧可用。
旧分屏版保留在 outflow/baseline_2708c19/；没有下载到实板或烧写 Flash。
实板请用新 bit 经 JTAG 下载后发大写 O 检查。image2 文件/功能未改。

## 镜像 2：拍照与 TF 相册

2026-10-22 已升级为 C 彩色、G 灰度、E 完整 Canny 去斑拍照；G/E 保存后自动查看
刚保存的照片。新增 M、大写 D 循环三档、N 像素门限、H/L 阈值控制，照片仍为
960×540 RGB565 BMP。小写 d 双确认删除保留。最新操作和验证见
[image2 Canny 拍照](image2-canny-photo.md)。下列“不综合 Canny / G 仍保存彩色”
等内容仅是 2026-10-11 原版记录，不再描述当前 image2。

### 2026-10-11 原版记录

镜像 2 新增当前照片删除：相册加载完成后发小写 d，收到 DEL_CONFIRM 文件名，
5 秒内再发 d 确认。翻页/退出/超时取消；忙时拒绝。成功后刷新相册，
最后一张删除后报告 ALBUM:EMPTY 并回到实时画面。
见 [删除操作、安全限制和失败处理](photo-delete.md)。先备份 TF 中的重要照片。

固定参数 `PHOTO_TF_BUILD=1, ENABLE_PHOTO_TF=1, DEFAULT_VIDEO_MODE=0`。
不综合 Canny、闭运算、CCL、形状分类器和 SHAPE 串口报告器。
沿用已保存的原生 SD 4-bit 主机、FAT32 写入/读取、DMA、错误恢复和相册链路。
拍照 RGB 来自白平衡/Gamma 后、灰度显示选择前，并使用同一阶段的 VSYNC/DE；
选择 G 只改变显示，不会把保存的照片变成灰度。

下载 `images/image2_photo/outflow/Ti60_Image2_Photo_checked.bit`。
在同一块已经使用原生 SD4 的卡上正常重新初始化即可；如果此前用过 SPI
初始化程序，需要先让 TF 卡真正断电再上电，避免旧 SPI 会话残留。

1. 上电默认 C 彩色显示，先确认没有闪屏/错位。
2. 发 i，收到一次 TF:INIT_OK。
3. 发 b，依次等待 DDR_OK、tfOK，中途不重发 b。
4. 移动摄像头/目标，再拍第二张。
5. 发 x 进入相册，等待 ALBUM:READY；<、> 上一张/下一张。
6. 再发 x 退出；可用 G 显示后拍一次，确认保存仍是彩色。

支持 C/G，T 只在彩色与灰度之间切换；F、白平衡、Gamma、Z 仍可用。
E/S/O/A/V/M/D/Q/J 返回 !；H/L/K/B 数字前缀消费到回车并拒绝。
小写 b 是拍照；WB/b 的白平衡通道选择不会误触发拍照。
SD 操作期间的 BUSY、超时、失败回执和保存后缓冲所有权策略保持原实现。

TF 卡必须是保存器支持的 FAT32 格式。i 成功不代表 FAT32 格式检查通过。
不会自动格式化或删除已有文件；文件命名为 IMG00001.BMP 等。
照片为 960x540 RGB565 BMP；DDR 使用专用双缓冲，与实时 RAW 环形缓冲分开。
DDR 所有权在下一张完整采集后释放，释放是允许覆盖而不是擦除。
JTAG 切换后不保证 DDR 照片/冻结状态保留，已成功存入 TF 的文件保留。

## 回归及回退

### 镜像 2 输入作用域修复（2026-10-11）

旧镜像 2 的 generate 块在顶层声明之前引用了 w_gamma_*，形成五个
没有驱动的局部信号。SD 初始化仍正常，但拍照没有帧/像素输入，
两秒后 DDR_FAIL 并保持 FAULT:RESET_REQUIRED。已把六个 Gamma 视频信号
提前声明到模块级；没有修改 SD 协议、照片格式、DMA 算法或镜像 1 的识别算法。

旧错误 checked.bit 已移至 `images/image2_photo/outflow/invalid_937fcfb/`，
文件名标记 SCOPE_BROKEN_DO_NOT_DOWNLOAD，不要继续使用。新的 checked.bit
只有通过完整编译、实际连接/采样器/缓存检查和全部时序检查才会生成。
修复前本地备份为 937fcfb；GitHub 推送失败，用户授权使用本地备份继续。

新增 tools/test-photo-capture.ps1 使用实际 1080p 输入和约 148.8/96 MHz 双时钟，
逐像素验证 960x540 RGB565、64,800 个 DDR 数据字、8,100 个突发写入，
覆盖地址/数据停等、整帧完成和灰度显示不影响彩色采样。
原 SD4 保存/相册/超时恢复回归也重新执行。这些仿真不代替实板验证。

修复后的最终镜像 2 已完成编译和导出，28 条约束内 Setup/Hold 均非负：
21,422 XLR（35.23%）、94 RAM10（36.72%）、21 DSP。
像素 Setup +1.235 ns、Hold +0.026 ns；DDR core_clk->twd_clk Setup +0.134 ns；
全部约束内关系最小 Slack 为 +0.017 ns。seed=3 的正确连接版本存在
DDR Setup -0.108 ns，已拒绝交付；最终使用 seed=4，没有放宽时钟约束。
实际采样器保留 78 XLR，照片 FIFO 保留 13 RAM；这 13 RAM 在旧错误文件中
被优化掉，因此旧资源数字偏低。综合网表检查已确认能拒绝旧未驱动信号，
即使不看旧警告，也会拒绝缺失采样器的旧网表。

新 `Ti60_Image2_Photo_checked.bit` 的 SHA256：
`6F1950D904C46AC6548A189F10FB2E4C36E74C4AEBD65641E297FD9340896CEA`。
2026-10-11 16:35 更新，文件长度 2,436,432 字节，与本次原始导出 bit 完全一致。
镜像 1 的已发布 checked.bit 未改，SHA256 仍为下方记录的 952A7B12...。
请重新在 Programmer 选择新 checked.bit 并 JTAG 下载，以清除旧 FAULT 状态；
发 i，再发 b 等待 DDR_OK、tfOK，最后测试 x/< />。不必先自行重新编译。

以下是修复前记录；旧镜像 2 的资源和 SHA256 对应错误文件，已失效。

本次两个工程均完成完整综合、接口、布局布线和 bit/hex 导出。
固定使用 TIMING_2/seed=3/effort=2，像素约束仍为 148.810 MHz：

- 镜像 1：45,628 XLR（75.05%）、177 RAM10（69.14%）、12 DSP；
  像素 Setup +0.068 ns、Hold +0.030 ns。
- 镜像 2：21,023 XLR（34.58%）、81 RAM10（31.64%）、21 DSP；
  像素 Setup +1.236 ns、Hold +0.042 ns。

两边全部 28 条列出的约束内 Setup/Hold 关系均非负，checked.bit 与对应
原始导出文件 SHA256 一致。镜像 1 最小余量为 +0.003 ns（DDR 时钟关系），
仍需上板验证，不把“软件通过”当作所有硬件条件下稳定运行的保证。
串口两种配置、冻结、诊断图、灰度/Canny/形态学/Hough，以及完整 SD4
初始化/保存/相册/超时重试回归均通过。SDHC、SDSC v2 和旧 SDSC 模型都覆盖；
相册回归逐字节验证 BMP 保存到 FAT，再回读、DDR 写入及 RGB565 显示。

下载文件 SHA256：

- 镜像 1：`952A7B12C071318D7A55B159B0C18EF444F1B9E67977FA63FB10227E3F709707`
- 镜像 2：`806CD1BE5BBC8ADA8002D2B986DE1834BEA50139342F2F674A0B9CE47F928955`

运行 tools/test-controls.ps1、tools/test-canny-vision.ps1、tools/test-sd4.ps1。
回归模型不等于物理 DDR、SD 卡或 HDMI 上板验证，两个新镜像均需实机测试。
改前版本已备份到 GitHub：78289c6。原有正常下载文件另存于
`outflow/baseline_78289c6/Ti60_Image1_baseline.bit`，对应 SHA256：
`D84D47B2BC6D01B938FBE2ACC4CEEBE768D9D84635F3CF5B36EAE105008EF9F4`。

后续再单独实现 Flash Remote Update、双向串口切换和保存忙时禁止切换。
