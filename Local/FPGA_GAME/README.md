# Soul Rider FPGA Pose Demo

默认使用 `preconfigured` FT232H 模式。控制面板提供三个检测选项卡：

| detection_mode | FPGA 数据 | 用途 |
| --- | --- | --- |
| `yolo` | version=1, kind=3, 640×360 packed 边缘图 | 游戏实时姿态推理 |
| `four_point` | version=1, kind=4, 44 字节结果 | 四点调试骨架 |
| `eleven_point` | version=2, kind=5, 86 字节结果 | 十一点调试骨架 |

YOLO 模式在游戏点击开始后打开 FT232H。四点和十一点是调试模式，选中后会自动接收对应 kind，不要求先启动游戏。其他宽度、类型或计数器帧会被忽略。

模式选项卡只切换接收和解码类型，不通过 COM30 向 FPGA 发送模式命令。切换前应让 FPGA 输出对应包类型。当前 image7 的 640×360 模型输出为 `version=2, kind=5`。

## 启动

```powershell
.\run_demo.ps1
```

已确认 FPGA 与训练集一致，因此实时模式不会再次执行 image5 Canny。
接收链路不发送 `!P`、`!0` 或任何 UART 命令。

需要回退到文件夹图片模式时，直接指定输入目录：

```powershell
.\run_demo.ps1 -InputDir "D:\images\pose_demo"
```

浏览器会打开游戏；控制面板：

```text
http://127.0.0.1:8765/panel
```

文件夹模式仍可在控制面板中更换目录。FT232H 模式只允许暂停和继续。

主要配置位于 `config.json`：

```json
{
  "source_mode": "ft232h",
  "detection_mode": "yolo",
  "ft232h_serial": "",
  "ft232h_width": 640,
  "ft232h_height": 360,
  "ft232h_kind": 3,
  "keypoint_conf": 0.1,
  "lower_body_point_conf": 0.2,
  "elbow_rise_pixels": 20,
  "elbow_rise_shoulder_ratio": 0.5,
  "elbow_rise_min_pixels": 14,
  "elbow_rise_max_pixels": 45,
  "wrist_rise_elbow_ratio": 0.65,
  "wrist_max_below_elbow_ratio": 0.2,
  "shoulder_width_confirm_frames": 3,
  "shoulder_width_agreement_ratio": 0.25,
  "elbow_release_pixels": 8,
  "gesture_confirm_frames": 2,
  "attack_confirm_window_frames": 4,
  "attack_confirm_min_votes": 2,
  "attack_keypoint_median_frames": 3,
  "elbow_release_frames": 2,
  "attack_cooldown_ms": 600,
  "shoulder_speed_window_frames": 5,
  "shoulder_speed_threshold_ratio": 0.2,
  "shoulder_min_drop_ratio": 0.08,
  "shoulder_hip_speed_threshold_ratio": 0.12,
  "shoulder_hip_min_drop_ratio": 0.05,
  "shoulder_release_ratio": 0.05,
  "shoulder_symmetry_ratio": 0.06,
  "shoulder_confirm_frames": 2,
  "human_confidence_threshold": 0.65,
  "arm_rule_weight": 0.70,
  "arm_model_weight": 0.30,
  "combined_confidence_threshold": 0.55
}
```

`ft232h_serial` 留空时只允许系统中存在一个 FT232H 设备；存在多个设备时
必须填写精确序列号。当前模块序列号为空时，程序会在确认仅有一个
FT232H 后按设备索引打开。

YOLO 模式只在网页进入游戏场景后打开 FT232H；返回主菜单时停止读取并关闭设备。四点/十一点调试模式选中后自动读取，暂停时关闭数据源。

## 单实例与复用

同一台电脑只允许运行一个 `SoulRiderBridge`。程序启动时会先检查
`http://127.0.0.1:8765/state`，再获取 Windows 命名互斥；已有实例时只打开
现有页面，不会再打开第二个 FT232H 句柄。

其他脚本需要姿态数据时应读取现有 HTTP 接口，而不是直接打开 FT232H：

```text
GET  http://127.0.0.1:8765/state
GET  http://127.0.0.1:8765/history
POST http://127.0.0.1:8765/api/game-start
POST http://127.0.0.1:8765/api/game-stop
```

排查设备占用时运行：

```powershell
python .\ft232h_source.py --list
```

如果输出包含 `flags=1`，表示 FTDI 设备已被其他进程打开。

## 运行日志

日志保存在程序目录的 `logs/sessions/`，不会写入用户目录或 C 盘。每次测试会话
生成一个独立目录：

```text
logs/
  sessions/
    latest_session.txt
    session_0004_20261030_113000/
      session.json
      bridge.jsonl
      game.jsonl
```

- `bridge.jsonl`：FT232 打开/读取异常、FPGA 发来的原始数据块和解析帧、动作识别及攻击门控事件。
- `game.jsonl`：网页收到的动作、事件发送后的游戏接收、攻击被拦截原因、实际开始攻击和怪物命中结果。
- `session.json`：本次测试的起止时间、结束原因、配置摘要和各事件数量。

每次通过 `START_SOULRIDER.cmd` 打开测试会建立新会话，关闭游戏网页时结束会话。
默认只保留最近 3 次测试，即第 4 次开始后会保留第 2、3、4 次并删除第 1 次。
可通过 `config.json` 的 `log_keep_sessions` 调整。

FT232 的 kind4/kind5 小包默认记录完整十六进制内容；kind3 大图记录 SHA-256、
首尾预览和帧头信息。可通过 `ft232_log_payload_bytes` 调整完整内容阈值。

## 姿态诊断台

游戏内调试页提供动作、校准、关键点、事件、调参和链路六个页签，可查看左右肘
基线、抬升量、动态阈值、确认票、冷却、校准原因、逐点质量、动作拦截阶段、
CRC、序列缺口和重连状态。

在线调参支持临时应用、保存为默认和恢复默认。预览可冻结而不中断后台读取，
并可导出最近 10 秒诊断 JSON。

## 动作规则

- 骑士固定在画面下方中央，不跟随摄像头人体横向移动。
- 记录手肘相对人体框顶部的位置，先对最近 3 帧肘部 Y 坐标取中值，过滤单帧关键点尖峰。
- 单侧手肘从静止基线向上移动至少 20 像素时进入攻击候选。
- 手肘从本次最高点回落至少 8 像素，并连续保持 2 帧后才解除该侧动作。
- 手肘与手腕分别维护静息基线和最近 3 帧中值，最低置信度均为 `0.10`。
- 手腕抬升阈值按手肘阈值的 `0.65` 倍计算，必须与手肘同时成立。
- 手腕允许低于手肘，但不得超过稳定肩宽的 `0.20` 倍，用于排除只抬肘或手垂在身侧的误触发。
- 左右方向按手肘相对人体框中心的位置判断，不依赖人体解剖左右。
- 双臂同时抬起时选择向上移动像素更多的一侧。
- 左右攻击统一使用游戏原有的上举姿势：左攻击使用 pose 5，右攻击使用 pose 4。
- 摄像头左右动作在游戏端交换方向；键盘和按钮攻击方向保持不变。
- `action_seq` 增加时使用独立的 `trigger_action` 确定攻击方向，避免浏览器轮询错过瞬时动作帧。
- 同侧怪物在画面内任意距离都会被击中。
- 实时模式使用 4 帧攻击窗口，同一方向至少获得 2 票后触发第一次攻击。
- 左右方向混合、孤立尖峰或不足 2 票的动作不会触发攻击。
- 下蹲状态会立即清空攻击候选窗口。
- 持续抬肘时，每次攻击后进入 1 秒冷却，冷却结束会再次触发攻击。
- 使用最近 5 个有效肩部样本做线性拟合，计算左右肩的归一化下降速度。
- 下蹲状态连续确认后才启用下蹲后攻击门控，门控最长约 1 秒。
- 肩部持续向上移动超过肩宽阈值时自动重新建立肩部基线。
- 游戏开始会等待最多 3 秒的中立校准结果，未完成时保持等待姿态校准。
- 十一点模式按 `fpga_point_conf` 过滤低分点，并检查肩宽、人体高度、中心跳变和
  连续稳定帧；连续异常 `500 ms` 后会清空全部动作状态并重新校准。
- 肩宽、中心位置和人体高度使用最近 3 帧中值；单帧异常只跳过该帧，连续 2 帧
  异常才判定骨架无效。
- 中立校准使用约 1 秒滑动窗口，要求有效帧和中立帧比例达到 70%，不允许连续
  超过 2 帧异常，单次抽动不会清空已有进度。
- 人体/抬手模型尚未凑满 18 帧时只阻止动作，不阻止几何有效帧完成校准。
- 状态为 `stream_lost` 时清空当前骨架和模型窗口显示；这不是“正在校准”，
  应先检查 FT232H 枚举、USB 连接和数据流。
- 短暂丢流会在 `1500 ms` 内保留运动基线，避免一次 D2XX 重连就清空模型窗口。
- 下蹲门控超时后不直接恢复攻击，而是退回校准状态。
- 首次打开游戏或调试页时，如果没有本地模式偏好，会读取 bridge 当前 kind 模式。
- 加载过程中按 Esc 会取消旧的进入游戏任务，窗口失焦会清除按键防御状态。
- 进入下蹲需要同时满足肩部和髋部证据：左右肩下降速度都达到 `0.20 肩宽/秒`，累计下移至少达到肩宽的 `8%`。
- 左右髋也必须同步下降，速度至少 `0.12 肩宽/秒`，累计下移至少达到肩宽的 `5%`。
- 髋部关键点最低置信度为 `0.20`；髋点不可靠时只禁用下蹲，不影响左右抬手攻击。
- 双肩位置差不得超过肩宽的 `6%`，避免单肩下移被误判为身体动作。
- 下蹲确认需要连续 2 帧满足条件，过滤单帧肩点漂移；进入下蹲后速度降到 0 不会释放。
- 双肩回落到基线下肩宽的 `5%` 以内时释放下蹲。
- 从下蹲最低肩位回升肩宽的 `18%` 并保持 2 帧也会释放，避免起立位置与旧基线不一致时卡在下蹲。
- 身体动作优先于肘部攻击；生效期间不触发摄像头攻击，游戏中的怪物突进伤害也会被忽略。
- 下蹲期间拦截所有玩家攻击入口，包括键盘、攻击按钮和摄像头动作，并取消尚未结束的攻击姿势。
- 怪物突进命中下蹲玩家时不扣血，每次突进只提示一次“格挡成功”并播放格挡音效。
- 游戏端额外保留 280 ms 防御余量，避免 FPGA/YOLO 短暂丢帧造成状态闪烁。
- 调试模式的防御动作参数行位于 `act_action` 下方，使用独立 `body_action_seq`，进入 `squat` 时显示“下蹲防御”，420 ms 后恢复 `None`。
- 调试页同时显示左右肩 5 帧归一化速度，便于现场调阈值。

## 人体与抬手模型辅助仲裁

十一点模式并行运行两个轻量模型，成熟规则仍是几何与状态机主干：

- 人体置信度模型低于阈值时，不进入抬手或下蹲判定。
- 抬手模型输出左手、右手、未抬手三类概率和抬手置信度。
- 人体模型完成 18 帧窗口之前显示 `model_warming_up`，不会产生攻击。
- 成熟肘部/腕部规则没有候选时，模型不能单独触发攻击。
- 模型和成熟规则左右方向冲突时直接禁止攻击。
- 方向一致时，默认按成熟规则 `0.70`、模型 `0.30` 加权。
- 融合置信度低于阈值时不触发攻击。
- 下蹲仍只由成熟肩部/髋部规则判断，模型不参与下蹲分类。

调试页面“调参”标签会读取以下在线参数：

| 参数 | 默认值 | 用途 |
| --- | ---: | --- |
| `human_confidence_threshold` | 0.65 | 人体门卫阈值 |
| `arm_rule_weight` | 0.70 | 成熟肘腕规则权重 |
| `arm_model_weight` | 0.30 | 左右手模型权重 |
| `combined_confidence_threshold` | 0.10 | 融合抬手最低置信度 |
| `model_side_mirrored` | 1 | 将人体解剖左右模型映射为画面左右规则 |
| `arm_model_enabled` | 0 | 关闭时只使用成熟肘腕规则判断左右手 |

模型训练使用人体解剖左右，成熟规则使用画面左右，因此默认开启
`model_side_mirrored=1`。如果现场左右方向仍相反，可在调参页设为 `0` 对照检查。

`arm_model_enabled=0` 时，人体置信度模型仍负责人体存在性门卫，但左右手方向
完全由成熟肘腕规则决定；模型不再参与左右方向、冲突判断、镜像或融合分数。
调试页“启用左右手模型”复选开关可直接切换。

人体置信度低于阈值时会拦截抬手，但成熟肩部/髋部规则已经确认下蹲时，
`squat` 仍优先输出，不会被人体模型覆盖。身体动作确认后再按原有下蹲门控
暂停攻击。

重新训练模型：

```powershell
python .\train_pose_model.py
```

当前严格留出结果：人体准确率 `100%`、空场景召回 `100%`、抬手三分类准确率 `94.8%`。
训练和测试录制文件不重叠，但仍来自同一批采集环境。

## 文件

- `ft232h_source.py`：FT232H 只读接收、FT5! 组帧与 CRC、kind3/kind4/kind5 解码。
- `gesture_filter.py`：动作确认和 1 秒攻击冷却。
- `pose_model.py`：人体门卫、左右手模型加载和规则加权仲裁。
- `train_pose_model.py`：人体与左右手模型训练和严格留出评估。
- `models/eleven_point_model.npz`：当前人体与左右手模型权重。
- `bridge.py`：三模式切换、实时推理、调试骨架、HTTP 桥接和控制命令。
- `pose_engine.py`：image5 边缘检测、YOLO 推理、动作分类。
- `game/`：复制后的 Soul Rider 游戏。
- `models/fpga_image5_best.pt`：最终 pose 模型。
- `outputs/live/`：当前原图、边缘图和 YOLO 骨架。
- `outputs/history.csv`：循环识别历史。

## 已验证

- FT232H 只读打开成功；未检测到数据流时保持等待状态。
- 帧解析、头/负载 CRC、kind3/kind4/kind5 过滤和动作去抖单元测试通过。
- version=2、kind=5、86 字节 payload、11 点解码和 640×360 骨架渲染测试通过。
- 控制面板三选项卡、模式切换请求、桌面和移动端布局通过 Playwright 检查。
- GPU CUDA 环境可用。
- Edge/Playwright 实际打开游戏并点击开始。
- 当前 `pic` 目录的 12 张回归图中，7 张明确单臂动作正确触发，5 张双臂姿势或无效姿势保持站立。
- 游戏 HUD 可显示“右平举”，骑士执行对应骨架动作。
- 控制面板原图、边缘图、YOLO 17 点预览均成功加载。
- 页面无 JavaScript 错误。

验证截图：

- `outputs/browser_game_action_clean.png`
- `outputs/browser_panel.png`
- `outputs/browser_pic_relaxed.png`

## 测试

```powershell
python -m unittest discover -s tests -v
python .\ft232h_source.py --list
python .\ft232h_source.py --seconds 3
python .\ft232h_source.py --kind 5 --seconds 3
python .\bridge.py --no-browser --detection-mode eleven_point
```
