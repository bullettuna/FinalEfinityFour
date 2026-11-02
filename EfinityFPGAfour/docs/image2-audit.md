# image2 时序、逻辑与功能复查

2026-10-22，复查基线为 `17ac26b`。工程为
`E:/Efinity_Project/EfinityFPGAfour/images/image2_photo/Ti60_Image2_Photo.xml`。

本轮复现并修复 1 处自动预览请求丢失问题。修复后综合、布局布线、时序检查、
算法逐像素比对、拍照存卡及视频并发仿真通过。这个结论限于代码、仿真和工具报告；
源码复查完成时未执行 JTAG 下载或 Flash 烧写。随后尝试上板的结果见文末；
摄像头实拍、真实 TF 卡兼容性及实板画质仍待验证。

## 已修复：保存完成遇到初始化时丢失自动预览

原实现的 `open_saved_photo` 只保持一个系统周期。如果此时用户发送 i，
`gallery_admit` 因 query_req 为高而拒绝打开，下一周期请求被清掉。
照片已成功写入 TF，但不会自动显示。

现在请求保持到相册接收，并在保存成功时锁存对应文件号。初始化完成后继续打开
准确文件；用户显式导航或接受新的拍照可以取消该请求。请求未被接收前拒绝删除，
避免用户误删仍显示着的上一张照片。没有更改图像算法、DDR 地址或 TF 文件格式。

`photo_native_pipeline_tb` 的 AUTO_OPEN_RACE=1 用例在保存完成时发 i：
修复前触发 `automatic preview request lost`，修复后检查第二次初始化确实成功，
再检查自动加载文件号为 2。后续 E 拍照、失败重试、删除和处理错误保护也继续运行。
该用例已加入 `tools/test-image2-canny.ps1`。

## 时序与网表

Efinity 2025.2.288，Ti60F225/C4，TIMING_2、effort=2、seed=4；未放宽原约束。
最新报告为 `images/image2_photo/outflow/Ti60_Image2_Photo.timing.rpt`。

- 14 项 setup、14 项 hold 全部非负。
- 系统域约 96MHz：setup +2.241ns，hold +0.026ns。
- 像素域约 148.8MHz：setup +1.389ns，hold +0.026ns。
- 最小 setup 为 DDR IP core_clk→twd_clk +0.153ns。
- 全局最小 hold 为 DDR IP twd_clk→twd_clk +0.014ns，余量较小但满足当前模型。
- CDC 报告没有 synchronizer skew 警告；它不构成所有跨域行为的形式化证明。

实际网表检查通过：应用输入有驱动，灰度均值采样器、行 RAM、13 块 RAM 的拍照
FIFO、整帧处理器、DDR 工作缓存及实时 Canny 均保留。未发现本轮新增模块的
组合锁存或多驱动问题。工作缓存的小数组映射为逻辑符合异步读取方式；关键行缓冲
和 FIFO 保留块 RAM。DSP 的 CE=0 警告已结合映射参数检查，使用的寄存级未启用 CE。

最终资源为 XLR 33,911/60,800（55.77%）、RAM10 126/256（49.22%）、
DSP 32/160（20%）。STA 通过仅说明现有受约束关系满足要求，不能代替实板 DDR、
摄像头与 SD 外部接口的信号完整性及工作条件验证。

## 功能覆盖

已实现并仿真验证：C 彩色、G 灰度、E 二值边缘拍照；G/E 的 2×2 灰度均值与可选
3×3 中值；E 的 Gaussian、Sobel、NMS、双阈值、整帧八连通强弱连接和 D/N 去小域；
后处理完成后保存 RGB565 BMP 至 FAT32/SD4，并自动打开刚保存的文件。

算法检查包括 32 组独立 Python 参考逐像素比对、末端强种子的长弱链、纯弱域丢弃、
小强噪点/闭合圈，以及读写错误、超时后的 AXI VALID 保持与故障不发布。
本轮重跑这些用例、UART 参数/大小写命令隔离、C/G/E 采样和完整存卡集成，均通过。
此前已通过的 1920×1080 采样、960×540 全阶段处理和 32×540 满队列/高位 Y 坐标
测试仍适用，本轮未修改这些算法模块。

新增 `tools/test-sd4.ps1 -ProcessedVideoOnly`：在真实视频读调度器和两级 AXI 仲裁下
完成两张 Canny 照片。逐字节检查 TF 中的图像，逐像素检查相册 RGB565 解码，
同时检查 RAW HDMI 无下溢、读事务正常完成。相册与 RAW 使用同一帧复位及足够的
消隐窗口，匹配顶层连接。该并发测试使用缩小画幅，不宣称替代实板 1080p 带宽测试。

普通 SDHC/SDSC 拍照、失败重试、读写背压与恢复、相册前后翻页/退出、双确认删除、
两份 FAT/FSInfo 更新及删除异常保护回归继续通过。

E 实时预览仍用局部连接；完整八连通和 D/N 去斑作用于最终照片。与主轮廓相连的
杂纹、阴影或大背景边缘不能仅靠小连通域删除。功能实现不等于保证任意场景无杂波。
处理为按需整帧运行，先前常量帧仿真约 2.23 秒（96MHz，不含存卡/回读），
复杂图像及 DDR 仲裁会增加时间，实板总耗时尚未测量。

## 产物与复现

- 最终 bit：`images/image2_photo/outflow/Ti60_Image2_Photo_checked.bit`，
  2,675,649 字节，与同次原始 bit 的 SHA256 完全一致：
  `F453BFF1BB3948A64B71E373BE1019951771615ACC4BA6699F26BAE62E631F3C`。
- 最终 hex：`images/image2_photo/outflow/Ti60_Image2_Photo.hex`，2,675,709 字节，
  SHA256 `143445A847DF9D4C579B16DCDD7C2B51D5097522C83298C4842230A76948BE76`。
- image1/3/4/5 的 8 个 bit/hex 哈希与复查前相同。

```powershell
& tools/test-image2-canny.ps1
& tools/test-sd4.ps1 -ProcessedVideoOnly -SimulationName image2_audit_video
& tools/test-sd4.ps1 -SimulationName image2_audit_sd4
& tools/test-sd4.ps1 -DeleteOnly -SimulationName image2_audit_delete
& tools/build-image.ps1 -Image 2
```

本地日志：`work_sim/image2_audit_build.log`、`work_sim/image2_audit_canny.log`、
`work_sim/image2_canny/auto_open_race_final_run.log`、
`work_sim/image2_audit_video_final.log`、`work_sim/image2_audit_sd4.log`、
`work_sim/image2_audit_delete.log`。修复前复现记录为
`work_sim/image2_canny/auto_open_race_before_run.log`；其中的 fatal 是预期的旧版缺陷复现。
普通 SD 回归中的 sd4_gap_negative 是有意违规的负向测试，必须由卡模型拒绝。

修改前源码 `17ac26b` 已成功推送 GitHub；本地回退标签为
`codex/backup-before-image2-audit-20261022`。修改前 bit/hex 已复制到
`E:/Efinity_Project/bit_hex_archive/Image2_before_audit_20261022/`。

## 后续上板连接检查：未读到有效 FPGA ID

2026-10-22 用户要求继续后，枚举到一个下载器 ELITES-232DL / FT232H，
USB ID 为 0403:6014，当次 URL 为 `ftdi://0x0403:0x6014:2:9/1`。
电脑串口只有蓝牙 COM3/4/7/8/10/11，未枚举到板卡 USB UART；未检测到可移动盘。

使用此前成功的 Generic Board Profile Using FT232 和 6MHz 尝试临时 JTAG 下载
最新 checked.bit，工具返回 0 且打印 finished，但器件 ID 为 `0xFFFFFFFF`，
与本板此前记录的 Ti60 `0x10660A79` 不符。因此本次**不能认定下载成功**，
没有继续发送拍照命令，也没有写入 Flash。

进一步用厂商 JTAG API 只读 ID：1MHz、3MHz 各连续读取三次，六次均为
`0xFFFFFFFF`。降低频率后仍未读到有效器件，当前需现场检查板卡供电、JTAG 排线
方向/接触、共地及下载器到板卡的连接。现有证据不能区分这些具体原因。

检查了厂商程序：普通 mode=jtag 分支没有像链式下载分支那样校验 ID 一致性，
所以仅凭返回码和 finished 不能作为成功证据。下一次应先确认 ID 为
`0x10660A79`，再下载并通过 UART V 回复 2 验证当前镜像。
日志为 `work_sim/image2_hardware_probe.log`、`work_sim/image2_jtag_scan.log`、
`work_sim/image2_canny_jtag_download.log`、`work_sim/image2_jtag_id_probe.log`。
RTL、约束及 bit/hex 均未改动。
