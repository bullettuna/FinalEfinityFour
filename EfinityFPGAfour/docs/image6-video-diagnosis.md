# image6 停帧排查（2026-10-27）

## 已有证据及边界

用户反馈：同一硬件 image5 流畅；image6 刚上电正常，随后出现红紫色横条闪动，最终长时间停帧，偶尔更新。卡住时通过 COM30 发送 `Z` 能切换到完整、无条纹的四色测试图。此项为用户实板观察，未由代理操作硬件。四色图本身是静态图，不能用来测量动态画面帧率。

image5/image6 主视频 RTL、顶层参数、引脚、PLL 设置一致。SDC 除工程名和生成时间外一致。image6 增加了模型和快照共用 DDR 的内层仲裁；外层视频仲裁、Canny、帧缓存控制均沿用 image5。当前时序报告没有负 slack；image6 `clk_sys` 最差 setup slack 为 0.189 ns，路径位于模型重定标乘法器，不能据此认定空闲时的视频停帧就是该路径造成。报告通过不等于已验证实板数据完整性。

新增 `tools/test-image6-video.ps1` 使用真实 image5/image6 FT 模块和真实外层 `photo_axi_mux`，两套独立 DDR 行为模型、128 拍视频突发及独立通道等待：

- 25,000 周期空闲对比：image6 模型无 DDR 请求，视频握手逐周期等同 image5；完成 170 次读突发、163 次写突发。
- 异步像素输入、768 字节快照、USB 接收持续阻塞：视频继续传输。
- 实际 UART 加载器和两层仲裁写入两组 16 字节模型数据，地址和数据核对通过；视频继续传输。
- 诊断数据跨域、查询、快照、串口反压和 56 字节 CRC 检查通过。

这些仿真不包含实际 DDR PHY、MIPI 电气链路和整机温度、电源条件，也没有覆盖加载完整模型后的实时推理带宽。不能由此宣称卡顿已经修复。

## 诊断版用途

新增观察器只读取已有信号，既不控制视频 ready/reset，也不启动模型或改变图像模式。image5 的源文件及共用视频模块不修改。诊断版用于区分采集帧不完整、DDR 事务停止、显示 FIFO 欠载以及人为冻结；不是已确认的修复版。新增观察逻辑会改变布局布线，因此应连同现象变化一起记录。

`~6D` 返回 56 字节：ASCII `P6D1`，12 个小端 uint32，再附前 52 字节的 IEEE CRC32。查询应独占串口；不要同时运行游戏启动脚本、上传权重或其他串口命令。上传二进制模型的过程中这些字节会被视为模型数据，不能发送诊断命令。

12 个字段依次为：

1. `sys_ticks`：96 MHz 系统计数，约 44.7 秒回绕；读取脚本用相邻差分。
2. `camera_frames`：摄像头 VSYNC 结束次数。
3. `camera_good_frames`：按帧缓存相同规则计数，恰好 518,400 个 RAW8 四像素字的帧数。只证明字数符合预期，不证明每个像素内容正确。
4. `camera_words`：摄像头有效数据字总数。
5. `display_frame_requests`：视频读端地址偏移为零的请求次数。
6. `display_buffer_changes`：读端帧缓存编号切换次数。
7. `write_buffer_changes`：摄像头写端缓存编号切换次数。
8. `bad_frames`：原帧缓存控制器的坏帧拒绝计数。
9. `display_underflows`：原显示 FIFO 欠载计数，按受影响帧计数。
10. `aux_read_requests`：快照／模型共用分支被外层仲裁接受的读请求数。
11. `aux_write_requests`：同一分支的写请求数。
12. `status`：bit0 冻结请求；bit1 DDR 校准完成；bit2 校准通过；bit3 读仲裁超时。

跨时钟累计计数通过源域寄存的 Gray 码和双级同步器读取，存在几个时钟周期的观测延迟。整包在查询时一次锁存，发送过程中不变化。缓存切换次数是总线描述符观察值，不能直接当作最终屏幕成功显示帧数。

## 手动验证

下载 `images/image6_pose_int16/outflow/Ti60_Image6_Pose_video_diag.bit`（须先由构建和时序检查生成）。关闭串口助手和游戏启动程序，保持实时画面模式，退出 `Z` 测试图；暂不加载权重。运行：

```powershell
powershell -ExecutionPolicy Bypass -File E:\Efinity_Project\EfinityFPGAfour\tools\read-image6-video.ps1 -ComPort COM30 -Seconds 60
```

若要覆盖上电正常到异常的全过程，可延长 `-Seconds`。原始计数和每秒差分保存在 `work_sim/image6_video_logs/video-*.jsonl`。脚本仅发送 `~6D`，不修改模式，不下载固件，不主动复位板卡。读取结束关闭串口。

判断顺序：

- `camera_frames` 继续增加，`camera_good_frames` 明显减少且 `bad_frames` 增长：优先查采集字数完整性与采集到帧缓存的交接。原代码会拒绝坏帧并保留上一张完整帧，能解释长时间看起来不动；尚不能区分 MIPI、跨域或具体时序原因。
- 摄像头计数停止、系统计数继续：优先查摄像头输入时钟／帧信号及接收状态。
- 有效采集持续而 `write_buffer_changes` 停止：检查 DDR 写事务和 FIFO 排空是否停住。
- `display_underflows` 增长：检查 DDR 读出与显示 FIFO 供数路径。
- `status` 指示冻结或校准异常：先解释对应状态。
- 所有计数正常但仍有条纹：字数检查不能识别内容错误，仍需抓取原始数据或对 DDR 做隔离验证；不可把它判为正常或归咎于模型。

当前结论：HDMI 独立测试正常，把重点转向摄像头／DDR 实时图像通路；尚未定位实板根因，未修改 Canny、模型结构或时钟频率。

## 本次构建记录

诊断位流已完成完整构建，28 项 setup/hold 时钟关系均通过；资源 XLR 32,440、RAM 184、DSP 50。新报告 `clk_sys` setup slack 为 0.289 ns。CDC 报告无同步器警告。这些仅是工具报告，不等价于实板故障已经消除。

`Ti60_Image6_Pose_video_diag.bit`：2,648,850 字节，SHA256 `22cae6fcd59281d1d030a156b567122aecbf592cb0674b6661c40cbc92a9e66f`。

原位流保留在同目录 `Ti60_Image6_Pose_before_video_diag.bit`，SHA256 `3fc8d5d2e844595b418f621f6c04e191045a441c2cb2f555012bcc82f057d1bd`。原交付 ZIP 未替换；诊断位流不是原 ZIP 中的位流。

## 模型启动的后续排查

用户反馈诊断版画面恢复，尚未读取诊断计数。模型启动先遇 COM30 占用；关闭串口软件后，上传头部返回 `E`，权重内容未发送。本地模型 161440 字节、CRC32 bbffdf52，与源码相符，不能据此确定板上拒绝原因。

新增 `tools/test-image6-uart-wire.ps1`，将工程实际 52 分频器、UART 接收器和实际模型常量加载器连接，以 115200/8N1 连续串行位流发送 `7e364ca076020052dfffbb`；标准位宽、8650 ns、8750 ns，以及逐字节 1 ms 间隔均被正确接收并回复 L。测试不绕过 UART 接收器，但不包含真实 USB-UART、引脚或电气条件。未发现该逻辑仿真中的头部错误。

PC 控制程序增加 `diagnose --port COM30`（仅串口读 P6D1，不打开 FT232H）、头部 2 ms 间隔及 `control-uart-*.json` 日志。原固定输入自检不跳过，头部拒绝不发送权重；37 项 PC 回归通过。间隔是排查措施，尚未确认解决板上错误。此阶段没有修改 FPGA 运行 RTL，也没有重生成或替换上述诊断位流。
