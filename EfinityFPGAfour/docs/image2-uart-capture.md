# image2 摄像头 Canny 图串口采集

现已增加用户确认的 [旧 P3 ADC 旋钮调阈值方案](image2-adc-p3.md)，可在电脑串口
被收图脚本占用时直接转动旋钮调阈值。下面记录的 20:34 构建为 ADC 接入前版本。

本功能在 `codex/image2-canny-photo-20261022` 分支的 image2 上增加。
最终 Canny 照片固定 **960×540**，与 HDMI 1920×1080 实时预览不同。
串口读取 FPGA 已完成的整帧 Canny/去斑结果，不在电脑上重算 Canny。
原 `b` 保存 TF、相册和删除命令继续使用。

## 快速使用

先通过 JTAG 下载本次串口版 image2：
`images/image2_photo/outflow/Ti60_Image2_Photo_checked.bit`。
旧的 Canny 拍照 bit 不支持这套导出协议，脚本会用 `:` 能力查询拒绝旧版。
固件编译状态、校验值和实板验证状态见本文件末尾。

关闭占用串口的 VOFA+/串口助手。使用板上现有 UART USB 连接，115200 / 8N1，
无需新增引脚、TF 卡或初始化 `i`。独立串口模块则沿用板上既有 3.3V TTL UART
接线并共地，不使用 RS-232 电平。

```powershell
cd E:\Efinity_Project\EfinityFPGAfour
python -m pip install -r tools/requirements_image2_uart.txt
python tools/image2_uart_receive.py --list-ports

# COM5 换为实际串口号。摆好动作后按一次 Enter，采一张；q 退出。
python tools/image2_uart_receive.py --port COM5 --label pose1

# 第二个动作另存目录
python tools/image2_uart_receive.py --port COM5 --label pose2

# 每张完成后等 1 秒，再开始下一次采集；不是视频帧率。
python tools/image2_uart_receive.py --port COM5 --label pose1 --count 30 --interval 1

# 可设置原 image2 阈值；M/D 沿用板上当前值，并随图片记录。
python tools/image2_uart_receive.py --port COM5 --label pose1 --high 60 --low 30 --min-pixels 20
```

默认保存 `samples/image2_uart/动作名/时间_s序号_canny1.png`，附带同名 JSON。
PNG 为 960×540 的 8 位灰度文件，每个像素严格为 0/255，白色是边缘；
串口上以每字节 8 像素无损打包，电脑展开后尺寸和像素不变。
JSON 记录动作标签、尺寸、序号、时间、M/D/N/H/L、CRC 和 PNG SHA256。
本仓库忽略默认采集目录，采集照片不会被日常源码备份自动提交。
`--output` 可改数据集根目录，动作标签仍作为其子目录。

**速度**：二值载荷 64,800 字节；115200/8N1 理论纯传输下限约 5.63 秒，
实际还包括 UART 间隔、完整帧采集和整帧处理，不能连续 60fps。
这不降低图片分辨率；请在采集瞬间保持姿势。软件提示 Saved 后再采下一张。

`--mode gray` 导出 G 模式的 960×540 灰度照片，载荷 518,400 字节，
纯传输下限约 45 秒。它是处理后 RGB565 照片的 6 位绿色通道扩展成 8 位，
不是 Canny 前精确 8 位灰度工作区。两次分别拍摄的 G/E 图片也不是同一帧配对。
如需同帧精确灰度与边缘配对，需要另外增加工作区导出协议。

## FPGA 行为

- `:` 返回 `U`：具有本协议的 image2。
- `E` 后发送单字符 `@`：下一张完整摄像头帧 → 2×2 精确灰度均值 →
  中值/Gaussian/梯度/NMS/完整八连通强弱连接/DN 去斑 → 锁定照片 → 二值串口包。
- `G` 后 `@`：同样抓新帧，执行已有 G 照片处理，再导出灰度。
- C 模式 `@` 返回 `!`。原 `b` 仍表示拍照并写入 TF。
- 参数在接受采集时锁定；传图结束以前拒绝新的采集、初始化、删除等存储任务。
  Python 脚本在传图期间不发送其他命令。
- 每个 512 字节 DDR 扇区先完整读入本地小 RAM，再慢速发 UART，不长时间占着 DDR RREADY。
  二进制整包通过 UART 原有消息仲裁锁定，文本回执等到最后一个字节发完再发送。
- 上一张 TF 保存失败、仍有照片待重试时，`@` 返回 BUSY，不替换待重试照片；先用 b
  完成原照片保存或复位。串口采集完成后不写 TF，也不自动进入相册。
- DDR 出错时不发布可用图片。能读到包头后的读取错误用补零结束完整长度并附 FAIL，
  PC 必须同时核对 CRC 和 DONE。地址/数据超时延续原 DMA 的排空及故障锁定策略。
- 采集来源与原 b 一样是实时 WB/Gamma 摄像头链路；F 冻结的显示帧、Z 测试图和
  相册里的旧照片不作为 @ 的输入。相册仍显示旧照片时，@ 采到的依旧是新摄像头帧。

## 协议 v1

32 字节小端包头依次为：magic `I2PX`(4)、version=1(1)、format(1)、
width(2)、height(2)、payload_bytes(4)、sequence(4)、mode(1)、median(1)、
cleanup(1)、flags=1(1)、N(2)、H(2)、L(2)、reserved=0(4)。

format=1 是二值，每字节 bit7→bit0 对应由左至右的 8 个像素；format=2 是灰度，
每像素 1 字节。载荷保留 DDR 的 bottom-up 行顺序，由接收器翻成 top-down。
flags bit0 表示 bottom-up。载荷后为 4 字节小端 CRC32，再接 ASCII DONE/FAIL。
CRC 为 zlib/IEEE CRC32，覆盖完整包头和载荷，不含 CRC 自身与尾标记。
序号每次导出递增，复位后重新从 1 开始；文件名包含微秒时间，不因序号复位覆盖。

收图脚本只在尺寸、长度、模式、参数、CRC 和 DONE 全部通过后保存。
截断、串口丢字节或失败包不生成训练样本；遇到错误退出，排查后重新采集。
中断程序时 FPGA 可能仍在发上一包，等待原传输结束再重开脚本。

## 训练数据使用

按动作分文件夹采集，固定 H/L/M/D/N、白平衡/Gamma、相机方向、目标距离和光照。
包头记录了 H/L/M/D/N，未记录白平衡/Gamma/曝光；这些条件请在采集记录中另记。
同一动作可有多次独立摆姿和小范围位置变化，以适应后续匹配。
按不同采集轮次划分训练/验证数据，避免将同一轮几乎相同的姿势图片同时放进两边。
最终板上匹配若改用 image3/image5，应先统一采样尺度与处理算法。

## 验证与构建

```powershell
& tools/test-image2-uart.ps1 -FullSize
& tools/build-image.ps1 -Image 2
```

回归覆盖 64×16 和完整 960×540 边缘/灰度包、逐像素与方向、CRC、PNG、分片串口读取、
传输中的参数锁定、命令回执不插入二进制包、DDR 失败包拒收；真实采样器/DMA/整帧
处理器联合仿真验证无 TF 抓图和重复采集。原 TF 保存/失败重试/删除与其他镜像 UART
命令也纳入回归。日志为 `work_sim/image2_uart_regression.log`。

旧 bit/hex 保存在 `images/image2_photo/outflow/before_uart_export_20261022/`。
本次修改前源码提交 `300e5a3` 已在 GitHub 备份。

2026-10-22 20:34，Efinity 2025.2，TIMING_2 / effort=2 / seed=4，原时钟约束未改。
综合/布局布线/导出、实际网表和源码时间一致性检查通过；全部 28 条受约束的
setup/hold 关系非负，最小余量 +0.022ns。像素时钟 +1.221/+0.027ns，
系统时钟 +1.822/+0.026ns，DDR core_clk→twd_clk setup +0.135ns。
总资源 34,620 / 60,800 XLR、127 / 256 RAM10、32 / 160 DSP；
导出器自身 499 XLR / 1 RAM10 / 0 DSP。

20:34 串口版的历史交付（现位于 `outflow/before_adc_p3_20261022/`，当前 ADC 版见文首链接）：

- `images/image2_photo/outflow/Ti60_Image2_Photo_checked.bit`，2,698,179 字节，
  SHA256 `49FAB6DC99AFBE959D46622BA5E60206C222620BF89425E053A11C33EDE98A76`；
  与同次导出的原始 `.bit` 完全一致。
- `images/image2_photo/outflow/Ti60_Image2_Photo.hex`，2,698,239 字节，
  SHA256 `7FCBED57174E0AE7D954E4D5443CBCA51EDD05B6B2BB60E80988153C50B8E4B5`。

本次未下载到实板、未写 Flash；USB-UART 的实际收图、耗时和实拍效果仍待连接板卡验证。
完整仿真日志 `work_sim/image2_uart_regression.log`、编译日志 `work_sim/image2_uart_build.log`。
