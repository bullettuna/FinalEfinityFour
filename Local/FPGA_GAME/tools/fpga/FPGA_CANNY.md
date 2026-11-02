# 本地 RGB 转 image5 FPGA Canny 边缘图

## 当前目标与修正

默认目标已经改为 `E:\Efinity_Project\EfinityFPGAfour\images\image5_canny`，
不是最初参照的 `04-1_Ti60_SC2210_HDMI_1080P60` 单独 Canny 链路。
前一版遗漏了 image5 前置中值、两级边缘清理和边界置黑，默认阈值也不同，不能作为 image5 的等价输出。
当前配置与来源指纹保存在 `fpga_canny_profile.json`。

脚本不下载数据、不训练 YOLO，不调用 OpenCV Canny；只依赖 NumPy 和 Pillow。

## 运行

```powershell
cd E:\vscode\cpp\EfinityFour
python -m pip install -r .\tools\requirements_canny.txt

# 合成彩色测试图，不下载图片；每次可换新的输出目录
python .\tools\fpga_canny.py --demo --output .\output\image5_demo --save-stages

# 单张彩色图片：换成自己的文件路径
python .\tools\fpga_canny.py --input "D:\dataset\photo.jpg" --output .\output\image5_photo

# 递归处理目录，并保留 train/val 等相对目录
python .\tools\fpga_canny.py --input "D:\dataset\images" --output "D:\dataset_edges_image5"

# 与实际板卡的 UART 设置保持一致，默认低/高阈值就是30/60
python .\tools\fpga_canny.py --input "D:\dataset\images" --output "D:\dataset_edges_image5_2" --low 30 --high 60

# 对应板卡 M=0、D=0：仍保留窗口中心的固定延迟，不能直接跳过窗口
python .\tools\fpga_canny.py --input "D:\dataset\images" --output "D:\dataset_edges_image5_off" --no-median --no-cleanup

# 验证当前 RTL 仍与参数快照一致
python .\tools\fpga_canny.py --demo --output .\output\image5_verified --fpga-root "E:\Efinity_Project\EfinityFPGAfour"
```

输入输出目录不能互相包含。默认拒绝向非空输出目录写入；显式 `--overwrite` 只覆盖本次同名文件，
不删除目录，也不清理旧批次中本次没有生成的文件。原图不会修改。
不缩放、不裁剪、不旋转、不按 EXIF 自动调整方向，保持文件中存储的像素宽高。
同一相对目录中的 `a.jpg` 与 `a.bmp` 会报命名冲突，避免都写成 `a.png`。

## 输出

- `images/.../photo.png`：image5 最终二值边缘图，值严格为0或255；默认保存三个相同通道，供三通道 YOLO 读取。
- `previews/.../photo.png`：前五张的原RGB、前级灰度和最终边缘对照。
- `manifest.json`：有效设置、逐张处理结果、尺寸、边缘数量、错误和来源文件 SHA256。
- `stages/.../`：加 `--save-stages` 时保存灰度、中值、Gaussian、梯度、NMS、双阈值分类、原始 Canny 边缘、两次清理以及最终边缘。
  `raw_stages.npz` 保存原始数值；梯度/NMS PNG 按0..2047映射至0..255，不能从预览亮度反推精确数值。

`--single-channel` 可保存单通道PNG；`--preview-count 20` 增加预览数量。
坏文件会记入 manifest，处理继续，最终退出码为1；批量处理后需检查错误数。

## 按实际 RTL 逐项对应

来源：`images/image5_canny/image5_platform.v`、`src/vision/image5_canny_pipeline.v` 和公共视觉核。

1. **白平衡**：`min(255,(pixel*gain+128)>>8)`，默认Q8.8增益R/G/B为335/248/280；256表示1倍。
2. **Gamma**：默认启用，强度42；使用从实际 Verilog 提取的256项ROM，
   `pixel+(((lut[pixel]-pixel)*strength+128)>>8)`。
3. **灰度**：`Y=(54*R+183*G+19*B+128)>>8`。
4. **前置3×3中值**：默认M=1，取九点精确中值；M=0仍取窗口中心，保留相同的空间和时钟延迟。
5. **3×3 Gaussian**：核`[1 2 1;2 4 2;1 2 1]`，`(sum+8)>>4`。
6. **梯度**：中值灰度复制到R/G/B；Gx=右列减左列，Gy=上行减下行；幅度`abs(Gx)+abs(Gy)`。
   方向按106/256整数比例分类，水平、右上/左下、垂直、左上/右下与RTL一致。
7. **NMS**：非零中心`>=`两个方向邻点时保留，相等也保留。
8. **双阈值**：默认low=30、high=60；0或小于low为非边缘，`>=high`为强边缘，其余为弱边缘。
9. **局部连接**：强边缘保留；弱边缘仅在八邻域有原始强边缘时保留；只执行一次，不递归传播。
10. **两级边缘清理**：默认D=1，每一级仅保留中心原本是边缘且至少有两个八邻域边缘邻居的像素。
    D=0仍经过两次中心取样，不改变固定延迟。
11. **边界保护**：最后把顶部12行、左右各2列、底部2行置黑，不裁剪尺寸。

没有在Canny前额外二值化。`--no-median` 对应M关闭，`--no-cleanup` 对应D关闭；
`--wb R G B`、`--gamma-strength N`、`--no-gamma` 可匹配实际 UART 配置。
image5 上电已经选择 Canny；串口V回复5可确认镜像身份，R恢复高/低阈值60/30但不重置M/D。

`--pipeline canny-core` 可只运行最初的 Canny 核，不加 image5 三个处理阶段；
此时若要复现前版参数，还需指定`--low 22 --high 45`。仅这个模式支持`--mode color`最强RGB梯度。
image5 模式不允许彩色梯度，避免把另一个处理模式误当成 image5。

## 光栅坐标与标签

默认`--layout raster`按窗口生成器的真实取样方式处理：输出行y使用`max(y-2,0),max(y-1,0),y`，
列x使用复制边界的x-1、x、x+1。这不是桌面图像处理中常见的对称三行窗口。
image5共七个窗口阶段，内部特征相对原图约向下延后7行，M/D关闭仍保留这7个中心延迟。
最初单独Canny核的4行延后不能套用于image5。

`--layout centered`将每一级改为以当前像素为中心、四边复制，仅用于离线对齐实验，
不是字面上的image5光栅输出。默认保持实际RTL行为。

脚本目前不复制YOLO标签。后续转换标注要处理特征偏移、底部缺失和边界置黑；
不能只因为输出宽高没变就宣称原框完全对齐。也不能从边缘图恢复被置黑的区域。

## 验证

```powershell
# 独立逐像素公式与批处理检查
python .\tools\check_fpga_canny.py

# 直接调用 Vivado，比较真正的 image5 Verilog 与 Python
python .\tools\check_image5_rtl.py --fpga-root "E:\Efinity_Project\EfinityFPGAfour" --vivado-root "F:\vivado\Vivado\2024.2"
```

RTL对照从同一RGB像素出发，经过白平衡、Gamma、灰度、image5中值/Canny/清理/边界保护，
在96×72下连续输入四帧，覆盖M/D四种开关组合、彩色合成图、随机噪声、平坦帧和移动图形。
结果写入`output/image5_rtl_check/comparison.json`，逐帧保存Python与RTL输出PNG。
仿真使用当前源代码，不会写入或修改FPGA工程。它不等于已验证板上实际烧录文件、摄像头ISP或HDMI采集压缩。

这里处理的起点是已有8位RGB像素，不模拟传感器曝光、Bayer去马赛克、DDR和HDMI。
训练后仍需用真实板卡输出验证，并保证实际UART参数与脚本参数一致。
