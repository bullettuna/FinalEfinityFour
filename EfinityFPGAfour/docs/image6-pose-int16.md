# image6 INT16 四点推理

工程：`images/image6_pose_int16/Ti60_Image6_Pose.xml`，Ti60F225 C4 / Efinity 2025.2.288。image5 源工程保留。当前是 SD 自动加载、板上自检和 HDMI 四点叠加的临时 JTAG 版，**本轮不做 Flash 启动**。详细步骤、文件和错误码见 [image6-standalone.md](image6-standalone.md)。

## 当前工程结论

当前串口调试版完整布局布线通过：XLR 43285/60800（71.19%），RAM 185/256（72.27%），DSP 56/160（35.00%）。系统 96 MHz 建立裕量 0.176 ns，全部 28 项时钟建立/保持关系通过。原先 SD 功能首轮构建的最差余量为 0.007 ns，定位到重量化宽乘法器后拆成注册的部分乘积与加法；没有降时钟，数值舍入规则不变。

位流：`images/image6_pose_int16/outflow/Ti60_Image6_Pose_timing_checked.bit`。
SHA256：`a79499d8409fd2cc42b75adb49983ea4a0c2a86ff71884a42ca0df19673235e2`。

**本版实板尚未验收。** 用户最新确认 SD 仅完成接线、尚未实测，2 GB FAT32 卡的启动文件稍后由用户通过读卡器复制；用户自行临时下载。不进行硬件枚举、下载、驱动/EEPROM 修改、SD 写入或 Flash 写入。历史 USB/JTAG 记录不代表当前硬件状态或本版验收结果。

## 保留与新增

复用 image5 摄像头、DDR 视频路径、Canny（含既有中值/清理设置）、ADC/按键、异步 FT232H 物理接口和诊断图包。复用 image2 原生 SD4 主机，按交接包当前 P4 引脚和 1.8 V FPGA 电平启用 SD。OLED/相册/旧人体识别关闭。

推理数据流：1080p Canny → 原 3x3 OR 得到 640x360 快照 → 整数区间 OR 得到 256x144 → 十层四点 context 网络 → 4x36x64 热图 → argmax 和四分之一网格修正 → Q14.2 原始 640x360 坐标。

新增核心位于 `src/pose6/`：

- `pose6_mac16`：16 路 signed17 x signed16，48 位累加。
- `pose6_requant`：卷积输出量化、可选 ReLU、下一域量化，均使用饱和 RNE；不是浮点近似卷积。
- `pose6_conv`：8 行输出分块、32768 个 UINT16 输入缓存、16 个 512x16 权重缓存，共 80 块 RAM，十层共用。
- `pose6_network`：十层调度，两处最近邻/拼接暂存 DDR，以便逐项核对，不增加大特征图 BRAM。
- `pose6_input_pool`、`pose6_decode`：精确训练输入和解码，附输入/热图 CRC。
- `pose6_uart_loader`、`pose6_packet`、`pose6_axi_master`、`image6_ft_link`：模型加载、FT 坐标包和 DDR 客户端。复用 `photo_axi_mux` 做第二级仲裁，外层视频优先规则保留。
- `pose6_debug_uart`：ASCII SD／文件／自检状态快照、推理开关和安全重载命令；命令及正常回复见独立运行说明。

## 模型和存储

模型身份见 `model-contract.json`、`pose6_model_identity.vh`、`pose6_layer_config.vh`。原卷积权重 160528 字节；按 16 输出通道排列并补零后，上传文件 161440 字节，CRC32 `bbffdf52`，SHA256 `5db98c6fc5cab40ed05ed869740cca682e782d9eea3da5ab9e89b03781fd8fc1`。

DDR 字节地址：参数从 `0x02000000`，输入 `0x02100000`，各层特征图至 `0x022347ff`；具体互不重叠的区间见合同。原快照从 `0x01800000` 开始。DDR 参数仍是易失数据；现在位流开始运行后从 FAT32 根目录 MODEL6.BIN 自动加载，校验并执行固定输入数值自检后持续推理。该文件含权重和自检数据，不是原始 model.bin。Flash 自动启动后续另做。

模型、量化尺度、偏置、通道数、PC CRC 必须作为同一个版本更新；不能只上传另一个权重文件。

## 重现命令

在 HDL 仓库根目录运行：

```powershell
E:\Efinity_Project\FPGA_GAME\.venv-fourpoint\Scripts\python.exe tools/export-image6.py
powershell -ExecutionPolicy Bypass -File tools/test-image6-arithmetic.ps1
powershell -ExecutionPolicy Bypass -File tools/test-image6-conv.ps1
powershell -ExecutionPolicy Bypass -File tools/test-image6-pipeline.ps1
powershell -ExecutionPolicy Bypass -File tools/test-image6-protocol.ps1
powershell -ExecutionPolicy Bypass -File tools/test-image6-axi.ps1
python tools/prepare-image6-sd.py
powershell -ExecutionPolicy Bypass -File tools/test-image6-sd.ps1
powershell -ExecutionPolicy Bypass -File tools/test-image6-overlay.ps1
powershell -ExecutionPolicy Bypass -File tools/test-image6-debug.ps1
powershell -ExecutionPolicy Bypass -File tools/test-image6-standalone.ps1 -WithVideo -SimulationName pose6_contended
powershell -ExecutionPolicy Bypass -File tools/build-image6.ps1
```

仿真使用已有 Vivado 2024.2 xvlog/xelab/xsim；生成参考向量使用训练虚拟环境和本地冻结模型，不启动训练。

临时下载工具 `tools/image6-jtag.py`：按已识别的下载器序列号过滤当前进程的 USB 枚举，避免通用 SDK 扫描接收模块 D2XX 驱动时报错。不修改已安装 SDK、驱动或接线；要求连续读到 Ti60 ID `0x10660A79`，且位流 SHA 匹配时序检查记录。

游戏启动使用 FPGA_GAME 根目录 `start-image6.ps1 -SkipDownload -ComPort COM30`，默认检查板上 SD 加载和数值自检后启用 USB，不上传权重；旧 UART 上传/固定输入比对保留为 `-UartLoad` 开发入口。操作见该目录 `IMAGE6.md`。

## 后续优化依据

目前资源没有要求把 Canny 换成 Sobel。若实测速度不足，先检查 DDR 访问等待、输入缓存和两次 glue 写回，再决定优化地址映射/突发传输。仿真周期数不能代替实板帧率。更换 Sobel 会改变输入分布，须用同场景采样重新比较效果。
