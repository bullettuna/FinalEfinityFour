# image7 A11 性能候选 v1

本轮保留原 image7 工程、模型和所有已有 HEX／BIT，新增独立工程 `images/image7_perf_a/Ti60_Image7_Perf_A.xml`。原 `images/image7_mocap11_a` 与 `src/pose7` 的运行模块未替换；新执行器放在 `src/pose7_perf`。源码基线为 Git `284106a`，本地额外备份位于 `tmp/image7_perf_20261029/baseline`，其中包含原源码 ZIP、image7 位流及原文件校验清单。

## 本次实际改动

- 量化：复用一组乘法器和舍入电路，分两批连续处理通道，保持两级饱和、最近偶数舍入、零点和 ReLU 规则。
- 输入缩放：顺序扫描一次不可变的 640×360 快照，用一行位缓存实现相同的 2／3 像素整数分箱 OR。没有改变 Canny、1080p→640×360 的 3×3 OR 或训练时的输入定义。
- 卷积缓存：按 128 位装载特征块，每次写入八个 U16，代替八个周期逐个拆写。乘加运算、权重及 48 位累加保持原样。
- 上采样／拼接：合并取值、装入输出字和坐标推进的控制步骤，保留完整中间张量与 DDR 地址布局。

系统仍为 96 MHz、16 路 MAC；没有改变视频／DDR 仲裁、摄像头时序、MIPI 工程裕量、FT232H 协议或单帧快照所有权规则。本轮通过缩短处理时间改善跟手性，没有加入“持续覆盖旧帧”的双缓冲策略。后续是否值得增加该策略，应以骨架对应图像的实际年龄决定。

## 验证与性能口径

原基准为 7,570,739 周期，新候选为 4,964,079 周期，减少约 34.4%；按 96 MHz 折算为 78.86 ms→51.71 ms。这是输入缩放、完整网络、解码和指定 DDR 停顿条件下的仿真，不是实板帧率，也不包括所有真实摄像头等待。

原资源为 XLR 57,860、RAM10 185、DSP 73；新候选为 XLR 57,632、RAM10 186、DSP 73。器件上限分别为 60,800、256、160。时钟没有提高。

发布工具只在以下项目全部通过后生成正式候选包：

- 完整输入、十层卷积和两处上采样／拼接的逐字节张量一致，11 点坐标和热图 CRC 一致。
- 4,352 个通道的原版与批处理量化一致，覆盖批长度、正负范围、可变移位、饱和、两级舍入和 ReLU。
- 四幅完整缩放专项图的全部 73,728 字节及 CRC 一致，覆盖空白、稀疏、边界、非标准非零像素、重复启动和 DDR 停顿。
- 原版连续识别对照及候选整机仿真，含 SD4／FAT32 启动、数值自检、模型启停、文件缺失恢复、菜单检查、视频 DDR 压力、USB 阻塞与恢复、重配置安全退出。
- 全部 setup／hold 关系、CDC、MIPI 附加裕量、FT 引脚及外部时序预算、资源与内部镜像切换控制器通过。

连续识别更新率与“采集开始到骨架输出”的对照见包内 `reports/performance.json`。所有毫秒和每秒次数均由仿真周期按目标时钟换算，`board_measured=false`。最终帧率、画面稳定性和跟手效果需要实板验收。

## 使用文件

1. 先测试识别效果：临时 JTAG 下载 `fpga/image7_perf_a.bit`；继续使用 SD 根目录原 `MODEL7.BIN`，无需重新训练或更换模型。骨架开关、原菜单和串口命令保持原样。
2. 需要固化及三镜像切换时：向配置 Flash 烧录包根目录 `FLASH_IMAGE7_PERF_1_5.hex` 并校验，再重新上电。默认进入优化版 image7，image1／image5 使用上一发布包中已通过检查的原镜像。
3. 单独 BIT 用于临时调试；它不包含官方合并时写入的内部重配置地址表。三镜像切换应从新合并 Flash 上电后测试。
4. 回退文件在包内 `baseline`，原发布目录也完整保留。请勿用单独 image1／image5 HEX 覆盖 Flash 起始地址。

本轮没有连接串口、JTAG 或写入板卡 Flash。模型文件仍为 236,448 字节，SHA256 为 `74280f04c943f1684f7ff1336919db0806adb01f81b5feb76caf2168d33da12e`。

## 复现

- `tools/test-image7-perf.ps1 -Variant baseline` 或 `candidate`：逐张量回归与阶段计数。baseline 使用上述本地备份 RTL；在新电脑上可从 Git `284106a` 恢复对应文件。
- `tools/test-image7-requant-batch.ps1`、`tools/test-image7-pool-fast.ps1`：两个专项一致性测试。
- `tools/test-image7-standalone.ps1 -WithVideo -PerfCandidate -SimulationName pose7_perf_standalone`：候选完整集成测试。
- `tools/test-image7-standalone.ps1 -WithVideo -PerfOnly -SimulationName pose7_perf_baseline_live`：原版连续识别对照。
- `tools/test-image7-reconfig.ps1 -PerfCandidate`：候选重配置任务所有权保护。
- `tools/build-image7-perf.ps1`：独立工程构建，不写原工程 outflow。
- `tools/package-image7-perf.py`：核对源码指纹、原文件不变、全部测试、位流及官方三镜像合并结果，生成独立发布包。
