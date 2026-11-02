# image2 视频停帧：独立时序裕量与诊断候选

本版用于排查用户反馈的 `Image2_P4_MENU_20261029.bit` 上电即停帧、上方花屏问题。
现场已确认：不操作菜单／SD便异常；Z四色测试图稳定；同接线切回正常image1／image7仍正常。
这些证据将重点指向摄像头接收、DDR帧更新与实时读出链路，尚不能证明唯一根因。
原版的28项STA检查通过并未覆盖所有实际板上条件，不能据此认定原版已经稳定。

## 候选改动

- 独立工程 `images/image2_video_guard/Ti60_Image2_Video_Guard.xml`；原image2 P4工程和下载文件保留。
- 相机时钟域的额外setup约束由0.5ns收紧至0.8ns，额外hold约束由0.3ns收紧至0.6ns。
  这是要求布局布线保留更多余量，不是测得的板上抖动值；摄像头频率、PLL、DPHY tap=17和引脚不变。
- 保留原SD4、拍照、完整Canny、UART收图、菜单、白平衡和默认参数。
- 保留完整帧检查，未放宽帧长要求、未将坏帧发布为正常帧，也未绕过DDR读取。
- 增加只读摄像头／DDR计数，窗口第9行显示：`Cxxxx Gxxxx Bxxxx Uxxxx`。
  数字为计数的低16位十六进制，会循环；C=收到的相机帧，G=518400个32位字的完整帧，
  B=AXI控制器拒绝的坏帧，U=显示FIFO欠载。C/G与B来自不同观察点，可能有短暂处理延迟。
- 新增独立`~2D`查询，隔离原命令解析，避免D误触发去斑。观察器没有视频控制输出。

## 实板验证

1. **只临时JTAG下载本候选BIT**，保持同样接线和SD内容，先不拍照。
2. 看实时画面是否恢复，保持约一分钟；长按SW1约0.8秒打开原菜单。
3. 观察C/G/B/U两次，相隔约5秒；若仍异常，提供这四个值或一张窗口照片。
4. 若C增长、G不增长、B增长，重点查MIPI帧完整性；若G正常而U持续增长，重点查DDR/显示读取。
   C不增长时还要区分传感器初始化和MIPI帧同步。计数只是定位证据，不能单独证明所有像素正确。
5. 实时画面稳定后，再验证SD检查、拍照、回显、翻页与双确认删除。

无须改MODEL文件。本版仍是独立image2，不加入原7／1／5合并Flash地址表。
候选是否解决现场故障必须由实板画面和计数确认，软件检查通过不等于上板问题已解决。

## 可选串口读取

115200、8N1，无换行，发送三个字节ASCII `~2D`。
准备好的只读脚本不切换模式、不拍照、不写SD、不启动模型，也不主动用DTR／RTS复位板卡：

```powershell
& tools/read-image2-video.ps1 -ComPort COM32 -Seconds 20
```

COM32替换为当前控制串口，先关闭其他串口助手。旧P4版不支持此查询。

回复固定56字节：`P2D1`四字节包头、12个小端uint32、4字节小端CRC32。
CRC采用常规CRC32/IEEE，覆盖前52字节。12个数依次为：
sys_ticks、camera_frames、camera_good_frames、camera_words、display_frame_requests、
display_buffer_changes、write_buffer_changes、bad_frames、display_underflows、
aux_read_requests、aux_write_requests、status。
status最低4位依次为freeze、DDR calibration done、DDR calibration pass、arbiter stalled。
sys_ticks按96MHz计数，32位回绕，脚本按模2^32计算相邻差值。

## 构建与检查

```powershell
& tools/build-image2-video-guard.ps1
& tools/test-image2-video-diagnostic.ps1
& tools/test-image2-video-guard.ps1
```

`check-image2-video-guard.py`比较原算法与外围配置，检查真实网表中的观察器和
时序报告里实际应用的摄像头不确定度；不通过时不接受候选。
诊断仿真覆盖完整／不完整帧、跨域计数、UART背压快照稳定、包头和CRC、
老命令透传、前缀超时和误命令隔离；菜单／SD回归继续覆盖原功能。

曾试验1.0ns额外hold：TIMING_2/seed4发生布线拥塞，CONGESTION_1/seed4布线完成后
CSI setup/hold仍有-0.081/-0.404ns违例，两轮均拒绝交付。相关原始文件和报告保留在
`tmp/image2_video_guard_20261029/`；后续采用0.6ns额外hold与0.8ns额外setup的组合，
仍比原版0.3/0.5ns更严格，必须重新满足全部约束后才生成checked文件。

## 本次交付的离线验证

最终为 Efinity 2025.2.288 / Ti60F225 C4 / CONGESTION_1 / seed7 / effort2。
全部28项setup/hold关系非负，CDC无synchronizer警告；摄像头域额外0.8/0.6ns要求
已实际应用，扣除后setup/hold slack为+0.641/+0.017ns。
系统域+2.028/+0.028ns，像素域+0.986/+0.026ns；所有关系中最小slack为+0.017ns。
资源为41,033/60,800 XLR、127/256 RAM10、32/160 DSP。
当前BIT SHA256：`995cac1f24f3e40701070bed28d05b12ef56e2650a3349418e042ca815995e8a`。

已通过新诊断模块及CRC独立解包、命令隔离、菜单控制、窗口逐像素三拍对齐、
原UART命令兼容，以及菜单到真实SD4/FAT32/Canny存卡、回显、双确认删除与视频DDR并发仿真。
存储并发仿真使用缩小画幅，不代替实板1080p和真实SD卡验证。
最后几轮仅变更SDC／布局布线设置，复用同一份已综合网表，构建脚本检查缓存输入时间、
网表哈希和运行源码指纹，避免把中途改动混入产物。

133份既有BIT/HEX和除检查工具增加可选工程参数之外的823份既有受跟踪文件保持原字节。
旧版image2、image1/5/6/7及原7/1/5合并HEX均未替换。实板故障是否解决仍等待本次候选反馈。
