# image1 显示同步修复

用户实板反馈：新中值版各模式花屏，E黑屏；Z独立四色正常，M关闭仍异常。
加入中值之前的旧checked.bit下载后C/E正常。这些反馈将问题范围缩小到新版本的实时视频路径。

## 可复现的同步缺陷与修复

旧中值前端在6拍过滤路径与0拍原始路径之间切换VS/HS/DE。
使用真正的低有效LCD同步和前后肩重放，在M从1切到0时，44拍HS低脉冲变成38拍。
旧代码对照日志位于 `work_sim/display_fix_old_repro/old_repro.log`，触发
`FAIL runt horizontal sync 38`。这证明旧测试的“VS覆盖整幅有效图像、HS只在DE期间拉高”
激励不足以验证HDMI同步；该缺陷与算法像素测试通过可以同时存在。

新前端共享32位两行窗口，计算灰度及RGB精确中值；M只选择像素值。
未过滤旁路、过滤结果和同步均固定为7拍延迟，包含末级输出寄存器。
分屏原始灰度直接复用共享窗口中心，减少一组独立行缓存。

新增 `image1_video_mux.v`，将相对grey输出的六条路径补齐到39拍：

- C：原始0拍，补39拍；G：中值7拍，补32拍。
- E与分屏：7+20=27拍，补12拍。
- O：27+8=35拍，补4拍。
- D识别、检测框及中文：27+8+1+3=39拍。

最终同步固定来自这组同相位信号，模式选择只切换RGB；末级统一寄存，总延迟40拍。
输入处理配置在VS低脉冲期更新，显示选择也只在消隐期提交。
这些是时钟延迟对齐；各算法原有的空间窗口与分屏原图配准仍由原模块负责。
image2的新参数保持默认0，其他镜像下载文件不由本次构建更新。

## 验证

`tools/test-image1-median.ps1` 保留原精确中值、Canny噪声消除及原图分屏对齐测试。
新增 `-VideoTiming` 使用实际lcd_driver和实际灰度、中值、Canny、彩色叠加、
分屏、形状显示及中文字模块；在有效行中提交M和六种显示请求。
断言覆盖固定7拍前端、六路同步逐拍相同、固定40拍显示同步、行宽/行数、
完整帧、44拍HS脉宽、恒定行/帧周期、RGB与同步统一寄存及安全切换。
识别算法在该时序测试中关闭计算，显示时序路径和中文字流水线仍实际运行；
本测试不据此声称识别正确率。

```powershell
python tools/check-image1-median.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-image1-median.ps1 -InitialMedian 1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-image1-median.ps1 -FullHD
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-image1-median.ps1 -VideoTiming
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-image1-median.ps1 -VideoTiming -FullHD
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-image.ps1 -Image 1
```

## 实板复查顺序

1. 下载最终通过检查的新checked.bit，重新上电，确认Z关闭、D关闭、分屏关闭。
2. 先发C看实时彩色图，再G看灰度，再E看有明显黑白边界的物体；保持旋钮不动。
3. M分别切到0和1，反复执行C/G/E/O，确认无花屏、失锁或持续黑屏。
4. E后测试 `|` 分屏，再关闭分屏测试D识别及中文标签，最后测试F冻结/恢复。
5. 每项至少观察数秒并重复切换。若仍异常，记录模式、Z结果及LED0～3状态，
   继续区分DDR校准、摄像头丢帧与显示FIFO欠载。

该修复的仿真和静态时序不能代替实物显示验证。用户已验证正常的旧版仍保留用于对照。

## 备份

修改前源码已推送GitHub提交 `22e1e7b`，修复分支为
`codex/image1-display-fix-20261024`。

出现异常的初版bit/hex、配置和时序报告：
`E:/Efinity_Project/bit_hex_archive/Image1_before_display_fix_22e1e7b_20261023_233135.zip`。
旁边manifest记录SHA256，压缩包内容逐项核验通过。

用户验证正常的前置中值之前的旧版：
`E:/Efinity_Project/bit_hex_archive/Image1_known_before_median_11d783d/Ti60_Image1_Vision_checked.bit`。
SHA256为 `C7FBFA2F41183B16049099287EE7290E9FA6754B511B3D41695DAF9EFF9B3591`。

第一轮修复构建出现DDR core_clk→twd_clk建立余量−0.013 ns，未标记checked，
产物已存 `E:/Efinity_Project/bit_hex_archive/Rejected_Image1_display_fix_first_seed4_20261023.zip`。

## 修复版下载文件及静态检查

2026-10-23 23:57:26 完整编译导出，TIMING_2 / seed=7 / effort=2。
28项建立/保持关系全部非负：像素Setup/Hold +0.079/+0.010 ns，
DDR core_clk→twd_clk Setup +0.017 ns，全局最小余量+0.010 ns。
未放宽SDC或修改外围配置，两者哈希与修改前一致。
实际网表49,927 XLR / 197 RAM10 / 12 DSP；中值前端2,520 XLR / 14 RAM10；
固定相位出口582.5 XLR / 0 RAM10。

`images/image1_vision/outflow/Ti60_Image1_Vision_checked.bit`：2,956,272字节，
SHA256 `5471AB0E3BEF5F621D5FC8E7F95D9D0ED2F8BCDD31C3870C242D96FBC22C722B`。
同次hex为2,956,332字节，SHA256
`2707BC22F67A96A1EA347A79EAB55C5763E9FA703D7DF5C916DFFC396E638E61`。
原始bit与checked.bit逐字节相同。最终文件、配置和报告另存
`E:/Efinity_Project/bit_hex_archive/Image1_display_sync_fix_seed7_20261023.zip`，
manifest及压缩包内容均核验通过。下载器应重新选择/加载该文件，避免沿用旧缓存。

实板显示结果待用户复核。
