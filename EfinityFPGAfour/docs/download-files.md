# 当前下载文件

2026-10-26 23:48:07：image1更新为最终P4扩展板版，独立键P4-37、ADC SPI P4-13/14/17/18，FPGA侧1.8V。
保持17项菜单和H25/L8等默认值；TIMING_2/seed17，28项setup/hold通过，全局最小+0.020ns。
文件/接线/测试见 [image1 P4输入](image1-p4-inputs.md)；新接线实板验收待进行。

## 2026-10-26 image5：异步 FT232H + 按键/ADC 采集

- JTAG：`images/image5_canny/outflow/Ti60_Image5_Canny_checked.bit`，2,353,278 字节。
- Flash HEX：`images/image5_canny/outflow/Ti60_Image5_Canny.hex`，2,353,338 字节。
- 按键消抖、长按不重复；CH0 旋钮只采集，CH1 分压键单次上报；`!A` 手动查询 ADC。
- 上电 Canny 高/低阈值仍为 60/30，旋钮不改阈值，OLED/SD 关闭。
- 17,714/60,800 XLR，104/256 RAM10，11/160 DSP；28 项 setup/hold 全部通过，最小余量 +0.017 ns。
- checked.bit SHA256：`8058E112629A1C4842D7A7A1C0C7DC62D6DFC9BF896FFC983B0B35ACE44D38C1`。
- HEX SHA256：`D62C092F044C856C385E4C51477C4EBFEB5B6FCC0F7792C0CF4F701AFD273C49`。
- 最终编译完成时间：2026-10-26 19:21:37；本次尚未下载板卡、写 Flash 或进行新外设实测。
- 说明见 [image5 外设](image5-inputs.md)，FT 图像操作见 [异步 FIFO](image5-ft232h.md)。
- 修改前的 image5 bit/hex 已备份到 `E:/Efinity_Project/bit_hex_archive/Image5_before_inputs_20261026.zip`。

## 其他镜像及历史记录

**云端 main 可直接使用：** [image1 checked.bit](../releases/image1/Ti60_Image1_Vision_checked.bit)、[同次hex](../releases/image1/Ti60_Image1_Vision.hex)、[校验清单](../releases/image1/manifest.json)。
拉取后无需编译，操作见 [main快速使用](image1-main-quickstart.md)。下方outflow路径和其他镜像文件是工作机本地构建记录。

当前工程保留五个镜像的最新已检查 bit 和同次导出的 hex，共 10 个文件。
2026-10-24 03:49:53 image1更新为17项文字菜单最终版，默认H25/L8、WB 496/416/313、Gamma ON/255，旋钮只在菜单EDIT中调参。
TIMING_2/seed=14/effort=2，28项setup/hold全部通过，像素+0.060/+0.026 ns，DDR setup +0.023 ns，全局最小+0.022 ns。
当前文件及菜单验证见[image1屏幕菜单](image1-menu.md)。
此前2026-10-23 23:57完成固定延迟/固定HDMI同步相位修复，保留Canny前置中值和双目标中文标签。
旧中值版切M出现44→38拍HS短脉冲已复现并修复；新显示出口不再按模式切换同步相位。
TIMING_2/seed=7，28项setup/hold通过，像素+0.079/+0.010 ns；完整验证与实板状态见
[image1显示同步修复](image1-display-fix.md)。
2026-10-14 初次清理时保留三个镜像，共 6 个文件；2026-10-21 新增独立 image4。
初次清理没有修改 FPGA 功能；随后 image3 于当日 17:41 本地编译更新为 ADC 旋钮阈值版。
2026-10-20 按用户要求关闭 image3 ADC，重新编译并完成临时 JTAG 下载。
同日按用户串口调节记录将 image3 默认阈值更新为 0/0，并重新编译下载。
同日 18:49 编译检查通过 V9 五类姿态匹配版，替换当前 image3 下载文件；本次尚未 JTAG 下载。
同日 21:34 按用户确认改为无头、无腿的上半身匹配，V 回复 U，未上板。
同日 21:42 更新为“识别成功后每 0.5 秒重复报告 POSE”版；保留 V 回复 U，本轮未上板。
同日 22:14 更新为彩色背景/阴影抑制版，V 回复 L；默认开启，可用 ~ 切换。本轮未上板。
同日 22:47 image1 更新为检测框中文标签版，矩形/圆形分别显示“检测到矩形”/
“检测到圆形”，两个目标独立显示；编译、实际网表和全部 28 项建立/保持关系通过。
2026-10-21 00:33 image3 加入白背景分割与掩膜匹配，V 回复 W，% 切换白布/原差分模式；本轮未上板。
同日 00:42 时序复查后补齐背景读开关的双时钟域同步和消隐期就绪更新，重新编译、时序与功能回归通过；V 仍回复 W，未上板。
image2 保留文件未变。
2026-10-21 10:17 image4 新增白背景上半身掩膜骨架版，V 回复 4；image1～image3 六个文件哈希不变。
同日 13:38 image5 新增独立去噪灰度 Canny 实时画面，V 回复 5，默认 E、阈值 60/30、中值/碎边清理开启；image1～image4 八个文件哈希不变。
同日 14:33 image3 五类模板替换为实拍上半身轮廓，V 回复 P；白布/差分、Canny 辅助和周期报告保留，未上板。
同日 15:47 image5 按最终硬件交接包接入 FT232H：P3 同步 FIFO、P4 外设迁移，支持计数包及 320×180 灰度/边缘快照；原 Canny/HDMI 保留，ADC 仍关闭，尚未实板收数。
同日 16:03 image4 按用户授权关闭 N/2 弱前景补回，保留补洞和骨架；V 仍回复 4，默认 N24，上板对照发送 N60 加回车；其余四个镜像下载文件未变。
同日 20:19 image4 新增第二部分上半身结构约束，U6 显示躯干及两侧手臂路径，SKEL 增加 BODY/ARM；保留 U4/U5 原始结果及弱前景关闭配置。第三部分背景细节/进一步去影暂未添加；其余四个镜像未变。

2026-10-22 21:08 image2 增加用户确认的旧 P3 MCP3202 旋钮调 Canny 阈值，
保留 UART 收图和 TF/相册；28 项时序通过，最小 +0.020 ns，未上板。
见 [旧 P3 ADC 方案](image2-adc-p3.md)。

2026-10-22 20:34 image2 增加最终 960×540 Canny 照片 UART 导出与电脑动作分类 PNG 采集，
`:` 回复 U，E/G 后 `@` 抓新帧，无需 TF；28 项时序及完整尺寸协议/像素仿真通过，尚未上板。

2026-10-22 image4 串口改为上电静默；U6 开启后每约 2 秒报告一次，切换其他视图停止，# 保留单次查询。

## JTAG 下载

- image5：`images/image5_canny/outflow/Ti60_Image5_Canny_checked.bit`
  — FT232H 同步 FIFO 版，V=5、!V=F；!1 计数、!2 灰度、!3 二值边缘、!0 停止；USB 快照 320×180。P3/P4 已按最终制板接线迁移，原 C/G/E、M/D、H/L/R、1080p HDMI 保留，默认阈值 60/30，ADC 仍关闭。
  14,977 XLR / 154 RAM10 / 9 DSP；36 项 setup/hold 通过，像素时钟 +1.289/+0.033 ns，FT 采样到发送 +0.932 ns，全部关系最小 +0.026 ns；PNR seed=6。
  完整输入、快/慢延迟角落、背压、CRC/序号/像素、组合串口、原 Canny 回归通过。FT 外部预算另按明确假设检查，实物波形未测。
  说明见 [image5 FT232H 通信](image5-ft232h.md)及[灰度 Canny](image5-canny.md)。本版本未上板，未写 Flash；D2XX 尚未枚举到目标模块，未宣称实板通信成功。
- image4：`images/image4_skeleton/outflow/Ti60_Image4_Skeleton_checked.bit`
  — 自动白背景分割、选区、120×68 骨架细化及短分支清理；U3 掩膜、U4 骨架、U5 同快照叠加，新增 U6 结构约束。
  保留关闭弱前景补回的配置：N60 不再通过 N/2 通道补回相连暗背景，保留选区、补洞和块采样。V=4、默认 N24，测试时手动 N60 加回车。
  无需 b，Q 查询白参考，# 单次查询 SKEL/BODY/ARM 状态；上电静默，仅 U6 开启约 2 秒一次的报告，退出 U6 停止。U6 绿/青/紫红分别为躯干/画面左臂/右臂，未找到部位不补画。尚未增加关节命名与动作识别。
  26,559 XLR / 222 RAM10 / 33 DSP；28 项 setup/hold 通过，像素时钟 +0.754/+0.044 ns，全部关系最小 +0.019 ns；2026-10-22 17:02 导出。
  说明见 [image4 骨架操作](image4-skeleton.md)。本版本未上板，未写 Flash。
- image1：`releases/image1/Ti60_Image1_Vision_checked.bit`
  — 2026-10-26 23:48:07，最终P4扩展板、17项菜单、中值及显示同步修复版。
  KEY1=P4-37；ADC SCLK/MOSI/MISO/CS=P4-13/14/17/18，FPGA侧1.8V。
  H25/L8、WB 496/416/313、Gamma ON/255，旋钮仅在菜单EDIT调参。
  28项setup/hold通过；像素+0.022/+0.027ns，DDR setup+0.064ns，全局最小+0.020ns。
  操作和接线见 [P4输入说明](image1-p4-inputs.md)。按键/ADC与菜单仿真通过，新接线实板操作待验收。
- image2：`images/image2_photo/outflow/Ti60_Image2_Photo_checked.bit`
  — 2026-10-22 更新为彩色/灰度/完整 Canny 去斑拍照，V 回复 2；G/E 保存后自动
  查看刚保存的文件。M 中值、D 去斑档位、N 小连通域像素门限、H/L 阈值可调，
  原 TF/相册/双确认删除和失败重试保留。使用说明见 [image2 Canny 拍照](image2-canny-photo.md)。
  同日复查修复保存完成与 i 初始化重合时自动预览请求丢失；28 项时序通过，
  像素时钟 +1.389/+0.026 ns，全局最小 +0.014 ns。详见 [image2 复查](image2-audit.md)，上述为串口导出前记录。
  当前已更新为 [旧 P3 ADC＋UART 导出版](image2-adc-p3.md)，34,988 XLR / 127 RAM10 / 32 DSP；
  28 项时序通过，像素时钟 +1.033/+0.026 ns，全局最小 +0.020 ns，未上板。
- image3：`images/image3_pose/outflow/Ti60_Image3_Pose_checked.bit`
  — 实拍上半身轮廓匹配版（V 回复 P）：五类模板来自照片7/8/10/9/4。% 启用自动白布分割，无需先 b；上电默认仍为原 Bayer 颜色差分、曝光补偿与灰影抑制。保留背景读开关同步修复、R 优化、Canny 辅助确认、成功时 UART 每 0.5 秒报告与 # 查询；2026-10-21 14:33 导出。
  ADC 关闭，Canny 默认 0/0，由 H/L/R 串口调节，R 恢复 0/0。
  26,048 XLR / 243 RAM10 / 34 DSP；28 项 setup/hold 均通过，像素时钟 +0.886/+0.030 ns，全部关系最小 +0.019 ns。
  说明见 [image3 实拍掩膜模板](image3-photo-templates.md)。本版本未上板，未写 Flash。

## 保留的 hex

- `images/image1_vision/outflow/Ti60_Image1_Vision.hex`
  SHA256：`7e5fdac82413de12dd3bb548bb6e68ad86b2fd317f4bf9cdbeeb5e02e1e5f979`
- `images/image2_photo/outflow/Ti60_Image2_Photo.hex`
  SHA256：`B9851800D3C6EC09E955F7F1CBFE0079DD0060F349BDD4C0E4CE0EA95B6A78ED`
- `images/image3_pose/outflow/Ti60_Image3_Pose.hex`
  SHA256：`69C4CCA3BD91E01BE04BDDD7789F8A30DD23DF75F0F5259031F0853472431673`
- `images/image4_skeleton/outflow/Ti60_Image4_Skeleton.hex`
  SHA256：`DCE88D1C24D6E222644E09916434C4DA3DEA44F4351231548CEA9A00168A8230`
- `images/image5_canny/outflow/Ti60_Image5_Canny.hex`
  SHA256：`464904DF12DD5401ED42B2307D3C819E95F00AF97FE62A50D12E6F8D9A4A9A70`

这些是各镜像单独导出的文件。当前仍按 JTAG 测试流程使用 checked.bit；
未重新生成多镜像 Flash 文件，也未烧写 Flash。

## 历史文件归档

原有 38 个 bit/hex 缩减为 6 个。其余 32 个及旧多镜像生成报告已打包到工程外：

`E:/Efinity_Project/bit_hex_archive/EfinityFPGAfour_20261014_173246.zip`

ZIP 保留原相对路径，包含历史版本、重复副本、失败构建、兼容单工程输出，
以及 2026-10-11 的 `images/multi_image.hex` 和 `.rpt`。
该旧多镜像文件只包含当时的 image1、image2，没有 image3，也没有最新 ADC 阈值功能。
历史说明中的专用文件路径用于阶段追溯；需要恢复时可按归档相对路径提取。

每个归档条目已按长度和 SHA256 验证，再移除工程中的原文件。
归档内 `manifest.json` 和旁边同名 `.manifest.json` 记录原路径、时间、长度及 SHA256。
清理前源码备份提交为 `90bb458`，已推送到 GitHub。

image1 加入中文标签前的 bit/hex、报告和配置另存于：
`E:/Efinity_Project/bit_hex_archive/Image1_before_chinese_labels_391d9f6_20261020.zip`，
文件长度及 SHA256 已与旁边的 manifest 核对；修改前源码为 `391d9f6`，已推送 GitHub。

## 保留 bit 的 SHA256

- image1：`b83befafdb88c5bf8654772ef9a74313ca462b70b8ade3a647083b585b2ca97e`
- image2：`2CA5E869463A8F5396914E9AD114A725E1989430AC9AAAEC2163496F01F1A5E8`
- image3：`2B7A416D227BA012014F3F40BDC033F6EE8B9BD188756D8A4231BA7E4DF4982F`
- image4：`D41BDAF3E4CDFDA2449EEB2D068F590DC3468669811B4D55DF1E15AE5D07AAE8`
- image5：`F6C39CE37D9476278CFB927E02E91499B72C7F3F8CD718B7F37AAF2868071B6A`

此前 00:33 白布版（补齐背景读开关同步前）与报告已归档并核对 bit/hex 哈希：
`E:/Efinity_Project/bit_hex_archive/Image3_before_read_enable_cdc_6f0cf03_20261021.zip`。

替换实拍轮廓前的00:42白布版、模板与报告已归档并核对哈希：
`E:/Efinity_Project/bit_hex_archive/Image3_before_photo_templates_ba042a1_20261021.zip`。

此前 V=L 彩色背景光照抑制版与报告已归档并核对 bit/hex 哈希：
`E:/Efinity_Project/bit_hex_archive/Image3_before_white_391d9f6_20261021.zip`。

此前无光照抑制、每 0.5 秒重复报告 POSE 的上半身版与报告已归档并核对 bit/hex 哈希：
`E:/Efinity_Project/bit_hex_archive/Image3_before_lighting_febd5e0_20261020.zip`。

此前仅变化时发送的上半身版及其报告已归档并核对 bit/hex 哈希：
`E:/Efinity_Project/bit_hex_archive/Image3_upper_change_only_947975e_20261020.zip`。

此前 V9 全身匹配版与其报告已归档并核对原 bit/hex 哈希：
`E:/Efinity_Project/bit_hex_archive/Image3_full_body_c598088_20261020.zip`。

姿态匹配之前的 V8 0/0 阈值版与其报告已另行归档并核对原 bit/hex 哈希：
`E:/Efinity_Project/bit_hex_archive/Image3_before_pose_575274f_20261020.zip`。

下一次完整编译会重新产生工具默认命名的 `.bit` 副本；通过检查后，构建脚本继续更新各镜像的 `*_checked.bit`。

image4 添加结构约束前的弱前景关闭版与报告已归档并核对长度和哈希：
`E:/Efinity_Project/bit_hex_archive/Image4_before_body_constraint_38eee56_20261021.zip`。

image4 串口限流修改前的结构约束版与报告已归档核对：
`E:/Efinity_Project/bit_hex_archive/Image4_before_quiet_uart_570f4ee_20261022.zip`。
