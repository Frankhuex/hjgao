# 音效系统（Sfx）设计文档

- 状态：设计完成（含 2026-09-29 三次反馈修订：3D 交互音全端播放、2D 翻牌仅翻动者端、R3–R5 音高抖动、悬停范围扩充、新增确认/入堆/出堆音）
- 日期：2026-09-29
- 关联文档：[godot-472-and-godot-ai-mcp.md](godot-472-and-godot-ai-mcp.md)、[counter-design.md](counter-design.md)

## 1. 需求清单（原始需求整理）

音源已就位：`res://sounds/` 下 5 个 WAV（44.1kHz 立体声 Int16，约 0.5s，`loop_mode=0` 不循环，适合一次性播放）：
`翻动牌.wav`、`拿起牌.wav`、`放下牌.wav`、`洗牌.wav`、`确认.wav`。

| 编号 | 场景 | 音效 | 音高 | 播放端 |
| --- | --- | --- | --- | --- |
| R1a | 所有原生 UI 按钮，鼠标移上去时 | `翻动牌.wav` | 固定 | 仅本端 |
| R1b | 牌堆 2D 查看器内的牌（UICard），鼠标移入时 | `翻动牌.wav` | 固定 | 仅本端 |
| R1c | 计数器 3D 加号/减号按钮，鼠标移入时 | `翻动牌.wav` | 固定 | 仅本端 |
| R6 | 所有原生按钮被**按下**时（**除**牌堆查看器六大理牌按钮外，已确认 Q9：按下即响、无成功门控） | `确认.wav` | 固定（已确认 Q11） | 仅本端 |
| R2 | 牌堆查看器内**六大理牌功能**（升序/降序/洗牌/全部翻正面/全部翻背面/逐一翻面）按下后，**等操作成功** | `洗牌.wav` | ±1 半音随机 | 仅本端（查看器私有） |
| R3 | 打牌模式下，左键拿起牌**成功**（3D） | `拿起牌.wav` | ±1 半音随机 | **全端** |
| R3 | 打牌模式下，左键放下牌**成功**（3D，放到桌面） | `放下牌.wav` | ±1 半音随机 | **全端** |
| R7 | 牌**放入牌堆**成功（3D 塞牌，已确认入堆用洗牌音替代放下音） | `洗牌.wav` | ±1 半音随机 | **全端** |
| R8 | 牌**从牌堆取出**（3D 生成到桌面，含批量抽取；已确认 Q10：批量同帧合并为一声） | `放下牌.wav` | ±1 半音随机 | **全端** |
| R4 | 左键开始拖动牌堆或计数器**成功**（3D） | `翻动牌.wav` | ±1 半音随机 | **全端** |
| R4 | 左键放下牌堆或计数器**成功**（3D） | `放下牌.wav` | ±1 半音随机 | **全端** |
| R5-3D | 右键在 3D 场景**成功**翻动牌 | `翻动牌.wav` | ±1 半音随机 | **全端** |
| R5-2D | 右键在 2D 场景**成功**翻动牌 | `翻动牌.wav` | ±1 半音随机 | **仅翻动者本端** |

半音换算：±1 半音 = `pitch_scale ∈ [2^(-1/12), 2^(1/12)] ≈ [0.9439, 1.0595]`。

播放端原则（已确认）：**3D 桌面上的物理动作（拿起/放下/拖动/翻牌/入堆/出堆）动画全端可见，音效全端播放**；
**2D 查看器是本端私有界面，其中发生的一切（悬停、按下、理牌、翻牌）只有本端能看见，音效仅本端播放**。

## 2. 现状调研（音效挂点的"成功"判定分析）

### 2.1 关键结论：request 返回 true ≠ 操作成功

- `OwnerMux.request_own()` / `request_release()` 返回 true 只表示"申请已发出"，服务器仍可能拒绝
  （`board_locked`、被他人抢占）。
- **真正的成功判定点是 `_set_owner` RPC 广播回包触发的 `OwnerMux.on_owner_change` 信号**，
  **所有端**都会收到（`call_local` 广播），这正是"全端播放"的实现基础。
- 例外：R6 按下音无成功语义，按下即响（Q9），不做门控。

### 2.2 拖起/放下的全端判定（R3/R4，[dragger.gd](../dragger.gd)）

`on_owner_change` 在每个端的 `Dragger.check_and_up_down()`（信号首个回调）都会触发。
给 Dragger 新增占用状态跟踪：

```gdscript
func is_being_dragged() -> bool:   # "有任何人正在拖动"（全端语义一致）
    return _owner_mux.is_owned() and _owner_mux.purpose == Const.Purpose.DRAG
```

在 `check_and_up_down()` 里对比前后状态，检测 **false→true（拖起）/ true→false（放下）** 的边沿，
每个端独立、同步地感知同一条所有权广播：

| 场景 | 状态边沿 | 播放 |
| --- | --- | --- |
| 我的拖起申请获批 | false→true | 拿起（卡）/ 翻动（牌堆、计数器），全端 |
| 申请被服务器拒绝（他人先抢占/清场锁） | 无边沿 | 不播放 ✓ |
| 我的放下申请获批 | true→false | 放下（放到桌面），全端 |
| 塞回牌堆 | 无边沿，见 2.3 | 洗牌音，全端 |

- 抽牌、计数器加减等瞬时事务占用的是 `PILE_OUTPUT_*` / `COUNTER_*` purpose，
  不满足 `purpose == DRAG`，**天然不会误触发拖动音效**。
- 清场/换库期间的强制释放（`release_local_interaction()`）与批量删节点发生在
  `clear_table_in_progress == true` 之后（[deck_change.gd](../deck_change.gd) L84-89 同样先置锁再清），
  放下音效用 `Util.board_locked()` 门控即可全端一致地静音；暂停菜单的强制释放不关门控——
  此时卡牌确实会落下（服务器 tween 回地面并同步），音效与画面一致。

### 2.3 牌入堆/出堆的全端判定（R7/R8）

**入堆（R7）**：塞牌走 `check_into_pile()` → 收牌事务，服务器端
[card_sorter.gd](../card_sorter.gd) `server_collect_card_into_pile()` **直接 `queue_free()` 卡牌节点**，
卡牌的 OwnerMux 全程保持 DRAG 占用、不发生释放广播。因此：

- 不能用 2.2 的 true→false 边沿检测（无边沿），也**不做**乐观播放；
- 用 **`Card._exit_tree()` 检测**：节点被回收时若 `is_being_dragged()` 仍为 true，
  说明这张牌是"塞回牌堆"时被删除的（正常放下不会删节点）→ 全端播放**洗牌音**（R7）。
  MultiplayerSpawner 保证节点在所有端同步回收，各端 `_exit_tree` 天然对齐；
  清场/换库的批量删除被 `Util.board_locked()` 门控静音；断线/退出房间时残留占用的清理
  用 `session_active` 守卫静音。

**出堆（R8）**：所有抽牌路径（左键牌堆顶、热点"底"/"随"、查看器批量抽取）最终都经由
[pile_card_spawner.gd](../pile_card_spawner.gd) `server_spawn_card_by_IDs()` 生成 3D 牌，
且 `Card.tscn` 全项目**仅此一处实例化**。因此用 **`Card._ready()` 检测**：
卡牌节点在每端被 MultiplayerSpawner 同步实例化 → 各端本地播放**放下音**，无需任何 RPC。

- 批量抽取 N 张时各端在同一帧内实例化 N 张 → Sfx 对 `SPAWN` 做**同帧合并**（Q10）：一次操作一声，
  逐张单抽仍是一张一声。
- 牌堆中的牌只是数据（无节点），出堆前不出堆后都无"拿起"语义，出堆 = 牌落到桌旁 = 放下音。

### 2.4 翻牌的成功判定（R5）

- `CardDatabase.on_flip` 是**全局无参数**信号，每次 `sync_flip_status` 广播都会触发，
  不能直接"收到信号就响"（N 张牌全翻会响 N 次，且其他玩家的翻牌也会误触发）。
- **3D（全端播放）**：[card.gd](../card.gd) `check_and_flip()` 每次收到 `on_flip` 都会刷新所有 3D 牌；
  只有"本牌新状态对应的旋转角 ≠ 当前旋转角"的那张牌才是真正翻动的牌（其余牌目标角与当前角相同）。
  在该判定分支内播放，全端可闻（与翻牌动画全端可见一致）。
- **2D（仅翻动者本端）**：[ui_card.gd](../ui_card.gd) `update_ui()` 用 `_last_is_front` 与新状态比较，
  且只有"本牌自己右键申请"的那次（武装标志，见 5.4）才播放——查看器是本端私有界面，天然只在本端发声。

### 2.5 查看器六大理牌功能（R2，[deck_viewer_ui.gd](../deck_viewer_ui.gd)）

| 按钮 | 成功时机 | 播放方式 |
| --- | --- | --- |
| 升序 / 降序 / 洗牌 | 纯本地子节点重排，不可能失败，回调结束即成功 | 按下回调内直接播放 |
| 全部翻正面 / 全部翻背面 / 逐一翻面 | 走 `request_flip_to` / `request_flip` RPC，服务器可能拒绝（锁/无变化） | 先"武装"，等 `on_flip` 到达再播放 |

- 查看期间牌堆被 `PILE_VIEW` 独占，牌堆内牌的 ID 不可能同时以 3D 牌存在于桌面，
  因此 `on_flip` 触发期间几乎只有本查看器的翻面请求能改变状态，武装判定可靠。
- `server_flip_to` 对"状态无变化"的牌直接跳过不发广播：全部翻正面时若所有牌已是正面 →
  无 `on_flip` → 不响（正确：操作未产生任何效果）。
- 六个按钮**排除在 R6 确认音之外**（它们有自己的成功音），否则按下会连响两声。

### 2.6 悬停音与按下音的覆盖面（R1/R6）

| 对象 | 悬停音（R1） | 按下确认音（R6） |
| --- | --- | --- |
| 原生 UI 按钮（主菜单/暂停菜单/聊天发送/两个查看器按钮/ConfirmationDialog 内部按钮/CheckBox） | Autoload 监听 `SceneTree.node_added`，对所有 `BaseButton` 自动连接 `mouse_entered` | 同一钩子自动连接 `pressed`；**六个理牌按钮除外**（加入 `sfx_no_confirm` 组，见 5.5） |
| UICard（牌堆 2D 查看器内的牌） | [ui_card.gd](../ui_card.gd) 已连接 `mouse_entered`（tooltip 用），回调中追加播放 | —（UICard 不是按钮，无按下音） |
| 计数器 3D 加/减按钮 | 3D 按钮是 `StaticBody3D` 上的 CollisionShape3D，**没有**逐形状的 mouse_entered；利用物理拾取会向 `_input_event` 投递 `InputEventMouseMotion` 的特性，按 `shape_idx` 跟踪悬停形状（详见 5.6） | —（非原生 UI 按钮） |

## 3. 总体架构

```
Autoload Sfx（新增 sfx_manager.gd）
 ├─ 播放：AudioStreamPlayer 对象池（8 个，轮转），非定位播放
 ├─ 按钮钩子：node_added 自动为所有 BaseButton 连 mouse_entered（悬停）与 pressed（确认，组排除）
 ├─ 合并：SPAWN 同帧合并（批量抽牌一声）
 ├─ 记录：_history 环形数组（任何模式都记录，供 headless 测试断言）
 └─ headless 守卫：DisplayServer.get_name() == "headless" 时不实际出声
        ▲ play() 调用
        │
Dragger（跟踪 is_being_dragged 边沿，全端一致）   DeckViewerUI / UICard / Card / Counter
  3D 拖起/放下；Card._ready（出堆）/ _exit_tree（入堆）  3D/2D 翻面判定、悬停、六大理牌音
```

设计原则：

1. **单一出口**：所有声音都经 `Sfx.play()`，键值集中定义，禁止散落 `AudioStreamPlayer`。
2. **成功语义**：3D 物理动作只在状态落地（广播边沿/状态比对）时响；R6 按下音是 UI 反馈、无成功语义，按下即响。
3. **播放端与可见性一致**：3D 桌面物理动作全端播放；2D 查看器内一切音效仅本端播放。
4. **非定位播放**：本项目是上帝视角共享桌面，走非定位 `AudioStreamPlayer`，不做 3D 衰减。
5. **测试可断言**：headless 下不出声但记录 `_history`，测试无需真实音频设备。

## 4. 新增文件：`sfx_manager.gd`（Autoload `Sfx`）

```gdscript
class_name SfxManager
extends Node

enum Snd { HOVER, CONFIRM, PICKUP_CARD, DROP_CARD, PICKUP_OBJECT, DROP_OBJECT,
    SHUFFLE_OK, PILE_IN, SPAWN, FLIP }

const SEMITONE := 1.0594630943592953  # 2^(1/12)
const POOL_SIZE := 8
const HOVER_MIN_INTERVAL_MSEC := 50   # 悬停最小间隔，鼠标扫过按钮排/牌列时不机关枪
const HISTORY_MAX := 64
const GROUP_NO_CONFIRM := &"sfx_no_confirm"   # 加入此组的按钮按下不响确认音

const _STREAMS := {
    Snd.HOVER:         preload("res://sounds/翻动牌.wav"),
    Snd.CONFIRM:       preload("res://sounds/确认.wav"),
    Snd.PICKUP_CARD:   preload("res://sounds/拿起牌.wav"),
    Snd.DROP_CARD:     preload("res://sounds/放下牌.wav"),
    Snd.PICKUP_OBJECT: preload("res://sounds/翻动牌.wav"),
    Snd.DROP_OBJECT:   preload("res://sounds/放下牌.wav"),
    Snd.SHUFFLE_OK:    preload("res://sounds/洗牌.wav"),
    Snd.PILE_IN:       preload("res://sounds/洗牌.wav"),
    Snd.SPAWN:         preload("res://sounds/放下牌.wav"),
    Snd.FLIP:          preload("res://sounds/翻动牌.wav"),
}
# 除悬停/确认外全部 ±1 半音随机抖动（Q11：确认固定）
const _VARY_PITCH := { Snd.PICKUP_CARD: true, Snd.DROP_CARD: true, Snd.PICKUP_OBJECT: true,
    Snd.DROP_OBJECT: true, Snd.SHUFFLE_OK: true, Snd.PILE_IN: true, Snd.SPAWN: true, Snd.FLIP: true }
# 同帧合并：批量抽牌 N 张同帧生成只响一声（Q10）
const _COALESCE_FRAME := { Snd.SPAWN: true }
const _VOLUME_DB := { Snd.HOVER: -6.0 }

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_hover_msec := 0
var _last_play_frame: Dictionary = {}
var _history: Array[String] = []      # 测试断言用：记录"枚举名|实际pitch"
var _headless := false

func _ready() -> void:
    _headless = DisplayServer.get_name() == "headless"
    for i in POOL_SIZE:
        var p := AudioStreamPlayer.new()
        p.bus = &"Master"
        add_child(p)
        _players.append(p)
    get_tree().node_added.connect(_on_node_added)

func play(snd: Snd) -> void:
    if _COALESCE_FRAME.get(snd, false):   # 同帧合并（合并发生在记录前，测试也只看到一条）
        var frame := Engine.get_process_frames()
        if int(_last_play_frame.get(snd, -1)) == frame:
            return
        _last_play_frame[snd] = frame
    var pitch := randf_range(1.0 / SEMITONE, SEMITONE) if _VARY_PITCH.get(snd, false) else 1.0
    _history.append("%s|%.4f" % [Snd.keys()[snd], pitch])   # headless 也记录，环形裁剪
    if _headless: return
    if snd == Snd.HOVER and Time.get_ticks_msec() - _last_hover_msec < HOVER_MIN_INTERVAL_MSEC: return
    _last_hover_msec = Time.get_ticks_msec()
    var player := _players[_next_player]
    _next_player = (_next_player + 1) % POOL_SIZE
    player.stream = _STREAMS[snd]
    player.volume_db = float(_VOLUME_DB.get(snd, 0.0))
    player.pitch_scale = pitch
    player.play()

func history_contains(tag: String) -> bool:
    return _history.any(func(e: String): return e.begins_with(tag))

# R1a/R6：自动为一切 BaseButton 挂悬停音与按下确认音（节点释放时连接自动断开）
func _on_node_added(node: Node) -> void:
    var button := node as BaseButton
    if button == null: return
    button.mouse_entered.connect(func():
        if not button.disabled:
            play(Snd.HOVER))
    button.pressed.connect(func():
        if not button.is_in_group(GROUP_NO_CONFIRM):   # 点击时检查（连接早于设组，见 5.5）
            play(Snd.CONFIRM))
```

要点：

- `project.godot` 增加：`[autoload]` 下 `Sfx="*res://sfx_manager.gd"`（排在 `_mcp_game_helper` 之后）。
- 带 `class_name SfxManager`，调用处直接用全局名 `Sfx.play(...)`，无 unsafe 警告问题。
- 节点释放时其对外信号连接由引擎自动清理，`node_added` 钩子无需手动断连。
- 悬停播放条件 `not button.disabled`：禁用按钮（如清场进行中的 ClearTableButton）不给反馈；
  禁用按钮无法触发 `pressed`，确认音天然不会响。
- headless 下 `_history` 照常记录（`_headless` 判断放在播放前而非记录前）。

## 5. 既有文件修改

### 5.1 [dragger.gd](../dragger.gd)：3D 拖起/放下成功音效（R3/R4，全端）

`config()` 增加末位可选参数 `sound_profile: String = "object"`，存为 `_sound_profile`。

```gdscript
var _was_being_dragged := false

func is_being_dragged() -> bool:
    return _owner_mux.is_owned() and _owner_mux.purpose == Const.Purpose.DRAG

func check_and_up_down():   # 每端收到 on_owner_change 都会执行
    var being_dragged := is_being_dragged()
    if being_dragged and not _was_being_dragged:
        Sfx.play(Snd.PICKUP_CARD if _sound_profile == "card" else Snd.PICKUP_OBJECT)
    elif not being_dragged and _was_being_dragged and not Util.board_locked(self):
        Sfx.play(Snd.DROP_CARD if _sound_profile == "card" else Snd.DROP_OBJECT)
    _was_being_dragged = being_dragged
    if i_am_dragging():
        Util.tween_y(_parent, dragging_y, up_down_duration)
    elif Util.is_server(self) and not _owner_mux.is_owned():
        Util.tween_y(_parent, Util.safe_call_float(_ground_y_getter), up_down_duration)
```

注意：

- 原有升起/回位动画逻辑原样保留（放后追加，不改变行为）。
- 每个端独立跟踪同一条所有权广播的边沿，因此**全端同步发声**，无需新增任何 RPC。
- 清场/换库的强制释放与删节点发生在锁内置位之后，`Util.board_locked()` 门控全端一致静音；
  暂停菜单强制释放不关门控（卡牌此时确实落下，音画一致）。
- 节点 `_ready` 时 `_was_being_dragged` 初始为 false；晚加入者不会为"加入前已在拖动"的状态补发声
  （无广播边沿），可接受。

[card.gd](../card.gd) `_ready()` 改为
`_dragger.config(_owner_mux, UP_DOWN_DURATION, DRAGGING_Y, func(): return _card_sorter.get_drop_y(), "card")`；
pile.gd / counter.gd 不传（默认 `"object"`）。

### 5.2 [card.gd](../card.gd)：出堆音 + 入堆音 + 3D 翻牌音（R8/R7/R5-3D，全端）

```gdscript
func _ready():
    ...
    Sfx.play(Snd.SPAWN)   # R8：Card.tscn 全项目仅 spawner 实例化，_ready 即"从牌堆取出"

func _exit_tree() -> void:
    if is_instance_valid(_description_tooltip):
        _description_tooltip.hide_for(self)
    var game: GameSession = get_node_or_null("/root/Game")
    if _dragger.is_being_dragged() and game != null and game.session_active \
            and not Util.board_locked(self):
        Sfx.play(Snd.PILE_IN)   # R7：带着 DRAG 占用被回收 = 塞回牌堆，全端洗牌音
```

- `_ready` 播放无守卫：除抽牌生成外无其他实例化路径（清场/换库重建只生成牌堆，不生成卡牌）。
- `_exit_tree` 双重守卫：`board_locked` 挡清场/换库批量删除；`session_active` 挡断线/退出房间时
  残留 DRAG 占用的节点清理。
- 3D 翻牌音在 `check_and_flip()` 内（`Snd.FLIP` 音高抖动由 Sfx 统一处理）：

```gdscript
func check_and_flip():
    var is_front := _card_db.is_front(card_ID())
    var target_rot_x := get_rot_x_by_is_front(is_front)
    if absf(_pivot.rotation_degrees.x - target_rot_x) > 1.0:  # 本牌状态真的变了
        Sfx.play(Snd.FLIP)
    Util.tween_rot_x(_pivot, target_rot_x, FLIP_DURATION)
    _refresh_description_tooltip()
```

（阈值 1.0 度容纳浮点/动画中间态；翻转动画进行中再次收到同步时以目标角比较，不会误响。）

### 5.3 [ui_card.gd](../ui_card.gd)：2D 悬停音 + 2D 右键翻牌音（R1b/R5-2D，仅本端）

```gdscript
var _last_is_front := false
var _flip_sound_armed_at := -1  # msec，>0 表示等待自己的翻面广播

func _ready():
    ...
    _last_is_front = _card_db.is_front(card_ID())

func _on_mouse_entered() -> void:
    _is_mouse_hovering = true
    Sfx.play(Snd.HOVER)          # R1b：2D 牌悬停
    _refresh_description_tooltip()

func _gui_input(event: InputEvent):
    ...
    elif Util.is_right_mouse_down(event):
        _flip_sound_armed_at = Time.get_ticks_msec()  # 武装
        request_flip()
        ...

func update_ui():
    var is_front := _card_db.is_front(card_ID())
    if is_front != _last_is_front:
        if _flip_sound_armed_at > 0 and Time.get_ticks_msec() - _flip_sound_armed_at <= 2000:
            _flip_sound_armed_at = -1
            Sfx.play(Snd.FLIP)   # 自己右键申请的那次翻面真正落地
        _last_is_front = is_front
    ...
```

- 悬停/翻牌音都只在本端播放：查看器与 UICard 是本端私有节点，无同步路径，天然满足"仅翻动者端"。
- 状态比对保证只有本牌变化才响；武装 + 2 秒过期避免被拒绝的申请留下"陈旧武装"误触发后续翻面。
- 六大翻面按钮触发的翻面**不会**进入此分支（未武装），不会与 R2 的洗牌音重复。
- `drag_preview` 的替身 UICard 是 `duplicate()` 出来的且 `mouse_filter = IGNORE`：替身既不触发悬停音，
  也从未武装翻牌音，全部静音 ✓。

### 5.4 [deck_viewer_ui.gd](../deck_viewer_ui.gd)：六大理牌音（R2，仅本端）+ 按下音排除（R6）

```gdscript
var _shuffle_sound_armed_at := -1   # 等待翻面类按钮操作的落地广播

func _ready():
    ...
    _card_db.on_flip.connect(_check_flip_sound)
    # R6 排除：六大理牌按钮有自己的成功音，按下不响确认音（悬停音保留）；
    # node_added 连接确认音回调早于本 _ready 执行，因此回调内点击时检查组而非连接时检查
    for btn: Button in [btn_sort_ascend, btn_sort_descend, btn_shuffle,
            btn_all_front, btn_all_back, btn_all_flip]:
        btn.add_to_group(Sfx.GROUP_NO_CONFIRM)

func _arm_shuffle_sound():
    _shuffle_sound_armed_at = Time.get_ticks_msec()

func _check_flip_sound():
    if _shuffle_sound_armed_at > 0 and Time.get_ticks_msec() - _shuffle_sound_armed_at <= 2000:
        _shuffle_sound_armed_at = -1
        Sfx.play(Snd.SHUFFLE_OK)

func _on_sort_ascend_pressed():
    if list_top.get_child_count() == 0: return   # 空列表无可"成功"的操作
    ...（原逻辑末尾）Sfx.play(Snd.SHUFFLE_OK)    # 降序、洗牌同理
```

- 升序/降序/洗牌：回调末尾直接播放（空列表守卫后）。
- 三个翻面按钮：各自回调第一行 `_arm_shuffle_sound()`，随后照常逐牌发请求；
  第一次 `on_flip` 到达即响一次（后续 N-1 次广播因已解除武装而静音）。
- 已知极小竞态：武装后 2 秒内恰逢其他端翻动某张桌面 3D 牌广播到达本端 → 本端误响一次洗牌音。
  查看器独占期间其他玩家无法翻动本牌堆的牌，且 2D 场景此刻被查看器遮挡，影响可忽略（见 8.4）。
- 查看器的 Btn_Cancel / Btn_Draw **不排除**，按下响确认音（R6"所有其他原生按钮"）。

### 5.5 [counter.gd](../counter.gd)：加/减号 3D 悬停音（R1c，仅本端）

3D 按钮是 CollisionShape3D，无逐形状 hover 信号；利用物理拾取会向 `_input_event` 投递
`InputEventMouseMotion` 的特性做形状跟踪：

```gdscript
var _hovered_button_shape := -1

func _ready():
    ...
    mouse_exited.connect(func(): _hovered_button_shape = -1)

func _input_event(_camera, event: InputEvent, event_position: Vector3, _normal, shape_idx: int):
    if event is InputEventMouseMotion:
        _update_button_hover(shape_idx)
        return
    if not _local_can_interact(): return
    ...（原点击逻辑不变）

func _update_button_hover(shape_idx: int) -> void:
    if not _local_can_interact(): return
    if shape_idx == SHAPE_MINUS or shape_idx == SHAPE_PLUS:
        if _hovered_button_shape != shape_idx:   # 从底座/外部进入按钮：边沿触发一次
            _hovered_button_shape = shape_idx
            Sfx.play(Snd.HOVER)
    else:
        _hovered_button_shape = -1               # 移到底座：复位，便于再次进入按钮时重响
```

- 底座（`SHAPE_BASE`）不响；按钮间互切（减→加）各自响一次。
- `mouse_exited` 复位悬停状态；悬停音同样受 50ms 最小间隔去抖。
- 复用 `_local_can_interact()`：仅打牌模式、会话中发声（与计数器点击 gating 一致）。
- 计数器 +/- 的 3D 点击不属于"原生 UI 按钮"，**不响**确认音（R6 范围外）。

## 6. 需求 → 挂点对照总表

| 需求 | 触发点 | 文件 | 枚举 | 音高 | 播放端 |
| --- | --- | --- | --- | --- | --- |
| R1a UI 按钮悬停 | `BaseButton.mouse_entered`（自动连接） | sfx_manager.gd | `HOVER` | 固定，-6dB | 本端 |
| R1b 2D 牌悬停 | `UICard.mouse_entered` | ui_card.gd | `HOVER` | 固定，-6dB | 本端 |
| R1c 计数器 ± 悬停 | `_input_event` motion + shape 边沿 | counter.gd | `HOVER` | 固定，-6dB | 本端 |
| R6 原生按钮按下 | `BaseButton.pressed`（自动连接，组排除六理牌钮） | sfx_manager.gd | `CONFIRM` | 固定 | 本端 |
| R2 升序/降序/洗牌 | 按钮回调末尾 | deck_viewer_ui.gd | `SHUFFLE_OK` | ±1 半音 | 本端 |
| R2 全部翻正面/背面/逐一翻面 | 武装 → `CardDatabase.on_flip` | deck_viewer_ui.gd | `SHUFFLE_OK` | ±1 半音 | 本端 |
| R3 拿起牌 | `check_and_up_down` 边沿（profile="card"） | dragger.gd | `PICKUP_CARD` | ±1 半音 | 全端 |
| R3 放下牌到桌面 | `check_and_up_down` 边沿 | dragger.gd | `DROP_CARD` | ±1 半音 | 全端 |
| R7 牌入堆 | `Card._exit_tree` + `is_being_dragged` | card.gd | `PILE_IN` | ±1 半音 | 全端 |
| R8 牌出堆 | `Card._ready`（仅 spawner 实例化） | card.gd | `SPAWN` | ±1 半音 | 全端 |
| R4 拖起牌堆/计数器 | `check_and_up_down` 边沿（profile="object"） | dragger.gd | `PICKUP_OBJECT` | ±1 半音 | 全端 |
| R4 放下牌堆/计数器 | `check_and_up_down` 边沿 | dragger.gd | `DROP_OBJECT` | ±1 半音 | 全端 |
| R5-3D 右键翻牌 | `check_and_flip` 旋转角比对 | card.gd | `FLIP` | ±1 半音 | 全端 |
| R5-2D 右键翻牌 | `update_ui` 状态比对 + 武装 | ui_card.gd | `FLIP` | ±1 半音 | 本端 |

## 7. 边界情况核对

| 场景 | 行为 |
| --- | --- |
| 申请拖起被服务器拒绝（清场锁/被抢占） | 无所有权广播边沿 → 全端不响 |
| 清场/换库期间强制释放与批量删节点 | `Util.board_locked()` 门控 → 全端静音 |
| 暂停菜单强制释放（拖动中的牌被放下） | 卡牌确实落下（服务器回位动画），全端响一声放下音，音画一致 |
| 拖起状态下塞牌入堆成功 | 卡牌节点全网回收 → `_exit_tree` 全端响一声洗牌音（R7）；无放下音重复 |
| 抽牌（点牌堆顶/热点/查看器抽取） | `Card._ready` 全端响放下音（R8）；批量抽取同帧合并为一声 |
| 断线/退出房间清理残留拖动占用的卡牌 | `session_active` 守卫 → 不误响入堆音 |
| 抽牌/计数器 ± 的瞬时事务 | 非 DRAG purpose → 不响拖动音 |
| 全部翻正面但牌全在正面 | `server_flip_to` 逐牌跳过、无广播 → 不响 |
| 空牌堆按升序/降序/洗牌 | 空列表守卫 → 不响 |
| 按下六大理牌按钮 | 不响确认音（组排除）；操作成功后按 R2 响洗牌音 |
| 按下其他任何原生按钮（含确认对话框 OK/取消、CheckBox、查看器取消/抽取） | 立即响确认音，无成功门控（Q9），端口非法点"创建房间"也响 |
| 按下禁用按钮 | 无法触发 `pressed`；悬停音也被 `disabled` 检查挡住 |
| 晚加入/断线重连 | 状态同步无广播边沿 → 不响；`_was_being_dragged` 初始 false |
| 其他端玩家翻动 3D 牌 | `check_and_flip` 全端可闻（符合"3D 动作全端播放"） |
| headless 测试 | `_headless` 守卫不出声，仅记录 history，不影响现有测试 |
| 悬停音连环触发 | 50ms 最小间隔去抖（R1a/R1b/R1c 共用） |
| 多个音效叠放 | 8 播放器池轮转，允许自然叠音 |

## 8. 设计决策记录

1. **Q1 播放端归属（已确认）**：3D 桌面物理动作（拿起/放下/拖动/翻牌/入堆/出堆）动画全端可见 →
   音效全端播放；2D 查看器是本端私有界面（悬停、按下、理牌、2D 翻牌）→ 仅本端播放。
   全端实现不引入新 RPC，复用所有权广播边沿、`on_flip` 广播与 MultiplayerSpawner 的同步实例化。
2. **Q2 塞回牌堆为什么用 `_exit_tree` 检测？** 收牌事务直接 `queue_free` 卡牌且不释放其 DRAG 占用，
   无释放广播边沿、无成功回包；"节点带着 DRAG 占用被回收"是塞牌路径的独有特征
   （正常放下不删节点），配合 `board_locked`/`session_active` 门控即可全端精确触发且不与放下边沿重复发声。
3. **Q3 为什么不用 AudioStreamPlayer3D？** 上帝视角桌面，位置感无意义且增加衰减调参成本；统一非定位。
4. **Q4 为什么悬停音不做全局开关/总线？** 本期最小实现；如需静音/分组调音，后续把 `bus` 换成专用
   `Sfx` 音频总线即可，接口不变。
5. **Q5 悬停音为何压低 6dB？** 高频触发音需比动作音弱一档；具体值实现时可听感微调。
6. **Q6 音高抖动范围（已确认）**：R2/R3/R4/R5/R7/R8 全部 ±1 半音随机，R1 悬停与 R6 确认固定；
   实现为 `_VARY_PITCH` 字典，调整只需改表。
7. **Q7 武装等待为何 2 秒过期？** 与认证超时同数量级，远大于正常 RTT；过期仅影响"拒绝后不再残留武装"，
   不影响正常流程。
8. **Q8 计数器悬停为何用 motion 跟踪而非 mouse_entered？** `CollisionObject3D.mouse_entered`
   不区分下属 CollisionShape3D；`_input_event` 会收到鼠标移动事件且带 `shape_idx`，
   用边沿跟踪即可精确到加/减按钮，无需改动 Counter.tscn 增设 Area3D。
9. **Q9 确认音时机（已确认）**：按下立即响、无成功门控——与"操作成功"解耦，点击被拒（端口非法）、
   对话框取消均照响；成功类音效（R2 等）另有判定，二者不冲突。
10. **Q10 批量抽牌合并（已确认）**：查看器一次抽出 N 张牌在 Sfx 层做同帧合并，一次操作一声放下音；
    逐张单抽仍是一张一声。合并发生在 `_history` 记录前，测试断言一致。
11. **Q11 确认音音高（已确认）**：固定音高，作为标准 UI 反馈音。
12. **Q12 出堆音为何用 `Card._ready` 检测？** `Card.tscn` 全项目仅 `PileCardSpawner` 实例化，
    节点被 MultiplayerSpawner 同步到各端即"牌从牌堆取出"，天然覆盖全部抽牌路径且无需 RPC；
    清场/换库重建只生成牌堆不生成卡牌，无误触发。

## 9. 测试方案

沿用项目"GDScript 按角色分进程 + Python 编排"模式，新增：

- `tests/sfx_test.gd`：角色 `parser` / `host` / `client`，复用 [deck_test_game.gd](../deck_test_game.gd) 抑制无头自动开房。
- `tests/run_sfx_tests.py`：仿 [run_counter_tests.py](../tests/run_counter_tests.py)，输出 marker
  `SFX_PARSER_OK` / `SFX_HOST_OK` / `SFX_CLIENT_OK`。

| 用例 | 角色 | 断言 |
| --- | --- | --- |
| 解析 | parser | headless editor `--check-only` + 全量解析通过（unsafe 警告当错误） |
| Sfx 基础 | client | `Sfx` 在树中；`play()` 后 `history_contains` 对应枚举；`_VARY_PITCH` 中键的 pitch 落在 ±1 半音区间，`HOVER`/`CONFIRM` 恒为 1.0 |
| 按钮悬停钩子 | client | 实例化 Button，`mouse_entered.emit()` → history 含 `HOVER`；`disabled` 按钮不记录 |
| 按钮确认音 | client | Button `pressed.emit()` → history 含 `CONFIRM`；把按钮加入 `sfx_no_confirm` 组后再 emit → 无新增 `CONFIRM` |
| UICard 悬停 | client | 实例化 UICard，`mouse_entered.emit()` → history 含 `HOVER` |
| 计数器悬停 | client | 调用 `_update_button_hover(SHAPE_PLUS)` → 新增一条 `HOVER`；连续同形状不新增；切 `SHAPE_BASE` 复位后再进入可重响 |
| 拖动音效（全端） | host+client | client 对公共牌堆 `pile.dragger.request_drag()` → 等所有权广播 → **两端** history 都含 `PICKUP_OBJECT`；`request_drop()` 后两端都含 `DROP_OBJECT` |
| 卡牌拿起/放下（全端） | host+client | 对 3D 卡牌走申请/释放流程，断言两端 `PICKUP_CARD` / `DROP_CARD` |
| 抽牌音（全端+合并） | host+client | client 抽 1 张 → 两端各恰新增 1 条 `SPAWN`；查看器批量抽 3 张 → 两端各恰新增 1 条（同帧合并） |
| 入堆音（全端） | host+client | 塞牌入堆事务后两端各恰新增 1 条 `PILE_IN`，且拖起/放下边沿未多发 `DROP_CARD` |
| 翻面音（全端） | host+client | client `request_flip` 一张 3D 牌 → 两端各恰新增 1 条 `FLIP` |
| 拒绝不响 | host+client | client 对已被他人占用的牌堆申请拖动 → 广播后两端 history 均无新增 `PICKUP_OBJECT` |
| 查看器理牌音（本端） | host+client | client 打开牌堆查看器：`_on_shuffle_pressed()` 立即响且**无**新增 `CONFIRM`（组排除生效）；`_on_all_front_pressed()` 后等 `on_flip`，仅 client 恰新增一条 `SHUFFLE_OK`，host 端无 |
| 2D 翻牌音（仅本端） | host+client | client 查看器内 UICard 右键翻面落地后，仅 client history 新增 `FLIP` |

运行：`python3 tests/run_sfx_tests.py`（需 localhost ENet 可监听，与现有运行器一致）。

### MCP 手动验证（GUI）

1. Godot AI MCP `project_run` 启动项目，开两个窗口创建/加入房间（验证全端音效需两端都能听见）。
2. `game_eval` 可随时查询任一端播放记录：
   `(get_node("/root/Sfx") as SfxManager)._history`。
3. 一端拖动牌堆/抽牌/塞牌/翻牌，另一端应同步听到对应音效；两端各验证悬停（主菜单按钮、查看器内牌、
   计数器加/减号）与按钮按下确认音（含清场对话框的确认/取消）。
4. `logs_read(source="game")` 确认无脚本错误。

## 10. 实现清单（预计改动面）

| 文件 | 改动 |
| --- | --- |
| `sfx_manager.gd` | 新增（约 110 行：播放池、按钮双钩子、同帧合并、组排除、history） |
| `project.godot` | `[autoload]` 增加一行 |
| `dragger.gd` | config 加 profile 参数 + `is_being_dragged()` + `check_and_up_down` 边沿播放 |
| `card.gd` | config 传 "card"、`_ready` 出堆音、`_exit_tree` 入堆检测、`check_and_flip` 比对播放 |
| `ui_card.gd` | 悬停播放 + `_last_is_front` 跟踪 + 武装判定播放 |
| `counter.gd` | motion 悬停跟踪（`_update_button_hover`） |
| `deck_viewer_ui.gd` | 六理牌钮加入排除组 + 排序类直响 + 翻面类武装判定 |
| `tests/sfx_test.gd`、`tests/run_sfx_tests.py` | 新增测试 |
| `README.md` | 自动化测试表格加一行（可选） |

不需要改动：owner_mux.gd、pile.gd、game.gd、pile_card_spawner.gd、网络/RPC 层
（全端音效复用既有广播与 MultiplayerSpawner 同步，音效本身是本地表现层逻辑）。

## 暂停确认框内部按钮修复（2026-10-04）

Godot ConfirmationDialog 的确认和取消按钮属于内部子节点。SfxManager 的全树及弹窗补扫使用 get_children(true) 包含内部节点，沿用 Callable 去重，确保重复打开弹窗不会重复发声；延迟扫描检查节点有效性与待删除状态。tests/sfx_test.gd 的 parser 覆盖真实一键清场、一键清计数器确认框的确认/取消按钮，两轮弹出后分别断言悬停与点击音效恰好一次。
