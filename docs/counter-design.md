# 计数器（Counter）设计文档

- 状态：设计完成（关键决策已确认，见第 10 节；Q5–Q9 按默认方案执行）
- 日期：2026-09-28
- 关联文档：[godot-472-and-godot-ai-mcp.md](godot-472-and-godot-ai-mcp.md)、[in-room-chat-design.md](in-room-chat-design.md)

## 1. 背景与目标

在现有桌面棋牌房间（`Game.tscn`）中新增一种 3D 物体：**计数器（Counter）**。
它是一个可拖动的紫色半透明长方形底座，上面有减号按钮、数字文本、加号按钮，
用于桌上游戏中记录生命值、分数等数值。功能要求：

1. 打牌模式下，左键加减号按钮 → 中间数字按步长增减（OwnerMux 保护并发）。
2. 打牌模式下，左键底座开始拖动，再次左键停止拖动（OwnerMux 保护并发）。
3. 打牌模式下，右键底座打开 2D 查看器（样式与 DeckViewerUI 一致），在查看器内可：
   - 直接在输入框修改数值，数值两侧有 "+1"/"-1" 按钮（文案随步长与小数位变化）；
   - 修改步长（仅一个输入框，无加减按钮）；
   - 修改小数位数（输入框 + 两侧纯 "+"/"-" 按钮，整数、最小 0，步长恒为 1）。

## 2. 现状调研

### 2.1 桌面物体通用骨架

现有两类桌面物体 Pile（[pile.gd](../pile.gd) / [Pile.tscn](../Pile.tscn)）与 Card（[card.gd](../card.gd)）共享同一骨架：

| 子节点 | 职责 |
| --- | --- |
| 根 `StaticBody3D` | 挂业务脚本，处理 `_input_event` 拾取 |
| `OwnerMux` | 所有权互斥锁（见 2.2） |
| `Dragger` | 拖动：request_drag / request_drop / process_drag，升起放下动画 |
| `MultiplayerSynchronizer` | 复制 `position`（spawn + on-change），拖动位置广播 |

### 2.2 OwnerMux 机制（[owner_mux.gd](../owner_mux.gd)）

- `request_own(purpose)`：向服务器申请所有权；`request_release()` 释放。
- 服务器 `server_set_owner` / `server_reset_owner` 校验后用 `_set_owner` RPC 广播全体
  （`call_local`），父节点 `set_multiplayer_authority(new_owner)`，发 `on_owner_change` 信号。
- 同一时刻一个物体只能被一个 purpose 占用；`Util.board_locked()` 在清场期间拒绝一切申请。
- 玩家断线时 `server_recover_mux` 自动回收其所有权。

### 2.3 Pile 的三个交互样例（计数器的参照）

1. **拖动**：`BaseArea`（Area3D）左键 → `dragger.request_drag()`（Purpose.DRAG）→
   获得 ownership 后 `check_and_up_down()` 升起；全局 `_input` 左键 → `request_drop()`。
2. **抽牌（瞬时操作）**：点击 Hotspot → `request_own(PILE_OUTPUT_x)` →
   服务器在 `on_owner_change` 里执行抽牌 → `server_sync_card_ID_stack()` 同步 →
   `server_reset_owner()` 立刻释放。整个"占用→改状态→广播→释放"是一次瞬时事务。
3. **右键查看（持续占用）**：右键 → `request_own(Purpose.PILE_VIEW)` →
   [pile_accessor.gd](../pile_accessor.gd) 在 `on_owner_change` 时若自己是查看者则实例化
   `DeckViewerUI`，否则关闭；确定时服务器校验 `is_being_viewed()` 后应用新牌序并释放。

### 2.4 DeckViewerUI 样式（[DeckViewerUI.tscn](../DeckViewerUI.tscn)）

- 根 `CanvasLayer`，全屏 `ColorRect` 半透明黑 `Color(0, 0, 0, 0.392)` 挡住 3D 输入；
- `Margin(40) / VBox` 布局，控件字号 30；实例化到 `/root`（不在 Game 子树）；
- 关闭时机：取消按钮（`request_release`）、ownership 变化、暂停菜单/退出房间/清场时
  由 `game.gd _close_local_deck_viewers()` 统一释放。

### 2.5 游戏模式与输入

- `Player.PlayerStatus`：CARD（打牌，鼠标可见）/ MOVE（移动，鼠标捕获），空格切换。
- **注意**：现有 Pile/Card 的 3D 输入处理均未检查 `is_card_mode()`；
  计数器按需求只允许打牌模式交互，需要新增 gating（见 Q8）。

### 2.6 晚加入同步与生命周期

- Pile `_ready` 时非服务器端 `request_sync_card_ID_stack()` 向服务器要状态；
  位置由 MultiplayerSynchronizer 自动补齐。
- 一键清场：服务器 `_clear_board_nodes()` 删除全部 Pile/Card 后重建公共牌堆与玩家牌堆；
  清场期间 `clear_table_in_progress` 使 `Util.board_locked()` 返回 true。
- 暂停菜单/退出房间：`_release_local_interactions()` 遍历所有 Pile/Card 调
  `release_local_interaction()`（挂起本地交互 + 释放 ownership）。

## 3. 需求清单（整理后）

| 编号 | 需求 | 并发要求 |
| --- | --- | --- |
| R1 | 3D 外观：紫色半透明长方形底座（俯视横向 > 纵向），上面从左到右依次为减号片、数字、加号片；按钮片为白色扁平正方形（厚 1，见 Q3），黑色 "+"/"-" 文本；数字字体与 Card 相同（默认字体） | — |
| R2 | 打牌模式左键加/减号 → 主数字按步长 ±step | OwnerMux 瞬时占用 |
| R3 | 打牌模式左键底座开始拖动，再左键结束 | OwnerMux 持续占用（DRAG） |
| R4 | 打牌模式右键底座 → 打开 CounterViewerUI（DeckViewerUI 同款半透明样式）；内含数值输入框 + "+1"/"-1" 按钮、步长输入框、小数位输入框 + 纯 +/- 按钮 | OwnerMux 持续占用（COUNTER_VIEW） |

## 4. 总体设计

### 4.1 新增文件

| 文件 | 说明 |
| --- | --- |
| `Counter.tscn` | 3D 计数器场景（根 StaticBody3D） |
| `counter.gd` | 根脚本：状态、可视化、输入路由、网络同步 |
| `CounterViewerUI.tscn` / `counter_viewer_ui.gd` | 右键查看器（仿 DeckViewerUI） |
| `counter_accessor.gd` | 查看器开关与提交（仿 pile_accessor.gd），挂根下 `Accessor` 节点 |
| 修改 | `const.gd`（Purpose 扩展）、`game.gd`、`Game.tscn` |

### 4.2 Counter.tscn 场景树

```
Counter (StaticBody3D, counter.gd)
├─ BaseMesh (MeshInstance3D)          # 紫色半透明 BoxMesh，R1
├─ ValueLabel (Label3D)               # 主数字，默认字体
├─ CollisionShape3D × 3               # 0=底座 1=减号 2=加号（根 body 统一拾取路由）
├─ MinusPlate (MeshInstance3D)        # 白色扁平正方形片
├─ MinusLabel (Label3D, "-")          # 黑色文本
├─ PlusPlate (MeshInstance3D)
├─ PlusLabel (Label3D, "+")
├─ MultiplayerSynchronizer            # 复制 position
├─ OwnerMux
├─ Dragger
└─ Accessor (Node, counter_accessor.gd)
```

**输入路由设计**：与 Pile 用独立 Area3D 做拖拽区不同，计数器把底座与两个按钮做成
**同一根 StaticBody3D 的 3 个 CollisionShape3D**，在 `_input_event` 里按 `shape_idx`
分发。原因：按钮片叠放在底座上方，若用重叠的两个 Area3D，同一次点击射线会同时命中
两者且派发顺序不确定，会出现"加号点击同时触发拖动"的竞态；单 body 多 shape 只有一个
接收者，按 `shape_idx` 路由是确定性的（实现时用 `event_position` 反查按钮区域做兜底校验）。

### 4.3 Const.Purpose 扩展（[const.gd](../const.gd)）

```gdscript
COUNTER_VIEW     = 9   # 持续占用：右键查看器
COUNTER_ADD      = 10  # 瞬时占用：加步长
COUNTER_SUBTRACT = 11  # 瞬时占用：减步长
```

`PURPOSE_STR` 同步补充。拖动复用 `Purpose.DRAG`，与 Pile/Card 一致。

### 4.4 状态与互斥矩阵

| 当前状态 | 其他玩家 + 底座左键 | 其他玩家 + 按钮左键 | 其他玩家 + 底座右键 |
| --- | --- | --- | --- |
| 空闲（无 owner） | 获得 DRAG，开始拖动 | 获得 ADD/SUB，数值变化后立即释放 | 获得 COUNTER_VIEW，打开查看器 |
| 被拖动 | request_own 失败 | 失败 | 失败 |
| 被查看 | 失败 | 失败 | 失败（查看者本人的编辑走查看器通道） |

自己拖动中再点任何左键（含按钮 shape）→ 一律视为 `request_drop`（与 Pile 行为一致）。

## 5. 3D 场景细节

尺寸为初版建议值，实现后用 MCP 截图（`editor_screenshot`）校对微调。

| 元素 | 建议 | 备注 |
| --- | --- | --- |
| 底座 BoxMesh | `1.8 × 0.05 × 1.0`（X × Y × Z，横向长） | 材质复制 Pile 底座：`StandardMaterial3D transparency=1, albedo=Color(0.4288, 0.3094, 0.9298, 0.4549)` |
| 按钮片 BoxMesh | `0.3 × 0.01 × 0.3`（厚 0.01，见 Q3） | 白色不透明 StandardMaterial3D；中心 x = ∓0.6，y = 0.055（坐在底座上） |
| 按钮文本 Label3D | "+" / "-"，黑色 modulate，默认字体 | font_size ≈ 32，pixel_size 0.005（同 Card），贴在片上方 |
| 主数字 Label3D | 默认字体（同 Card，无 font override） | 居中 x=0；颜色默认白（同 Pile 计数 Label，见 Q6）；font_size ≈ 40 |
| 拾取 shape | 底座 `1.8 × 0.05 × 1.0`；两按钮 `0.3 × 0.06 × 0.3` | 按钮 shape 略高于底座顶面 |
| 拖动参数 | `DRAGGING_Y = 0.0`，`UP_DOWN_DURATION = 0.1` | 底座贴桌面滑行，同 Pile |

## 6. 数值模型与格式化

### 6.1 状态字段（counter.gd）

```gdscript
var value: float    = 0.0   # 当前数值
var step: float     = 1.0   # 步长 > 0
var decimals: int   = 0     # 小数位数 ≥ 0（上限见 Q5，建议 6）
```

### 6.2 格式化规则

- 显示统一按 decimals 定点格式化：`decimals=0` → "5"；`decimals=2` → "5.30"。
  实现备注：不用 `String.num(x, decimals)`——它会裁剪末尾零（`String.num(2.5, 2) == "2.5"`）；
  实际采用 printf 定点格式 `("%." + str(decimals) + "f") % x`，并把 `-0` 归一为 `0`。
- 查看器按钮文案：方向符号 + 步长格式化，即 `"+1"` / `"-1"`；`step=0.5, decimals=1` → `"+0.5"`。
- 小数位按钮文案：恒为 "+"/"-"（步长恒 1，不显示数值）——按用户要求。
- 步长变化 → 刷新查看器 +1/-1 按钮文案；小数位变化 → 刷新主数字、步长显示、+1/-1 文案。

### 6.3 约束与边界

| 操作 | 规则 |
| --- | --- |
| ± step | `value += ±step`，结果按 decimals 四舍五入后存储；是否允许负数/上下限见 Q4 |
| 步长输入框 | 必须为正数；非法输入不提交、恢复原值（见 Q5 关于 step 与 decimals 的关系） |
| 小数位输入框 | 必须为 ≥0 整数；变化后 `value` 与显示一并按新位数取整 |
| 数值输入框 | 解析失败恢复原值；小数位超出 decimals 时按 decimals 取整（见 Q7） |

## 7. 网络协议设计

服务器权威，全部 reliable RPC，风格与 Pile 一致。

### 7.1 RPC 列表（counter.gd）

| RPC | 方向 | 作用 |
| --- | --- | --- |
| `server_apply_step(direction: int)` | 客户端→服务器 | ±步长申请（按钮点击 / 查看器 +1/-1） |
| `server_apply_value(new_value: float)` | 客户端→服务器 | 查看器数值输入框提交 |
| `server_apply_step_value(new_step: float)` | 客户端→服务器 | 查看器步长输入框提交 |
| `server_apply_decimals(new_decimals: int)` | 客户端→服务器 | 查看器小数位提交 |
| `sync_counter_state(value, step, decimals)` | 服务器→全体 | 状态广播（`call_local`） |
| `server_sync_counter_state()` / 回包 | 客户端→服务器→客户端 | 晚加入同步 |

`Accessor` 复用 OwnerMux 的 `on_owner_change` 开关查看器（同 pile_accessor.gd），
查看器内操作提交时服务器校验：`is_being_viewed()` 且 sender == 当前 owner。

### 7.2 时序 1：3D 按钮点击（瞬时占用，仿抽牌 + PileCardReceiver）

```
玩家A 左键"+" → counter._input_event(shape=加号)
  → 检查 is_card_mode()（见 Q8）
  → 服务器直接 RPC server_apply_step(+1)
服务器：
  1. board_locked() → 拒绝
  2. is_owned() 且不是"查看者本人提交" → 拒绝（互斥保护）
  3. owner_mux.server_set_owner(COUNTER_ADD, sender)   # 占用，广播
  4. value = round(value + direction*step, decimals)
  5. sync_counter_state.rpc(value, step, decimals)      # 广播刷新 3D 数字
  6. owner_mux.server_reset_owner()                     # 立刻释放
```

期间其他玩家的 +/-/拖动/右键申请都会因 `is_owned()` 被拒，满足"OwnerMux 保障并发安全"。

### 7.3 时序 2：底座拖动（持续占用，完全复用 Dragger）

```
左键底座 → dragger.request_drag()          # Purpose.DRAG，升起
 _process → dragger.process_drag()          # 跟随鼠标，position 由 Synchronizer 复制
任意左键 → counter._input → dragger.request_drop()  # 放下并释放
```

无需新增网络代码，Dragger 的 `_sync_rot_y` 与 `server_recover_mux`（拖动者断线自动放下）天然适用。

### 7.4 时序 3：右键查看器（持续占用，仿 PILE_VIEW）

```
右键底座 → accessor.request_open_viewer()  # request_own(COUNTER_VIEW)
on_owner_change → 我是查看者 → 实例化 CounterViewerUI 到 /root
查看器内编辑 → server_apply_* → 服务器校验 sender==owner → 应用 → sync_counter_state
关闭（按钮）→ request_release → 广播 → 所有人关闭查看器
```

### 7.5 一致性与边界情况

- **晚加入**：`_ready` 时非服务器 `server_sync_counter_state.rpc_id(1)`，服务器回
  `sync_counter_state`；位置由 MultiplayerSynchronizer 补齐。
- **查看者断线**：`server_recover_mux` 重置 ownership → 全体 `on_owner_change` → 查看器关闭。
- **清场期间**：`Util.board_locked()` 拒绝一切申请；"一键清牌"不删计数器，
  "一键清计数器"单独清除（见第 9 节第 4 条）。
- **快速连点丢点击**：互斥是"申请→广播"往返，广播回来前本地 `is_owned()` 仍为 false，
  第二次点击也会发出申请，但服务器上第二次会因已被占用而拒绝 → 极快连点可能丢点击。
  Pile 抽牌同样存在。v1 接受该行为（Q9 可选优化：服务器对同 owner 同 purpose 的连击排队合并）。

## 8. CounterViewerUI 设计

### 8.1 布局（样式对齐 DeckViewerUI）

```
CounterViewerUI (CanvasLayer)
├─ Background (ColorRect, Color(0,0,0,0.392)，全屏，挡 3D 输入)
└─ Panel (居中 PanelContainer，仿暂停菜单面板)
   └─ Margin / VBox
      ├─ 标题 "计数器"
      ├─ Row1 (HBox): [Btn_Minus "+-step文案"] [LineEdit 数值] [Btn_Plus "+step文案"]
      ├─ Row2 (HBox): [Label "步长"]  [LineEdit 步长]
      ├─ Row3 (HBox): [Btn_DecMinus "-"] [LineEdit 小数位] [Btn_DecPlus "+"]
      └─ 底栏 (HBox): [Btn_Close "关闭"]
```

### 8.2 控件行为

| 控件 | 行为 |
| --- | --- |
| 数值输入框 | `text_submitted` / 焦点离开时提交 `server_apply_value`；非法输入恢复原值。回显随 `sync_counter_state` 刷新（非编辑中才覆盖，避免打断输入） |
| "+1"/"-1" 按钮 | 文案 = ±格式化(step)，点击即 `server_apply_step(±1)`；step/decimals 变化时刷新文案 |
| 步长输入框 | 提交 `server_apply_step_value`；必须 > 0；提交后刷新 +1/-1 文案 |
| 小数位输入框 | 仅 ≥0 整数；提交 `server_apply_decimals`；按钮恒为纯 "-"/"+"；主数字与 +1/-1 文案随之刷新 |
| 关闭按钮 | `request_release`，ownership 广播后所有端关闭查看器 |
| 删除按钮 | 仅房主或当前占用者可见可用；确认后服务器 `queue_free()` 该 Counter（MultiplayerSpawner 自动全网销毁），若被占用先释放 |

- 查看器打开期间该计数器被本玩家独占，其他玩家操作全部被拒；本玩家的 3D 按钮点击
  也被拒（编辑统一走查看器），避免两条通道竞写。
- 修改即时生效（逐项提交），无"确定"按钮（与 DeckViewerUI 的批量确定不同，见 Q7）。

## 9. 与现有代码的集成点（实施清单）

1. `const.gd`：新增 3 个 Purpose + `PURPOSE_STR`。
2. `Game.tscn`：新增 `Counters`（Node3D）容器 + `MultiplayerSpawner_Counters`
   （spawnable = Counter.tscn，spawn_path = `../Counters`），仿 MultiplayerSpawner_Piles。
3. `game.gd`：
   - `add_counter(pos)` 服务器端生成接口；
   - `_release_local_interactions()` 遍历 `Counters` 调 `release_local_interaction()`；
   - `_close_local_deck_viewers()` 同时释放 CounterViewerUI。
4. **清场拆分为两个独立功能**（已确认）：
   - 现有"一键清场"保持不变，只清散牌与牌堆，**不动计数器**；
   - 暂停菜单新增"一键清计数器"按钮 + 确认对话框，服务器 RPC
     `server_clear_counters()`：校验 board_locked 后删除全部 Counter
     （清场期间同样置 `clear_table_in_progress` 或独立 busy 标志防重入）。
5. 暂停菜单（`Game.tscn` PauseOverlay）：新增"添加计数器"按钮（仅房主可用，
   仿 ClearTableButton 的连接方式）。
6. `counter_accessor.gd`：仿 `pile_accessor.gd`，另含"删除计数器"入口。
7. 卡牌交互兼容性：`Card.detect_pile_or_hotspot()` 射线开启了 `collide_with_areas`，
   拖牌经过计数器底座上方会先命中计数器（ray 命中最近碰撞体），返回 null →
   卡牌只是无法入堆，不会误操作计数器；无需改动，但实现后需实测验证。

## 10. 待确认问题

### 10.1 已确认（2026-09-28）

| # | 问题 | 结论 |
| --- | --- | --- |
| Q1 | 创建/删除方式 | 暂停菜单"添加计数器"按钮（房主可用），生成在桌面空位；查看器内"删除"按钮（房主或占用者可删） |
| Q2 | 清场行为 | 拆分为两个独立功能：现有"一键清场"只清牌堆与散牌；新增"一键清计数器"只清计数器 |
| Q3 | 按钮片厚度 | 0.01（同 CARD_THICKNESS） |
| Q4 | 数值范围 | 允许负数，无上下限 |

### 10.2 默认按建议执行（如有异议再调整）

| # | 问题 | 默认方案 |
| --- | --- | --- |
| Q5 | step 可否 < 10^-decimals（如 step=0.5、decimals=0） | 提交步长按 decimals 四舍五入校验，结果 ≤0 则拒绝 |
| Q6 | 3D 主数字颜色 | 白色（同 Pile 计数 Label3D），在紫色底座上清晰 |
| Q7 | 查看器生效时机 | 逐项即时提交，无"确定/取消"批量按钮 |
| Q8 | 模式 gating 范围 | 仅计数器检查 `is_card_mode()`，不改动现有 Pile/Card |
| Q9 | 快速连点因互斥往返丢点击 | v1 接受；必要时再做服务器排队合并 |

## 11. 实施步骤与验证方案

### 11.1 实施顺序

1. `const.gd` Purpose 扩展（先行，避免后续冲突）。
2. `Counter.tscn` + `counter.gd`：外观 + 状态同步 + shape_idx 输入路由 + 拖动（复用 Dragger）。
3. 数值操作 RPC（server_apply_* / sync_counter_state）+ 晚加入同步。
4. `CounterViewerUI.tscn` + `counter_viewer_ui.gd` + `counter_accessor.gd`。
5. `Game.tscn` / `game.gd` 集成（Spawner、清场、释放本地交互、创建入口）。
6. 测试与视觉校准。

### 11.2 验证方案

- **解析检查**：修改后跑 headless editor 解析（命令见 [godot-472-and-godot-ai-mcp.md](godot-472-and-godot-ai-mcp.md)）。
- **联机测试**：仿 `tests/run_chat_tests.py` 模式新增 `tests/run_counter_tests.py`
  （主机 + 客户端 + 晚加入者），覆盖：±步长同步、拖动占用互斥、查看器编辑广播、
  晚加入状态补齐、断线回收、清场行为。
- **MCP 手工验证**：`project_run` 后用 `game_manage.get_scene_tree` 检查节点、
  `input_mouse` 模拟点击、`editor_screenshot` 校对 3D 布局与查看器样式。
