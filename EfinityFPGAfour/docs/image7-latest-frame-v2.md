# image7 最新完整帧优先候选 v2

本轮在性能候选 v1 上优化输入帧调度，使用独立工程 `images/image7_latest_a/Ti60_Image7_Latest_A.xml` 与 `src/pose7_latest`。原始 image7、性能 v1、image6、image1／image5 的运行源码与已有 HEX／BIT 保留。开始修改前已登记 67 个 HEX／BIT 的长度与 SHA256，并在 `tmp/image7_latest_20261029/baseline` 保存 Git 源码 ZIP 和性能 v1 发布包。

## 调度变化

DDR 的 `0x01800000..0x019FFFFF` 与 `0x01A00000..0x01BFFFFF` 分别作为两个图像区；模型与激活区仍从 `0x02000000` 开始，两者不重叠。它们使用板载 DDR，没有新增整帧片上 RAM。

采集器只在一帧完整接收、DDR 写入完成且检查通过后标为可用。推理开始时选择最新的完整帧，并锁定其区域。输入缩放完成、相关 DDR 事务结束后才释放区域；在此期间采集器只能写另一个区域。过时的未使用帧可以丢弃，正在读取的帧不能覆盖。坏帧和不完整帧不能发布。

两帧区域之间只有所有权切换，不做图像混合、预测补帧或坐标平滑。11 点 A 模型、权重、Canny 和两级 OR 输入处理、量化舍入、16 路 MAC 与 96 MHz 时钟保持原样。v1 的精确执行器继续复用。非模型图像传输保留冻结帧和原字节读取方式。

自动推理模式下，USB 模式／尺寸切换等待 USB 数据包完整结束，不再要求独立运行的模型和连续采集器一起空闲。Flash 重配置仍使用更严格的独立退出条件，等待推理、读取锁、采集及 DDR 在途事务排空。UART 上传、SD 检查、诊断任务的重配置保护继续保留。

## 结果与口径

连续识别的 v1／v2 对照见包内 `reports/performance.json`。两个对照都从同样的 SD 启动、自检与视频压力条件开始，各输出六次正确结果，统计后五次的更新间隔，以及所选帧采集开始到坐标产生的时间。时间戳跟随被选中的区域，不能用正在采集另一帧的时间替代。所有值由仿真周期按 96 MHz 折算，不含 HDMI 下一帧提交等待，`board_measured=false`；实板需要另外验收。

本次同条件六次对照中，稳态更新约 16.58→16.56 次／秒，采集开始到坐标输出约 105.19→88.11 ms，减少约 16.2%。本轮资源为 XLR 57,591、RAM10 186、DSP 73；上一轮分别为 57,632、186、73。

本轮专项仿真让每帧具有不同编号，检查最新帧选择、长时间读取保护、采集继续更新、DDR 阻塞导致的溢出丢弃与恢复、同周期取帧／分配、停止／取帧竞争、模式切换等待锁释放、重复启动及原冻结字节流。另用真实 UART 前缀控制器检查自动推理时 USB 模式／尺寸／停止应答和数据包完整性。

发布还要求完整 SD4／FAT32 启动、自检、连续模型点位与热图 CRC、菜单检查、SD 文件缺失恢复、视频 DDR 压力、USB 阻塞及恢复、重配置退出、全部时序／CDC／MIPI 裕量及资源检查通过。没有把专项仿真当成实板测试。

## 使用

1. 临时 JTAG 测试：下载 `fpga/image7_latest_a.bit`。保持摄像头、HDMI 和 SD 卡连接，比较骨架跟手感与视频稳定性。SD 根目录继续使用原 `MODEL7.BIN`。
2. 固化：将包根目录 `FLASH_IMAGE7_LATEST_1_5.hex` 写入配置 Flash 并校验，重新上电。默认进入最新帧版 image7，菜单仍可切换 image1／image5；这两套镜像使用原已验证版本。
3. 单独 BIT 不含官方合并时生成的镜像地址表，三程序切换需从合并 Flash 上电后验证。
4. 回退 v1：临时下载 `baseline/image7_v1.bit`；恢复原固化内容可使用 `baseline/FLASH_V1.hex`。旧发布目录与全部原 HEX／BIT 也完整保留。

模型文件仍为 236,448 字节，SHA256 为 `74280f04c943f1684f7ff1336919db0806adb01f81b5feb76caf2168d33da12e`。本轮没有连接串口、JTAG 或写板卡 Flash。

## 复现

- `tools/test-image7-latest-snapshot.ps1`：不同帧编号、所有权和丢帧／恢复专项。
- `tools/test-image7-latest-control.ps1`：模型运行中的真实 USB 前缀控制与严格 Flash 退出区分。
- `tools/test-image7-reconfig.ps1 -LatestCandidate`：上传与诊断任务所有权保护。
- `tools/test-image7-standalone.ps1 -WithVideo -LatestCandidate -SimulationName pose7_latest_standalone_final`：完整模型、SD 和视频集成回归。
- 对照：同一脚本用 `-PerfOnly -LiveSamples 6`，分别指定 `-PerfCandidate` 和 `-LatestCandidate`，并使用不同的 SimulationName。
- `tools/build-image7-latest.ps1`：独立工程编译与时序、资源检查。
- `tools/package-image7-latest.py`：核对原文件、源码指纹、测试、官方 Flash 合并与配置载荷，生成独立发布包。
