# image2：彩色、灰度与完整 Canny 去斑拍照

新增通过 UART 将最终 960×540 Canny 照片直接采集为电脑 PNG，无需 TF 卡。
使用本次串口版 bit 和 [电脑采集脚本说明](image2-uart-capture.md)，原 b 保存功能继续可用。

2026-10-22，工程入口仍为 `images/image2_photo/Ti60_Image2_Photo.xml`。
默认 C 彩色；照片继续为 960×540、RGB565、BI_BITFIELDS BMP，像素偏移 512，
文件共 1,037,312 字节。原生 SD4、FAT32、相册、双确认删除及保存失败重试继续使用。

## 使用

串口为 115200 / 8N1，单字符命令独立发送，数值命令以回车结束。

- `V`：返回 `2`，识别本 image2 配置。
- `C` / `G` / `E`：彩色 / 灰度 / Canny 边缘；分别返回 `0` / `1` / `2`。
- `T`：C→G→E→C；`S` 是 E 的兼容别名，`A` 确认 Canny。
- `b`：拍下下一张完整帧，锁定模式、中值、去斑级别、面积门限和 Canny 阈值。
- `i`：初始化 TF；`x`：进出相册；`<` / `>`：前后翻页。
- 小写 `d`：相册中双确认删除。大写 `D` 不删除文件。
- `M`：开关中值滤波，默认开启。作用于 G/E 预览及 G/E 照片。
- 大写 `D`：循环去斑级别，返回新级别 `2`、`0`、`1`。上电为 `1`。
  - `0`：关闭尺寸去斑，仍执行完整 Canny 强弱连接。
  - `1`：保守；白色像素数小于 N，且包围框宽、高均不超过 8，才删除。
  - `2`：加强；白色像素数小于 N 就删除，可能删除真实的小细节/短线。
- `N20` 回车：最小连通域像素数；0～2047，默认 20。计数单位为 960×540
  照片中实际的白色边缘像素；不是包围框面积。`N0` 禁用尺寸去斑。
- `H60` / `L30` 回车：高 / 低阈值，默认 60 / 30；低阈值限制为不超过高阈值。
- `+` / `-`：调整高阈值；`R`：仅恢复高低阈值，不重置 M/D/N。
- `F`、`Z`、白平衡 `WR/WG/WB/WD`、Gamma `Y/P` 保留；诊断 Z 不写入照片。
- O 彩色叠加、形状识别、分屏和人体相关命令仍不提供。

建议第一次上板：`V` → `i` 等待 `TF:INIT_OK` → `E` → `b`。
灰度/边缘照片依次报告 `PROCESSING`、`DDR_OK`、`tfOK`；处理期间不要重发 b。
保存成功后自动加载刚保存的准确文件号，收到 `ALBUM:READY` 后可检查最终结果。
发 x 退出相册再构图。C 彩色保存沿用 DDR_OK/tfOK，不自动进入相册。

保存失败后下一次 b 重试保留的原照片，模式/参数切换不会替换这张待重试照片。
`PROCESS_FAIL:RESET_REQUIRED` 表示后处理的 DDR 事务失败；不开始写 TF，必须复位后
再试，原先成功保存的文件不受新照片处理影响。

## 预览与最终照片

HDMI 为 1920×1080。E 预览使用灰度中值 + Gaussian + 梯度/NMS/双阈值 +
现有局部八邻域连接，用于构图、调参数。D/N 的整帧连通域去斑只作用于最终照片。

G/E 照片先对每个 2×2 源区域的四个精确灰度值取舍入均值，再在 960×540 上处理。
G 照片可选中值后转 RGB565；E 照片执行下面的完整链路。因此预览与照片的像素、
细节及边缘连接不承诺一一对应；相册显示的就是 TF 中的最终照片。

## 算法与实现

1. 灰度使用工程既有 `(54R + 183G + 19B + 128) >> 8`，与彩色同步延迟匹配。
2. 2×2 灰度均值 `(Y00+Y01+Y10+Y11+2)>>2`；C 仍保留旧 RGB565 左上角采样。
3. 可选精确 3×3 中值；默认开启。
4. 3×3 Gaussian `[1 2 1;2 4 2;1 2 1]`，加 8 后右移 4，边界复制。
5. Sobel L1 幅值 `|Gx|+|Gy|`，四方向量化沿用工程 106/256 的判据。
6. NMS 比较中心和方向两侧，中心须非零且不小于两侧；输出最外一圈置背景。
7. 保留背景/弱/强三态，按高、低门限分类。这里没有提前运行局部滞后或端点削除。
8. 在完整三态图上遍历每个八连通域，统计 has_strong、像素数和包围框。
   使用 DDR 队列的广度优先遍历，每个像素在入队前标为已访问，整帧每个候选像素
   最多入队一次；无需限制弱边缘传播距离，也无需选择固定迭代次数。
9. 仅保留包含强边缘、并通过 D/N 去斑规则的连通域。重用该连通域的队列，
   只标记真实成员像素；不擦除包围框内的其他目标。
10. 整帧渲染为 0x0000 / 0xffff，然后交给原 FAT32 保存器。G 同样在渲染后才允许保存。

后处理在 96MHz 系统域按需分阶段运行，以小片内工作集换取拍照处理时间；不是
60fps 的整帧去斑器。完整 960×540 常量帧的测试 DDR 模型用 214,502,386 周期，
折合 96MHz 约 2.23 秒，仅为模型中的处理时间，不包含采集、TF 写入和相册加载。
实板 DDR 仲裁、图像边缘数量及 TF 卡会影响总耗时，实板速度未测。

灰度/图像坐标在 DDR 中沿用 bottom-up 存放，所有空间处理均在同一坐标系完成，
最后生成合法 bottom-up BMP。相册加载继续转换成 top-down 显示地址。

## DDR 所有权

- RAW 实时/背景/相册沿用原地址，不加入新主人。
- 拍照双缓冲：`0x01600000`、`0x01700000`，每槽 1MiB。
- 工作 A：`0x01800000..0x018fffff`，中值/梯度复用。
- 工作 B：`0x01900000..0x019fffff`，Gaussian/三态/访问/保留标记复用。
- 工作队列：`0x01a00000..0x01bfffff`，32 位坐标，最多 518,400 项。

采集 DMA 完整写入且收到 B 响应后，才把拍照 AXI 端口切给处理器；处理器全部
写入确认后才发布新照片并转给保存器。工作内存使用四行 128 位全相联直写缓存，
每张照片开始时失效；不存在必须另行刷新的脏数据。

AXI 地址/数据在背压下保持，事务超时后仍保留已提出的 VALID 并排空迟到响应，
同时锁定为必须复位的故障。失败或处理中的缓冲不发布给 TF。

## 验证

```powershell
& tools/test-image2-canny.ps1 -FullSize
& tools/test-image2-full-frame.ps1
& tools/test-image2-full-frame.ps1 -ConnectivityOnly
& tools/test-controls.ps1
& tools/test-sd4.ps1 -SimulationName image2_sd4_regression
& tools/test-sd4.ps1 -DeleteOnly -SimulationName image2_delete_regression
& tools/test-sd4.ps1 -ProcessedVideoOnly -SimulationName image2_processed_video
& tools/build-image.ps1 -Image 2
```

- 独立 Python 数组参考对 4 个场景、中值开关、三档去斑进行 32 组逐像素比对。
- 定向三态输入验证末端强种子的长弱链、纯弱域、小强噪点及小闭合圈。
- 32×540 全候选图验证满容量队列、图像边界、超过 Y=511 的坐标和整域传播。
- 960×540 常量帧经过所有后处理阶段，逐像素输出全黑，无旧工作区残留。
- 1920×1080 输入的 C/G/E 采样各输出 518,400 个准确像素，帧中模式切换不混帧。
- 真实采样/DMA/后处理/SD4/FAT32/相册组合仿真检查 C/G/E 的 BMP 字节、自动打开
  新文件、原照片失败重试，以及后处理故障不发布。
- 处理照片的双确认删除会准确删除当前文件并重新选择剩余文件；原删除/相册回归保留。
- DDR 背压、读/写错误、地址超时后 VALID 不撤销均有负向用例。
- 保存完成与 i 初始化同时发生时，自动预览请求保留到相册能够接收，且文件号锁定；
  回归脚本包含这个竞态用例。显式翻页/进出相册或接受新的拍照会取消待执行的自动预览。
- 完整 Canny 与真实视频读调度、两级 AXI 仲裁、TF 保存及相册解码联合仿真通过；
  同时逐像素检查 RAW HDMI、两张照片的 TF 字节及相册显示像素。

这套验证不替代实板光照、噪声及 TF 卡测试。独立小杂点可按大小删除；与主要边缘
相连的杂纹、阴影和大背景轮廓不能靠连通域面积独立删除。滤波与尺寸门限过强会丢细节。

## 2026-10-22 原 Canny 拍照版编译交付（串口导出前）

以下为修改前历史交付，当前下载文件已更新为 [UART 导出版](image2-uart-capture.md)。

Efinity 2025.2，TIMING_2 / effort=2 / seed=4，原约束不变。
最终资源为 33,911 / 60,800 XLR（55.77%）、126 / 256 RAM10（49.22%）、
32 / 160 DSP（20%）。全部 28 条受约束 setup/hold 关系非负，最小余量 +0.014ns；
像素时钟 setup/hold 为 +1.389 / +0.026ns，系统时钟 +2.241 / +0.026ns，
DDR core_clk→twd_clk setup 为 +0.153ns。

实际网表检查确认新采样器、灰度均值行 RAM、拍照 FIFO、整帧处理器、工作缓存
和实时 Canny 预览硬件均保留，应用输入没有未驱动信号。checked.bit 与同次导出
原始 bit 完全一致，长度 2,675,649 字节：

- `images/image2_photo/outflow/Ti60_Image2_Photo_checked.bit`
  SHA256：`F453BFF1BB3948A64B71E373BE1019951771615ACC4BA6699F26BAE62E631F3C`
- `images/image2_photo/outflow/Ti60_Image2_Photo.hex`，长度 2,675,709 字节，
  SHA256：`143445A847DF9D4C579B16DCDD7C2B51D5097522C83298C4842230A76948BE76`

image1/3/4/5 的 8 个 bit/hex 哈希已与原清单核对，一致。
本地最终编译日志位于 `work_sim/image2_audit_build.log`，复查结果见
[image2 时序与功能复查](image2-audit.md)。其他日志位于 `work_sim/image2_canny/`、
`work_sim/image2_canny_full_frame/`、`work_sim/image2_connectivity_tall/` 及
`work_sim/image2_controls_regression.log`、`work_sim/image2_sd4_regression.log`、
`work_sim/image2_delete_regression.log`。

## 来源、回退及隔离

架构参考 [AMD Vitis Vision](https://xilinx.github.io/Vitis_Libraries/vision/2022.1/overview.html)
的流式前端/内存边缘追踪分工；完整连通语义参考
[scikit-image 0.25.2 Canny](https://github.com/scikit-image/scikit-image/blob/v0.25.2/skimage/feature/_canny.py)
和 [OpenCV Canny](https://github.com/opencv/opencv/blob/4.x/modules/imgproc/src/canny.cpp)。
本次新增 RTL 是本工程的实现，没有把 AMD HLS 或 Python 库直接综合到 Ti60，
也没有修改/复制 LinkRunCCA。现有 LGPL 派生模块及其声明保持原样。

修改前源码 `9944c91` 已推送 GitHub；本地标签 `codex/backup-before-image2-canny-20261022`。
旧 image2 bit/hex 保存在 `E:/Efinity_Project/bit_hex_archive/Image2_before_canny_20261022/`。
开发分支为 `codex/image2-canny-photo-20261022`。源码复查后曾尝试临时 JTAG，
但只读到无效器件 ID，未确认下载成功；详见 [上板连接检查](image2-audit.md)。未写入 Flash。
image1/3/4/5 的工程入口、平台和已发布 bit/hex 不修改。
