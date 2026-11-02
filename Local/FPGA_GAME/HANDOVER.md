# Soul Rider / FPGA Pose Demo 交接单

## 1. 版本快照

- 交接日期：2026-10-27
- 项目目录：`E:\Document\school_team\26Game\FPGA_GAME`
- Git 分支：`main`
- 最新已提交版本：`2eaa2e1 Add five-frame squat defense and debug feedback`
- 远程仓库：`https://github.com/PeterrrPan/FPGA_GAME.git`
- 远程状态：`main` 比 `origin/main` 领先 3 个提交
- 工作区状态：有一批未提交改动（见第 7 节），包含攻击抗噪、蹲后门控和肩宽自适应阈值，
  未提交、未推送
- 单元测试：49 项全部通过（`D:\python\python.exe -m unittest discover -s tests -v`）
- 运行时：bridge 已按最新代码重启，监听 `127.0.0.1:8765`（PID 会随重启变化）

注意：当前工作区不是 `2eaa2e1` 的完整功能状态，交接时必须连未提交改动一起保留。
提交前不要丢弃工作区修改，也不要单独推送已提交的旧版本。

## 2. 当前系统链路

```text
SC2210 摄像头
→ Ti60F225 FPGA image5 Canny
→ FT232H FT245 FIFO
→ 640×360 kind=3 packed 边缘帧
→ bridge.py 接收和 CRC 校验
→ YOLO11n-pose 推理
→ 肩部动作判定（下蹲）+ 肘部动作判定（攻击）
→ GestureFilter 多帧投票 + 蹲后攻击门控
→ action_seq / trigger_action / body_action_seq
→ 浏览器游戏或独立调试页
```

FPGA 端当前按 `preconfigured` 方式工作。PC 点击开始或进入调试模式后才打开
FT232H，不发送 `!P`、`!0` 或其他 UART 命令。

## 3. 模型信息

- 模型文件：`models/fpga_image5_best.pt`
- 大小：6,034,888 字节，约 5.75 MiB
- SHA256：`7BD069D4B6940ADCF46CD5E6D85D1A423B0B7D298056537A756BDC4902E85F15`
- 结构：`YOLO11n-pose`
- 参数量：2,874,462
- 输入计算量：约 7.601 GFLOPs（640 输入）
- 输出：1 个人体框、17 个 COCO 关键点

15 FPS 理论算力约为 114 GFLOP/s。

## 4. 当前动作判定

### 4.1 输入过滤

- 只接受 `640×360`、`kind=3` 的完整帧
- 校验帧头 CRC、负载 CRC、尺寸和序号
- 其他类型、其他尺寸和损坏帧忽略
- 没有合格帧时不运行姿态模型
- 人体框置信度低于 `bbox_conf=0.20` 时不产生动作；YOLO 推理时已按 0.20 预过滤，
  实际上常表现为 `no_person`

### 4.2 肘部动作（攻击）

- 使用左右肘和手腕关键点，索引为 7/8 与 9/10，置信度最低均为 `0.10`
- 位置使用 `joint_y - bbox_top_y`，肘与腕各自维护静息基线和最近 3 帧中值
- 手肘抬升仍是主触发；手腕必须同步达到手肘阈值的 `0.65` 倍
- 手腕最多低于手肘 `0.20` 倍稳定肩宽，避免只抬肘或手腕留在身侧时触发
- 抬肘阈值按肩宽自适应：
  - 取最近 5 个"已采纳"肩宽的中位数
  - 阈值 = clamp(中位数 × `elbow_rise_shoulder_ratio`(0.5), `14 px`, `45 px`)
  - 肩宽尚未稳定、肩点低置信度或比例设为 0 时回退到 `elbow_rise_pixels=20`
- 肩宽本身经过一致性门控（见 4.3），单帧 3 px / 300 px 这类跳变不会影响阈值
- 从本次峰值回落且在 `elbow_release_frames=2` 帧后释放；释放距离按阈值等比缩放
  （阈值 20 px 时为 8 px，阈值 40 px 时为 16 px）
- 超过 `0.5 秒` 没有有效肘部时重置基线
- 左右方向按肘部相对人体框中心的位置判断（摄像头镜像，人的右手通常判为 `left`）
- 两侧同时成立时选择上升像素更多的一侧

### 4.3 双肩动作（下蹲）

- 使用左右肩和左右髋关键点；肩点沿用 `0.10`，髋点使用独立的 `0.20` 低置信度门槛
- 使用最近 5 个有效肩、髋样本做线性拟合并计算归一化下降速度
- 左右肩速度都达到 `0.20 肩宽/秒` 时进入肩部下蹲候选
- 左右髋速度都达到 `0.12 肩宽/秒` 且累计下降达到肩宽 `5%` 时才确认真实下蹲
- 肩点下降但髋点稳定时返回 `hip_motion_below_threshold`，不触发下蹲
- 髋点低置信度时返回 `lower_body_unavailable`，只禁用下蹲，不阻断抬手攻击
- 左右肩速度差不得超过 `0.06 肩宽/秒`
- 双肩累计下移至少达到肩宽的 `8%`
- 双肩向上移动不产生玩家身体动作
- 左右肩位移差超过肩宽的 `6%` 时拒绝判定，避免单肩抬手误判
- 速度和髋部窗口连续满足 2 帧后生效，过滤单帧肩点漂移
- 回落到肩宽的 `5%` 以内时释放
- 从下蹲最低肩位回升肩宽的 `18%` 并保持 2 帧时释放，避免旧站立基线不一致导致卡住
- 超过 `0.8 秒` 没有有效肩部时重建基线
- 下蹲优先级高于肘部攻击；下蹲生效期间重置肘部跟踪

肩宽一致性门控（用于 4.2 的自适应阈值）：

- 每帧原始肩宽必须与"候选值"连续 3 帧一致（相对误差 ≤ 25%）才被采纳
- 已采纳值附近的帧持续更新采纳值，能跟上人走近/走远
- 单帧离群值直接丢弃，不进入阈值计算
- 只有采纳值才进入最近 5 帧中位数窗口
- 状态字段：`shoulder_width_px` 为当帧原始值，`shoulder_width_stable_px` 为当前采纳值

### 4.4 动作事件与门控

- 攻击使用最近 4 个动作结果投票，同一攻击方向至少 2 票才触发
- 左右攻击混合或不足 2 票时不会触发
- `no_person` / `low_bbox_confidence` 帧不再投 `stand` 票：
  窗口只按帧数老化（`GestureFilter.age()`），已有有效票不会被稀释，也不会被提前清空
- 下蹲期间直接清空攻击候选窗口，`triggered=false`
- 蹲后攻击门控（`PostSquatAttackGate`）：
  - 从 `squat` 回到 `stand` 的瞬间开始，抑制攻击 `post_squat_suppress_ms=300`
  - 抑制期结束后，还需连续 `post_squat_neutral_frames=3` 帧 `attack_action=stand`
    才重新允许攻击投票
  - 期间任何一次抬肘都会让该计数重新开始
  - 门控状态通过 `attack_gated` 字段暴露，便于调试
- 攻击冷却为全局 `600 ms`
- 保持抬肘时，冷却结束后会再次触发
- `action_seq` 只在真正触发时递增
- `trigger_action` 持久保存最近一次实际触发方向
- 浏览器使用 `trigger_action`，避免轮询错过瞬时 `action`
- `body_action` 独立保存 `stand` 或 `squat`，不占用攻击事件序号
- `body_action_seq` 只在进入 `squat` 时递增，持续保持下蹲不会重复触发
- `trigger_body_action` 持久保存最近一次身体动作
- 身体动作生效时 `attack_action=stand`，不会产生摄像头攻击

## 5. 当前游戏行为

- 人物固定在画面下方中央，不再跟随摄像头横向移动
- 所有攻击统一使用上举姿势：左方向使用 pose 5，右方向使用 pose 4
- 攻击距离限制已取消，但攻击方向必须与怪物方向一致
- 人物生命值为 `Infinity`
- 保留三颗心显示、受伤闪屏和受伤音效
- 不会触发阵亡界面
- 摄像头动作在游戏端交换左右方向：
  - `trigger_action=left` → `playerAttack(1)` → 右侧上举和右侧攻击
  - `trigger_action=right` → `playerAttack(-1)` → 左侧上举和左侧攻击
- 键盘和攻击按钮不执行这次左右交换
- 攻击姿势保持 420 ms，摄像头 `stand` 更新不能提前覆盖
- `squat` 生效时骑士显示下蹲压缩姿态
- `squat` 生效期间怪物突进命中不扣血
- `squat` 生效期间键盘、攻击按钮和摄像头攻击全部被拦截，并取消当前攻击姿势
- 怪物突进命中下蹲玩家时显示"格挡成功"并播放格挡音效，每次突进只提示一次
- 游戏端额外保留 `280 ms` 防御余量，抵抗 FPGA/YOLO 短暂丢帧

## 6. 调试模式

主菜单"继续游戏"已替换为"调试模式"。

- 入口文件：`game/debug.html`
- 进入时调用 `/api/game-start`
- 退出或按 Esc 时调用 `/api/game-stop`
- 不运行怪物、战斗或生命值逻辑
- 只显示 `/frame.png`，即 FPGA 边缘图叠加 YOLO 骨架
- 显示字段：
  - `action`
  - `body_action`
  - `act_action`
  - 防御动作参数行
  - 左右肩 5 帧归一化下蹲速度
  - FPGA FPS
  - 推理 FPS
  - 推理耗时

`act_action` 是调试页展示字段：

- `trigger_action=left` → `左攻击`
- `trigger_action=right` → `右攻击`
- 其他情况 → `None`
- 显示持续时间 `420 ms`

防御动作参数行位于 `act_action` 下方，使用 `body_action_seq` 和 `trigger_body_action`：

- `squat` → `下蹲防御`
- 其他情况 → `None`
- 显示持续时间 `420 ms`

状态 JSON（`/api/state`）中与本次改动相关的新字段：

- `attack_gated`：是否处于蹲后攻击抑制期
- `elbow_rise_threshold_px`：当帧实际使用的抬肘阈值
- `shoulder_width_px`：当帧原始肩宽
- `shoulder_width_stable_px`：一致性门控采纳后的肩宽
- `hip_drop_ratio` / `hip_confidence`：髋部下降比例和当帧髋点置信度
- `lower_body_confirmed`：双髋是否通过同步下降确认
- `post_squat_suppress_ms` / `post_squat_neutral_frames`：蹲后门控参数回显

## 7. 改动文件

本批未提交改动：

- `HANDOVER.md`（本文件重写）
- `README.md`（配置示例同步）
- `bridge.py`（丢帧老化、蹲后门控、新参数接线、状态字段）
- `config.json`（冷却 600 ms、蹲后门控、肩宽自适应与一致性参数）
- `elbow_tracker.py`（支持动态阈值，释放距离等比缩放）
- `gesture_filter.py`（`age()` 老化、`PostSquatAttackGate`）
- `pose_engine.py`（肩宽采集与门控、自适应抬肘阈值、状态字段）
- `shoulder_tracker.py`（`ShoulderWidthGate`）
- `tests/test_elbow_tracker.py`
- `tests/test_gesture_filter.py`
- `tests/test_live_controller.py`
- `tests/test_pose_engine_elbow.py`
- `tests/test_shoulder_tracker.py`

已包含在提交 `2eaa2e1` 中的相关功能：

- 玩家 `jump` 动作全局移除，只保留 `squat`
- 5 帧肩部速度下蹲判定、蹲下格挡、格挡成功提示
- 调试页 `body_action` 与下蹲防御状态行
- `body_action_seq` / `trigger_body_action`
- 3 帧肘部中值滤波、4 帧投票、2 帧释放确认

运行输出 `outputs/history.csv` 和 `outputs/live/` 已被 Git 忽略。

## 8. 已验证项

2026-10-27 交接前检查：

- Python 单元/集成测试：49 项通过
- `bridge.py` / `gesture_filter.py` 通过 `py_compile`
- bridge 已按最新代码重启，`127.0.0.1:8765` 可监听
- 此前提交上已验证：`game/index.html`、`game/debug.html`、`panel.html`
  JavaScript 语法通过；Edge 无头模式验证调试页下蹲防御行
- 本轮改动尚未做完整真机回归（见第 10 节）

此前手工/浏览器验证：

- FT232H 可只读打开并接收 640×360 kind=3
- 实际 FPGA 帧率约 18～20 FPS
- GPU 推理速度约 40 FPS，单帧约 20～25 ms
- 调试模式可自动启动识别、显示实时字段，并按 Esc 返回主菜单
- Esc 返回后 `game_active=false`
- 触发动作后上举姿势保持约 420 ms
- 同侧目标可进入 `hurt_0.png`/`hurt_1.png` 受击动画
- 连续模拟受伤 10 次后仍为 3 颗满心，未出现阵亡界面

历史数据观察（2026-10-27 实测 `outputs/history.csv`）：

- 人框检测会成片丢失，出现连续数十帧 `no_person`
- 肩宽关键点在边缘图上噪声很大，曾观察到 3 px～323 px 的原始值
- 抬肘量常落在 18～22 px，紧贴旧固定阈值 20 px，是此前"多次平举不触发"的主因
- 蹲起瞬间的起身动作曾被误判成抬肘，产生随机方向攻击，已由蹲后门控处理

## 9. 已知风险

- 人体检测仍会间歇性丢失；投票窗口只有 4 帧，长时间 `no_person` 会让已有票自然过期。
- 肩宽依赖关键点，边缘图上仍可能出现连续多帧一致的错误值（门控只能挡单帧跳变）。
- 抬肘阈值下限 14 px、上限 45 px 尚未用多距离真机数据校准；太近/太远可能偏松或偏紧。
- 蹲后门控 300 ms + 3 帧中性确认是经验值，需要真机确认手感。
- 浏览器可能缓存旧 HTML/JS，修改后需要 `Ctrl+F5` 或关闭旧标签页重开。
- 当前所有改动尚未提交，存在误丢风险。
- 真实摄像头、FT232H、FPGA 和不同光照条件仍需持续回归。
- `HP=Infinity` 依靠现有 3 颗心渲染，不会显示无限符号。

## 10. 启动和调试

```powershell
cd 'E:\Document\school_team\26Game\FPGA_GAME'
powershell -ExecutionPolicy Bypass -File .\run_demo.ps1
```

手动重启 bridge（配置文件或 Python 改动后必须重启）：

```powershell
$p = Get-CimInstance Win32_Process -Filter "Name like 'python%'" |
  Where-Object { $_.CommandLine -like '*bridge.py*' }
if ($p) { $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force } }

Start-Process -FilePath 'D:\python\python.exe' `
  -ArgumentList @('E:\Document\school_team\26Game\FPGA_GAME\bridge.py','--port','8765','--no-browser') `
  -WorkingDirectory 'E:\Document\school_team\26Game\FPGA_GAME' `
  -WindowStyle Hidden
```

地址：

- 游戏：`http://127.0.0.1:8765/game/`
- 调试模式：`http://127.0.0.1:8765/game/debug.html`
- 控制面板：`http://127.0.0.1:8765/panel`
- 状态 JSON：`http://127.0.0.1:8765/api/state`

测试：

```powershell
& "D:\python\python.exe" -m unittest discover -s tests -v
```

## 11. 建议下一步

1. 审阅工作区改动并提交本批功能（当前 13 个文件未提交）。
2. 推送 `main` 到 GitHub，当前本地领先远程 3 个提交且还有未提交改动。
3. 真机回归：
   - 不同距离下左右平举是否都能稳定触发；
   - 观察 `/api/state` 的 `shoulder_width_stable_px` 与 `elbow_rise_threshold_px`，
     确认阈值随距离变化且不来回跳；
   - 下蹲→起身后 1 秒内不应出现随机方向攻击；
   - 下蹲格挡提示仍正常。
4. 若肩宽仍频繁被判为离群，可考虑用人体框宽度作为肩宽回退值。
5. 若制作 EXE，先处理 PyInstaller 的 `RESOURCE_DIR`/`APP_DIR`、模型资源、
   可写输出目录和 `multiprocessing.freeze_support()`。

## 12. 模型独立部署结论

- 普通 MCU 无法以 15 FPS 运行当前 640 输入 YOLO11n-pose。
- 需要至少数百 GOPS 的 NPU、数 MB 运行内存和模型格式转换。
- Ti60 单独加 TF 卡不能达到当前 YOLO 效果；TF 只负责存储。
- Ti60 加带 NPU 的边缘 SoC，由 FPGA 输出 packed 边缘帧，是更现实的独立方案。
- 若只需要左右动作，可训练更小的专用模型；完整 17 点骨架仍需更强算力。
