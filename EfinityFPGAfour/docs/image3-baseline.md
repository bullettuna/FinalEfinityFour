# image3 基础逻辑移植

本页记录基础迁移阶段。当前已增加 image3 独立背景、候选掩膜/ROI/边界链路，
新的功能和命令见 [image3 人体候选 ROI](image3-person-roi.md)，以下旧阶段记录不作为当前能力清单。

image3 是边缘主导的多姿势匹配方案的独立工程入口。本轮仅移植已有基础功能，
不实现人体候选筛选、640×360快照、归一化、模板库、匹配器或骨架生成。

## 工程入口

- 工程：`images/image3_pose/Ti60_Image3_Pose.xml`。
- 顶层：`images/image3_pose/image3_top.v`。
- 基础平台：`example_top.v`、`src/`、`pri/`和`ip/`，与image1/image2复用。
- 外围配置和SDC由当前image1复制，保持现有板级引脚、PLL与时钟约束。
- 本轮不改变image1/image2的功能默认值；共享平台新增三个编译参数，image3置0。
- 各镜像在自己的outflow和work目录生成结果，不能通过UART切换镜像。

修改前本地备份提交为`3de7150`。GitHub连接失败后，用户明确授权以本地备份继续。
该提交尚不能称为已完成远端备份。

## 已迁移功能

- SC2210配置、MIPI接收、DDR视频帧缓存及Bayer转RGB。
- 白平衡、Gamma、灰度显示及已有灰度中值滤波。
- 现有RGB梯度Canny：Gaussian、梯度、NMS、双阈值、局部八邻域连接。
- 1080p HDMI、UART参数控制、完整帧冻结、Z独立HDMI测试图。
- 上电显示黑底白色Canny边缘；可切彩色或灰度检查摄像头输入。

编译排除：TF初始化/拍照/相册、Sobel副本、矩形/圆形识别、Hough、形状报告、
彩色边缘着色和灰度/边缘分屏。排除以实际综合网表为准，不是只关闭运行开关。

二值形态学和CCL源代码仍在共享src中可复用，但本轮不接入人体分析链路。
当前CCL只输出包围框，不能直接作为人体掩膜或姿势匹配结果。

## UART（115200，8N1）

- `C`：彩色，返回`0`。
- `G`：灰度，返回`1`；`M`切换灰度显示中值滤波。
- `E`或`S`：Canny边缘，返回`2`。
- `T`：在彩色、灰度、边缘三个模式间循环，跳过已移除的彩色叠加。
- `A`：返回`C`确认Canny，不能切换到Sobel。
- `H120`加回车、`L40`加回车：设置高/低阈值；`+`/`-`调整高阈值。
- `R`：恢复高/低阈值45/22。
- `WR`/`WG`/`WB`数字加回车、`WD`：已有白平衡控制。
- `Y`、`P0..P256`加回车：已有Gamma控制。
- `F`：冻结/恢复；`Z`：切换独立HDMI测试图；`?`查询基础显示模式。
- `D/Q/J/O/V/|`及照片/TF命令返回`!`，不发出形状或照片请求。
- `B<number>`与`K<number>`作为未提供的形状参数，消费到回车后返回`!`，不修改Canny阈值。

`M`只改变G模式的已有中值滤波，不串联到本轮迁移的Canny。边缘图仍含背景和衣服纹理，
不是已经分离出的人体；本轮没有有效姿势编号或骨架输出。

## 构建与检查

关闭对应Efinity GUI工程后，在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-controls.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-image.ps1 -Image 3
```

构建脚本沿用TIMING_2、effort=2、seed=6，并检查新生成报告、综合网表和约束内Setup/Hold。
只有全部通过才复制`images/image3_pose/outflow/Ti60_Image3_Pose_checked.bit`；旧checked文件
不代表本次构建成功。禁止用时序失败的普通bit替代checked文件。

本轮不自动下载JTAG或烧写Flash。上板基础检查顺序：`Z`测试HDMI，再`Z/C`检查相机，
然后`G/E`和阈值命令，最后验证`F`；人体和姿势识别留给后续阶段。

## 后续接入点

`u_platform.w_edge_vsync/w_edge_hsync/w_edge_href/w_edge_pixel`是现有Canny同步和边缘流。
这些是内部网络，供后续RTL接入设计参考，不是现在已新增的外部接口。
先验证基础视频稳定，再新增同帧快照、人体区域、模板归一化和评分模块。

## 本轮验证记录

2026-10-13完成Efinity 2025.2.288完整综合、Interface Designer、布局布线和bitstream导出：

- TIMING_2 / seed=6 / effort=2，现有时钟约束未放宽。
- 布局报告：12,805 / 60,800 XLR（21.06%），86 / 256 RAM10（33.59%），9 / 160 DSP（5.62%）。
- 像素时钟clk_pixel_2x的Setup余量+1.398ns、Hold余量+0.030ns。
- 全部28条Setup/Hold关系非负，最小余量+0.021ns；DDR core_clk→twd_clk Setup为+0.136ns。
- 实际综合网表检查通过：相机/DDR/RGB/Canny/HDMI/UART存在，排除模块没有被保留。
- UART各镜像控制回归、image3能力限制、冻结、诊断图和分屏回归通过。
- 灰度、Canny运算核、Canny视频流和中值核回归通过；Canny算法源文件未修改。
- checked.bit与本次导出的普通bit SHA256一致，长度2,263,704字节。
- SHA256：`8F69839F350E19E55D5C63725113397B7B14D99687C6CE56D652F529ED832E09`。

报告位于image3工程自身的outflow目录；测试日志在work_sim中，均按现有规则忽略。
Interface Designer保留了现有HDMI附近HSIO间距告警；本轮没有改动引脚分配。
尚未下载到实板，没有上板稳定性或人体姿势匹配的实测结论。
