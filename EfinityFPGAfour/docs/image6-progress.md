# image6 四点模型移植记录

目标：保留 image5 Canny 输入，在独立 image6 工程中完成 INT16 四关键点推理，游戏留在电脑。

## 执行约定

- 用户已授权按阶段自动执行，硬件已连接并可保持供电。
- 每阶段开始先说明需要用户协助查找、确定、现场操作或主观判断的事项。没有则明确说明不需要。
- 保留 image5 原工程。先临时 JTAG 验证 image6；启动 Flash 布局单独核对，不覆盖已有镜像。
- 不再训练模型；INT16 QDQ 只是已有数值基线，真正整数运算、RTL、时序与实板各自验收。
- 当前只建立 Git 备份后修改；HDL 分支 codex/image6-int16-pose。两个仓库开工前均 git push 成功。

## 阶段与验收

1. 模型合同与 DDR 布局：固定输入、参数哈希、量化与舍入规则、分支、地址区间。
2. 整数参考：完整十层推理；与现有 QDQ 对比，输出各层/边界测试向量。
3. 计算核和缓存：RTL 仿真通过、Efinity 综合占用和时序实测，按瓶颈调整缓存/并行度。
4. image6 集成：Canny、图像聚合、DDR 仲裁、串口模型加载、FT232H 坐标包，电脑解析支持。
5. 布局布线与上板：无关键时序违例、JTAG 有效器件 ID、模型加载校验、确定性输入逐项对齐。
6. 游戏闭环：四点显示，独立攻击/躲避逻辑、动作延迟与稳定性，交付可复现命令和限制。

## 已核对基线

- Ti60F225 C4，Efinity 2025.2.288；96 MHz 系统时钟。
- image5 2026-10-26 布局：XLR 17714/60800，RAM 104/256，DSP 11/160。
- 当前模型：context，256x144，80264 个 INT16 卷积权重（160528 字节），偏置 1024 字节。
- 所有关键点使用人体解剖学左右；电脑显示/游戏镜像仅映射一次。
- 权重和特征图放 DDR，BRAM 仅缓存；第一版不引入 SD。Flash 自动加载后续核对。
- Canny 保留；如更换 Sobel，须先做同场景两种输入效果对照，不能把旧 Canny 图当成 Sobel 测试。
- Vivado 2024.2 xvlog/xelab/xsim 可用，位于 F:/vivado/Vivado/2024.2/bin。

## 当前状态

阶段 1–3 已完成，阶段 4 接口已接入、协议验证进行中，阶段 5 整机编译正在运行。尚未下载 image6，不能宣称实板推理或实测帧率。

已完成：

- FPGA_GAME 新增 fourpoint/fpga_integer.py：真实 INT64 卷积累加、Q31 常数、两次饱和 RNE 转换；64 张审核图与旧 QDQ 的点位最大差 0.0000095367 px（浮点坐标表示差）。3 项整数边界测试通过。
- 源 QDQ SHA256：2070f71470f02982c1e616613d483e0b0bae9eec58bb653e869b64a424471269。
- src/pose6/pose6_mac16.v、pose6_requant.v：500 项独立 Fraction 生成的算术测试 + 6 组 MAC 序列通过，含负激活、停顿和 432 项累加。
- pose6_conv.v：十层卷积逐字节与整数参考一致，模拟 DDR 等待通过。日志 work_sim/pose6_conv/result.log。
- pose6_network.v、pose6_input_pool.v、pose6_decode.v：真实 S3_F000035 的 640x360 输入到 256x144 OR、全部中间张量、Resize/Concat、四点和热图 CRC 全链路通过，6696265 个模拟周期（不等于板卡实测帧率）。日志 work_sim/pose6_pipeline/result.log。
- image6 平台复用 image5 摄像头、Canny、DDR 与外设；新增嵌套 photo_axi_mux、pose6_axi_master、pose6_uart_loader、pose6_packet、image6_ft_link。
- 实际完整 image6 map 综合通过：184 RAM、50 DSP/MULT，19203 LUT4、12872 FF；最终 XLR 和时序需 place/route 报告。
- 独立探针 80 RAM、22 DSP，仅供缓存/计算核估算，不能代替完整报告。

参数导出：FPGA_GAME 的模型虚拟环境运行 tools/export-image6.py。
生成 tmp/image6_parameters/model.bin：161440 字节，CRC32 bbffdf52，SHA256 5db98c6fc5cab40ed05ed869740cca682e782d9eea3da5ab9e89b03781fd8fc1。
模型身份和元数据内嵌，权重只放 DDR；无 SD/Flash 修改。

DDR：参数 0x02000000；输入 0x02100000；各层固定区域至 0x022347ff，见 images/image6_pose_int16/model-contract.json。所有地址与旧低于 0x02000000 的图像区域分离。

协议：UART ~6L（模型）、~6I（确定性 UINT16 图片）+ LE length32 + CRC32；先回 L，再发送 payload；完成且 CRC 正确回 K，错误 E，忙 B。~6Q 查询 R/N，~6T 单张测试。只允许停机/空闲上传。FT5! kind4，640x360，payload44，输入/热图 CRC 和四组 Q14.2 坐标/UINT16 peak。实时仍用 !5、!3；!0 停止。

电脑端 FPGA_GAME 新增 fpga_points.py、image6_control.py、config.image6.json，bridge.py 支持 fpga_points，独立攻击/躲避通道，模式下不初始化 YOLO。PC 测试与游戏接入尚在完成。

硬件枚举事实：当前 Windows 发现 CH340 COM30，D2XX 列表为空，Win32_PnPEntity 未发现 FTDI VID0403。用户回复硬件按已有接线做、没有问题，不希望常规硬件反复确认。继续软件侧排查，必要的具体现场操作才提出。不要把用户的确认当作成功枚举/下载的测量。

执行日志：work_sim/pose6-map-run.log（map已PASS）；work_sim/pose6-compile-run.log（完整构建运行中）；PC outputs/fourpoint/image6/pc-tests.log。

## 最新状态（整机构建后）

- 完整 map/place/route/bitstream 均通过；XLR 31010/60800，RAM 184/256，DSP 50/160。clk_sys 建立裕量 0.189 ns、保持裕量 0.023 ns；全部 28 条时钟关系通过。
- 生成 `images/image6_pose_int16/outflow/Ti60_Image6_Pose_timing_checked.bit`（2628081 字节），SHA256 3fc8d5d2e844595b418f621f6c04e191045a441c2cb2f555012bcc82f057d1bd。
- `tools/check-image6-ft.py --reports` 和 `tools/check-image6-netlist.py` 通过，保留原寄存 IO/异步 FT 时序预算；RAM/DSP 够用，无须改 Sobel 或启用 SD。
- 五项 RTL 回归全部通过：arith、conv、pipeline、protocol、axi。AXI 验证新增 master 与原 photo_axi_mux 并发客户端、128 个事务、AW/W/B/AR/R 独立等待。没有在位流生成后修改推理 RTL。
- PC 29 项回归通过后又加入 USB 状态字节拆除测试（30 项最终回归待最终日志）；两项控制器测试通过；Node 游戏护盾/并行躲避/过期状态测试通过；真实 HTTP 服务 `/state`、游戏与 JS 路由检查通过（未启用游戏/未开硬件）。
- `bridge.py --source fpga_points` 进程未导入 Torch/YOLO；攻击和躲避独立，游戏加入三次成功躲避生成一个一次性盾，原模式保持独立。
- 新增 `FPGA_GAME/start-image6.ps1`：JTAG 身份/下载 → DDR 模型/固定输入 → 实板点位/热图 CRC → 实时启动 → 电脑游戏。任何前置失败就停止，不会用电脑模型冒充 FPGA。

硬件进展与当前阻塞：

1. 用户已连接 USB 并检查过板端 JTAG 排线。可见 ELITES 下载器序列号 FTC4XDT0，以及产品 Single RS232-HS 的接收模块，CH340 COM30 正常。两个 FT232H 均绑定 libusbK/oem291.inf，D2XX 当前为空。
2. 新增 `ft232h_usbk.py` 自动接收兼容层，只选择 Single RS232-HS，排除 JTAG 下载器，移除每个 USB 包的两字节 FTDI 状态，保留帧 CRC 验证；D2XX 可用时仍优先。实际已能打开/发送原有 USB 初始化控制，但不代表 FIFO 数据已通过。
3. FPGA 旧固件 COM30 `!V` 返回 A。已检查原 !5/!3 图像流和独立 !1 计数流；USB 应用有效字节均为 0。命令测试后恢复了原 mode3。
4. 接收端 EEPROM 只读 256 字节：word0=0010，模式位0（UART）；标准 CRC128=f634、CRC256=f32b，未通过。原始读取 SHA256 2f2e016069a635c98030802c6b1b1dee76aa25fca2860962ced2cf20020b200f，备份在 PC outputs/fourpoint/image6/receiver-eeprom-*；没有写 EEPROM，不据此假定可安全套用标准模板。`image6_receiver_eeprom.py inspect` 只读备份工具保留。
5. Efinity 全量 USB 枚举会因接收端驱动不兼容中断，`tools/image6-jtag.py` 仅在当前进程筛选 FTC4XDT0，未改 SDK/驱动。下载器 USB 已确认，但 1/3/6MHz 下复位 ID 和显式 Titanium ID 均为 0 或无效值；最新 work_sim/image6-jtag-download.log，未读到 0x10660A79，因此从未执行 image6 配置写入。
6. 未生成真实 board_test.json，未测实板帧率/实时动作精度；还需要确认两个模块到板端的实际连接及接收模块原有 FIFO 配置。下一步需要接线照片或恢复此前实际能下载、能收图的链路，再自动运行启动脚本；不能宣称任务已实板完成。

交付说明：HDL docs/image6-pose-int16.md、PC IMAGE6.md；归档入口 tools/package-image6.py，产物 releases/image6/image6_int16_prototype.zip，含位流、模型、固定测试输入和真实报告，不含训练图片/大模型。

最终范围更新：用户明确指示硬件问题由其自行解决和调试，当前只需完成软件代码。停止硬件扫描、下载和外设配置操作。软件/构建/仿真交付已完成，实板状态保留为未验证，不再将其作为本次软件交付的阻塞项。

最终 PC 回归为 33 项全部通过；另有 3 项整数算术测试、Node 游戏状态测试和 HTTP 服务检查通过。原 image5 工程未改动。源码与归档将分别记录可回退的 Git 提交和文件 SHA256。

## 2026-10-27 视频停帧诊断更新

用户反馈 image5 流畅，image6 先有红紫横条后长时间停帧；卡住时发送 Z 后四色测试图正常（用户实板观察）。转查摄像头／DDR 图像通路，不认定为空闲模型算力不足或已确证的时序错误。新增真实 image5/image6 FT 模块与外层 DDR 仲裁共存回归：空闲视频握手逐周期等同，USB 阻塞、快照及模型数据写入均未阻塞测试视频。原 UART 协议回归通过。

image6 增加只读 `~6D` 计数查询及 `tools/read-image6-video.ps1`。原 image5 和共享视频模块未修改；未操作硬件。诊断位流完整构建、28 项时序关系通过，独立命名 `outflow/Ti60_Image6_Pose_video_diag.bit`；原位流另存 `Ti60_Image6_Pose_before_video_diag.bit`。详细字段、命令、限制、SHA256 和判断方法见 `docs/image6-video-diagnosis.md`。这不是已确认修复版，下一步由用户手动下载并记录停帧过程的 JSONL。

## SD 独立推理与 HDMI 显示交付更新

本节为当前状态，前述 UART 上传版与诊断版记录保留作历史。用户已反馈诊断版画面恢复，随后授权完成 SD 加载、独立模型推理与 HDMI 四点显示。最新确认：P4 SD 接线完成但尚未实测，2 GB FAT32 卡稍后由用户复制文件；本轮只做临时 JTAG 版，不写配置 Flash，不进行硬件下载或访问。

- 原生 SD4 直接复用 image2 当前实际使用的只读接口，P4 引脚／1.8 V 约束采用最新交接包。新增 FAT32 只读文件加载，支持碎片簇链、SDSC／SDHC，加载包 `MODEL6.BIN` 为 235232 字节，包含冻结权重与固定数值自检输入。没有向 SD 写数据的路径。
- FPGA 等待 DDR 就绪后自动加载和执行数值自检，通过才启动实时推理并显示四点及三条连线。无电脑、无 FT232H 接收时持续运行。USB 忙时跳过中间结果，不阻塞推理；保留独立 Z 四色诊断。
- 重量化乘法增加流水级，数值与整数参考一致。完整构建 XLR 42599/60800、RAM 185/256、DSP 56/160；clk_sys 建立裕量 0.330 ns，全部 28 项建立／保持关系通过，CDC 无同步器警告。保留 Canny，共享 SD／摄像头／DDR 源码及 image1～5 均未修改。
- 最终临时位流 SHA256：`2825c491e8b049f7b351b32b2f41222162e6ac779f9d21f50ed53fad561760ed`。旧诊断位流单独保存，未覆盖。
- SD 九项正常／故障用例、HDMI 叠加、UART、视频共存、500 项算术边界和十层卷积输出回归通过。完整 SD 至实时推理仿真通过，并用实际外层仲裁器完成视频读写压力测试：43685 次读／21843 次写，每次 128 拍，最大请求至完成 160／166 周期；并发与 USB 背压下四次实时结果和恢复数据包均与整数参考一致。
- PC 40 项回归和 Node 游戏测试通过。`start-image6.ps1` 默认等待 SD 加载及板上自检，然后启动坐标流和电脑游戏，不从电脑上传模型。旧 UART 路径仅作为显式 `-UartLoad` 开发选项；此前实板 E 回复原因尚未确认。
- 软件交付在 `releases/image6/standalone/`，归档 `releases/image6/image6_sd_hdmi_temporary.zip`，操作说明 `docs/image6-standalone.md`。包内包含当前源提交、位流／文件哈希和测试报告；用户后续将 MODEL6.BIN 复制到卡根目录并临时下载。

本轮所有验证均在电脑上完成。实卡读取、HDMI 长期稳定性、实时帧率及动作效果未测量，不作为软件交付完成的前提，也不宣称已通过实板验收。断电后仍需重新临时下载位流。

## 串口 SD 验证及模型调试命令

按用户要求新增七个三字符 ASCII 命令：`~6S` SD 初始化／FAT32／错误快照，`~6F` 文件找到／长度／头校验／内容 CRC／读取字节数，`~6V` 模型就绪／固定输入自检／开关／忙状态／累计实时计算次数，`~6+` 开启推理，`~6-` 关闭推理，`~6R` 安全重载并重做完整自检，`~6H` 帮助。串口为 COM30、115200、8N1，不附加回车换行。

关闭后不再发起实时模型计算，在途计算安全结束；持续发送无效显示结果，避免一次性清点通知在占用的跨时钟邮箱中丢失。摄像头／显示继续运行，权重仍保留在 DDR。重载必须先关闭并等待空闲；重新加载失败不会沿用旧的模型就绪状态。重载成功后保持关闭，由用户明确开启。

本轮不修改 PC 的其他训练工作。SD 包格式、权重和固定自检数据不变。image1～5 和共享 SD4／摄像头／DDR 源文件未修改，不访问串口、USB、JTAG、SD 卡或 Flash 硬件。

新增 ASCII 格式／状态快照／UART 背压测试、真实 UART 接收器七命令测试、九项 SD 故障状态检查、HDMI 关闭清点竞争检查，以及完整 SD 至推理链路上的关闭、重载拒绝、文件缺失与恢复重试检查。最终结果与证据见交付包 reports 及 qualification.json。

当前调试版完整构建通过：XLR 43285/60800、RAM 185/256、DSP 56/160；系统建立裕量 0.176 ns，全部 28 项建立／保持关系通过，CDC 无同步器警告。位流 SHA256 为 `a79499d8409fd2cc42b75adb49983ea4a0c2a86ff71884a42ca0df19673235e2`。完整命令回复和操作顺序见 `docs/image6-standalone.md`。实板仍待用户手动下载验证。
