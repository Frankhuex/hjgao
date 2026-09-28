# HJGAO

一个基于 **Godot 4.7.2** 的 3D 多人联机桌面游戏项目。玩家以"上帝视角"围坐在一张 3D 桌面旁，可以在桌面上抽牌、打牌、翻面、整理牌堆、使用计数器，并通过房间内聊天交流。它不绑定任何具体规则，而是一个**通用的桌面牌类游戏平台**：牌面内容完全由 JSON 卡组定义，适合跑团、桌游辅助、自定义牌局等场景。

## 功能特性

- **3D 桌面与实体卡牌**：真实的 3D 桌面、牌堆、可拖动/翻面的卡牌，牌堆高度随牌数实时变化
- **多人联机**：ENet 可靠传输，服务器权威（host 即服务器），支持晚加入、断线恢复占用
- **自定义卡组**：通过 JSON 文件定义牌名、数量、描述；支持游戏中安全更换卡组
- **牌堆系统**：从顶/底/随机位置抽牌、放牌；2D 查看器内排序、洗牌、统一翻面、批量抽牌
- **计数器**：桌面上的可计数物件，支持步长与小数位设置，适合记录生命值/分数
- **房间聊天**：聊天面板 + 关闭时浮动通知横幅，服务器限流与历史记录
- **音效系统**：全局 `Sfx` 管理器统一调度（悬停去抖、同帧合并、±半音随机音高），覆盖牌堆/卡牌/计数器/查看器全部操作；按钮悬停与确认音自动挂载；背景音乐进入房间 10 秒后开始循环播放
- **一键清场 / 一键清计数器**：并发安全的桌面重置
- **自动化测试**：headless 多进程联机测试脚本

---

# 玩家指南

## 快速开始

1. 使用 **Godot 4.7.2** 打开本项目（`project.godot`），按 `F5` 运行（主场景为 `Game.tscn`）。
2. 主菜单中输入昵称（可留空，默认为"玩家+ID"）。
3. 房主填写端口号（默认 `7788`）点击**创建房间**；其他玩家填写房主 IP 和端口点击**加入**。
4. 加入成功后自动获得一个空的个人牌堆；房主额外获得一张洗好的公共牌堆。

无头模式（用于测试/自建服务器）：

```bash
Godot --headless --path <项目目录> -- --port=7788   # 实际上无头模式会自动开房，--port 可省略（默认 7788）
```

## 基础操作

游戏有两种模式，按 **空格** 切换：

| 模式 | 说明 |
| --- | --- |
| **打牌模式**（默认） | 鼠标可见，可点击/拖动桌面上的一切物件 |
| **移动模式** | 鼠标被捕获用于转动视角，`WASD` 移动角色，适合走动观察桌面 |

键盘快捷键：

| 按键 | 作用 |
| --- | --- |
| `空格` | 切换 打牌模式 / 移动模式 |
| `T` | 打开 / 关闭聊天窗口 |
| `Q` | 开关卡牌悬停描述提示 |
| `ESC` | 打开暂停菜单（聊天输入中按 ESC 会先释放焦点） |

## 桌面物件

### 牌堆（Pile）

紫色长方体底座，上方的数字表示剩余牌数，牌堆高度会随牌数增长。底座两侧各有一个悬停会变黄色放大的热点区：

| 操作 | 位置 | 效果 |
| --- | --- | --- |
| 左键点击底座 | 牌堆本体 | 从**牌堆顶**抽一张牌到桌面 |
| 左键点击热点"底" | 牌堆一侧 | 从**牌堆底**抽一张牌 |
| 左键点击热点"随" | 牌堆另一侧 | **随机**抽一张牌 |
| 右键点击底座 | 牌堆本体 | 打开 2D **牌堆查看器** |
| 左键拖动底座 | 牌堆本体 | 移动整个牌堆 |

### 牌堆查看器

半透明全屏 2D 界面，上半部分是牌堆里的牌，下半部分是"待抽区"。支持：

- **升序 / 降序 / 洗牌**：按卡组优先级重排牌堆
- **全部翻正面 / 全部翻背面 / 逐一翻面**
- **拖拽**：把牌拖到下半部分（滚轮滚动牌列），可精确定位插入位置
- **抽取**：把"待抽区"的牌作为 3D 卡牌生成到桌面上
- **取消**：关闭查看器

查看牌堆期间该牌堆被你独占，其他人无法同时操作。

### 卡牌（Card）

| 操作 | 效果 |
| --- | --- |
| 左键点击 | 抓起卡牌（悬空跟随鼠标） |
| 再次左键点击 | 放下卡牌 |
| 拖动状态下左键点击牌堆/热点 | 把牌**塞回**牌堆的对应位置（顶/底/随机） |
| 右键点击 | 翻面（背面朝上时牌名与描述隐藏） |
| 悬停正面卡牌 | 显示卡名与描述提示（可用 `Q` 关闭） |

拖动中的牌悬浮在牌堆上方时会自动垫高到牌堆顶部高度，放下时按桌面叠放顺序自动排列，不会重叠。

### 计数器（Counter）

紫色半透明底座，从左到右依次是：**减号按钮 / 数值文本 / 加号按钮**（仅打牌模式下可交互）。

| 操作 | 效果 |
| --- | --- |
| 左键点击 + / − | 数值按步长增加 / 减少（允许负数，无上限） |
| 左键拖动底座 | 移动计数器 |
| 右键点击底座 | 打开计数器**查看器** |

计数器查看器（2D 半透明界面）内可以：

- 直接在**输入框**里输入数值（或点数值两侧的 `+步长` / `−步长` 按钮）
- 修改**步长**（必须为正数，如 `0.5`，按钮文案会实时变为 `+0.50`）
- 通过 +/- 按钮调整**小数位数**（0～6 位，显示按位数定点格式化，如 `2.50`）
- **关闭**（释放占用）或**删除计数器**（房主或当前占用者可删）

## 暂停菜单（ESC）

| 项 | 说明 |
| --- | --- |
| 玩家列表 | 显示所有玩家的昵称、ID，并标注 `[房主]` / `[我]` |
| 显示卡牌描述 | 与 `Q` 键等效的开关 |
| 显示聊天窗口 | 与 `T` 键等效的开关 |
| 返回游戏 | 关闭暂停菜单 |
| 一键清场 | 清空所有牌与牌堆，重新生成满编公共牌堆和个人空牌堆（二次确认） |
| 添加计数器 | **仅房主可见**，在桌面两侧自动寻找空位生成一个计数器 |
| 一键清计数器 | 清空所有计数器，不影响牌堆（二次确认，与清场共用并发锁） |
| 更换卡组 | 选择本地 JSON 卡组文件，全体同步换库（见下文） |
| 断开连接 | 离开房间 |

## 聊天系统

- `T` 打开聊天面板，输入框获得焦点时角色输入暂停，其他快捷键不会误触
- `Enter` 发送 / `Shift+Enter` 换行 / `ESC` 释放输入焦点 / 点击输入框外释放焦点
- 聊天窗口关闭时，新消息以**浮动横幅**显示在屏幕左下（最多同时 2 条，10 秒后自动消失，超出的排队滚动）
- 消息服务端中继：单条最长 500 字符、最多 8 行；限流为**突发 5 条 + 每秒回复 1 条**的令牌桶
- 新加入的玩家会收到一次完整的聊天历史（最多 200 条）

## 更换卡组

1. 房主或玩家点击**更换卡组**，选择 JSON 文件（≤ 1 MiB）
2. 本地预检通过后确认，服务器再次校验
3. 全体进入两阶段事务：所有人释放占用的物件 → 删除旧桌面 → 安装新卡组 → 重建桌面
4. 期间拒绝新连接，任何端 15 秒未确认会被踢出；任何端加载失败会断开重连
5. 更换完成后的公共牌堆按模板顺序排好（与清场一致）

## 自定义卡组（JSON 格式）

卡组是一个 JSON 对象，示例（项目自带 `poker.json` 为一副 54 张扑克，含大小王）：

```json
{
  "deck_template": {
    "ordered_card_templates": [
      { "name": "♠️A", "count": 1, "description": "黑桃 A" },
      { "name": "♥️A", "count": 2, "description": "红桃 A，两张" }
    ]
  },
  "card_ID_to_is_front": { "1": true }
}
```

字段说明：

| 字段 | 必填 | 约束 |
| --- | --- | --- |
| `deck_template.ordered_card_templates` | 是 | 1～1000 个牌模板对象，**数组顺序即排序优先级** |
| `…[].name` | 是 | 字符串，≤ 64 字符，不可重复 |
| `…[].count` | 否 | 1～1000 的整数，默认 1；全部模板的 count 总和 ≤ 1000 |
| `…[].description` | 否 | 字符串，≤ 1000 字符，悬停提示显示 |
| `card_ID_to_card_name` | 否 | `"1": "♠️A"` 形式，恢复特定 ID 布局；省略则自动从 1 编号 |
| `card_ID_to_is_front` | 否 | `"1": true` 形式，指定某张牌初始正面朝上；省略则全部背面 |

校验规则：文件 ≤ 1 MiB；ID 必须是规范正整数字符串（不接受 `"01"`）；ID 映射数量必须与模板总数一致。未通过校验的卡组不会影响当前房间。

---

# 开发者参考

## 技术栈

| 项 | 选型 |
| --- | --- |
| 引擎 | Godot 4.7.2（GL Compatibility 渲染，Jolt Physics） |
| 网络 | ENetMultiplayerPeer + SceneMultiplayer 高级 API（RPC + MultiplayerSynchronizer + 自定义 auth） |
| 语言 | GDScript（项目把 unsafe 系列警告全部当错误，见 `project.godot` 的 `[debug]`） |
| 编辑器插件 | `addons/godot_ai`（AI 辅助开发用 MCP 插件，不影响游戏逻辑） |

## 目录结构

```
├── project.godot            # 引擎配置（主场景、输入映射、警告策略）
├── poker.json               # 默认卡组（54 张扑克，含大小王）
├── Game.tscn / game.gd      # 主场景：大厅、会话、暂停菜单、清场、聊天、玩家管理
├── Card.tscn / card.gd              # 3D 卡牌：拖动、翻面、tooltip、入堆检测
├── Pile.tscn / pile.gd              # 牌堆：抽牌、计数、可视高度
│   └── 子组件（见"牌堆子系统"）
├── Counter.tscn / counter.gd        # 计数器：3D 按钮交互、数值 RPC
├── CounterViewerUI.*                # 计数器 2D 查看器
├── DeckViewerUI.* / UICard.*        # 牌堆 2D 查看器与 UI 卡牌
├── deck_template.gd / deck_instance.gd / deck_json.gd / card_template.gd
│                                      # 卡组数据模型与 JSON 解析校验
├── card_database.gd         # 卡组运行时访问入口 + 翻面 RPC
├── card_sorter.gd           # 桌面散牌的高度管理（服务器权威）
├── deck_change.gd           # 换卡组两阶段事务
├── owner_mux.gd / dragger.gd / util.gd / const.gd   # 通用组件
├── player.gd / Player.tscn  # 玩家角色（双模式、相机挂载）
├── chat_panel.gd / chat_banner.gd   # 聊天 UI
├── card_description_tooltip.gd      # 3D/UI 卡牌共用的悬停提示
├── hotspot.gd               # 牌堆侧面的"底"/"随"抽牌热点
├── sfx_manager.gd           # 全局音效/背景音乐管理（autoload `Sfx`）
├── sounds/                  # 音效与背景音乐（wav）
├── tests/                   # 自动化测试（GDScript + Python 运行器）
└── docs/                    # 各功能的设计文档
```

## 网络架构总览

- **拓扑**：星形，host 固定 `peer id = 1` 即服务器；所有状态变更由服务器执行后广播。客户端不信任本地推算。
- **RPC 风格**：统一 `request_xxx()`（本地判断是服务器则直接调，否则 `rpc_id(1, ...)`）→ 服务器端 `server_xxx()` 校验 → `sync_xxx`（`"authority", "call_local"`）广播落地。工具函数见 `util.gd` 的 `is_server / not_server / my_id / sender_id`。
- **同步**：位置类高频数据用 `MultiplayerSynchronizer`（如 `Card`、`Pile`、`Counter` 根节点的 position）；低频离散状态用可靠 RPC 广播（翻面、牌堆栈、计数器数值、聊天）。

### OwnerMux：占用复用器（核心并发原语）

`owner_mux.gd` 是所有可交互物件的**分布式互斥锁 + 操作语义**：

- `_owner`（peer id，0 表示空闲）+ `purpose`（`Const.Purpose`：`DRAG`、`PILE_VIEW`、`PILE_OUTPUT_*`、`COUNTER_VIEW`、`COUNTER_ADD` …）
- `request_own(purpose)` → 服务器 `server_set_owner`（已被人占用/清场锁定则拒绝）→ `_set_owner` 广播（切换节点的 `multiplayer_authority`，让占用者的 Synchronizer 开始同步位置）→ 发 `on_owner_change` 信号
- `request_release()` → `server_reset_owner` → authority 归还服务器
- 玩家掉线时 `server_recover_mux` 自动回收其占用的物件
- **瞬时占用事务**（抽牌、放牌入堆、计数器加减）：短暂 own → 服务器改状态 → sync → reset，同一物件的并发操作天然串行化
- **持续占用**（拖动、查看器）：保持占用直到释放；新玩家尝试 request_own 会被拒绝

### Dragger：通用拖动组件

`dragger.gd` 被卡牌/牌堆/计数器复用。管理"请求拖起→动画升起→跟随鼠标（射线与水平面求交，只改 XZ）→请求放下→落下"的状态机，并通过 `_sync_rot_y` 把拖动物朝向同步为拖动者相机朝向。`suspend_local_interaction` 用于暂停菜单/换库时冻结本地操作。

## 各模块速览

| 文件 | 职责 |
| --- | --- |
| `game.gd` | 会话生命周期：开房/加入、玩家增删、暂停菜单、花名册同步、聊天服务端（中继/历史/限流）、一键清场、一键清计数器、计数器生成定位 |
| `card_database.gd` | 卡组运行时入口（牌名/描述/优先级/正反面查询）；`request_flip` 翻面 RPC；`on_flip` 信号驱动 3D/UI 卡牌刷新 |
| `card_sorter.gd` | 桌面散牌的"牌塔"：维护 `card_ID_stack` 决定每张牌的高度；牌被抓起时出栈、放下时入栈并触发全体重排（服务器权威，Synchronizer 同步高度） |
| `pile.gd` + 子组件 | 见下节 |
| `pile_card_spawner.gd` | 依据占用 purpose 从顶/底/随机弹牌生成 3D 卡牌；`server_spawn_card_by_IDs` 供查看器批量出牌 |
| `pile_card_receiver.gd` | 卡牌入堆事务：占用 → push 到栈顶/栈底/随机位置 → sync → 回收 3D 节点 → 释放 |
| `pile_accessor.gd` | 牌堆查看事务：右键 → `PILE_VIEW` 占用 → 生成 `DeckViewerUI`；确认抽取时服务器出牌+更新栈+释放 |
| `counter.gd` + 子组件 | 见下节 |
| `deck_change.gd` | 换卡组事务（见下文） |
| `player.gd` | 双模式角色：`CARD`（默认）/`MOVE`，相机 reparent 到玩家 pivot，`input_enabled` 门控所有输入 |
| `chat_panel.gd / chat_banner.gd` | 聊天面板（历史 RichTextLabel + TextEdit）、通知横幅栈（入场/退场动画、排队、过期回收） |
| `card_description_tooltip.gd` | 悬停提示：3D 卡牌与 UI 卡牌共用，挂在 `/root` 的浮层 |
| `deck_json.gd` | 卡组 JSON 静态校验（尺寸/类型/数量/ID 规范），本地预检、服务器校验、认证加载三处共用 |
| `util.gd` | 消息/昵称清洗、鼠标事件判定、tween 封装、`board_locked`（清场全局锁）等 |
| `sfx_manager.gd` | 音效系统：`SfxManager.I.play()` 对象池轮转、悬停 50ms 去抖、批量抽牌同帧合并、±1 半音随机音高，headless 下只记录 `_history` 不出声；`node_added` 自动为按钮挂悬停/确认音（`sfx_no_confirm` 组可排除）；背景音乐进房 10 秒后循环、离房停止 |

## 牌堆子系统（Pile 组合）

`Pile.tscn` = 底座 StaticBody3D + `OwnerMux` + `Dragger` + `CardSpawner`（抽牌）+ `CardReceiver`（收牌）+ `Accessor`（查看）+ 两个 `Hotspot`（Area3D，`label_name`="底"/"随"）。

牌堆本体维护 `card_ID_stack: Array[int]`（前=顶）。可视高度 = 牌数 × 0.01 + 底座厚度，Label 与碰撞体同步缩放。晚加入的玩家在 `_ready` 时向服务器请求 `server_sync_card_ID_stack` 补齐状态。

## 卡牌生命周期

```
牌堆栈中(仅数据) --抽牌事务--> 3D Card 节点(CardSorter 下, 入栈维护高度)
      ^                                   |
      |            左键点击牌堆/热点        | 抓起(DRAG 占用, 出栈)
      +-------- receiver 事务收牌 <--------+ 放下(回栈, 重排高度)
```

- 卡牌节点名即 `card_ID`，通过 `CardDatabase` 查牌名/描述/正反面
- 3D 牌（`card.gd`）与 UI 牌（`ui_card.gd`，查看器内）都监听 `on_flip` 信号统一刷新

## 计数器实现（Counter）

- 根 StaticBody3D 挂 3 个 `CollisionShape3D`：`0=底座`、`1=减号`、`2=加号`，`_input_event` 按 `shape_idx` 分发，另有 `event_position` 落点兜底校验
- 3D 视觉：紫色半透明底座 + 两片白色按钮 + 黑色 +/- Label3D + 居中数值 Label3D
- 数值状态 `value / step / decimals` 通过 `sync_counter_state`（`"any_peer", "call_local"`）广播 + `state_changed` 信号刷新查看器；显示用 printf 定点格式 `("%."+str(decimals)+"f") % x`（不用 `String.num`，它会裁剪末尾零），负零归一为 0
- 加减为瞬时占用事务（`COUNTER_ADD/SUBTRACT`），与牌堆抽牌同构；唯一特例：当前查看者点击 +/- 时跳过占用直接改值，避免打断自己的查看器
- 晚加入时向服务器请求 `server_sync_counter_state` 补齐
- 添加计数器仅房主（暂停菜单按钮）；删除需 sender 为服务器(=房主)或当前 owner；位置自动避让现有计数器与牌堆（距离 < 2.0）

## 换卡组事务（DeckChange）

两阶段全端同步，`transaction` 计数器防串台，任何阶段检测到连接变化即中止：

1. `begin_change`：全体关闭弹窗/查看器、释放占用（等待 OwnerMux 广播回来）、暂停菜单强制打开显示进度
2. `install_change`：服务器清空桌面节点后广播新卡组 JSON，各端重新 `init_deck_instance`，ack 后服务器 `_rebuild_board`
3. 服务器换库期间 `refuse_new_connections`，对正在认证中的 peer 直接断开；15 秒超时踢人

## 加入认证流程（DeckInstance 快照走 auth 通道）

1. 客户端 `create_client` → `peer_authenticating`
2. 服务器 `send_auth(id, 卡组快照 JSON)`（换库中则拒绝）
3. 客户端用快照初始化本地 `DeckInstance`，回 `{version: 1, deck_ready: true, player_name}`
4. 服务器校验后 `complete_auth`，随后 `peer_connected` 生成玩家节点 + 个人空牌堆 + 广播花名册
5. 客户端进入房间后 `call_deferred` 请求花名册与聊天历史

## 清场与全局锁

- `clear_table_in_progress` 是全局互斥锁：清场、清计数器、换卡组共用；期间 `Util.board_locked()` 拒绝一切 `request_own` / 翻面 / 收牌等申请
- 清场流程：广播 `set_clear_table_busy(true)` + `prepare_for_table_clear`（关查看器/弹窗）→ 删旧节点并等 `queue_free` 真正离树 → `_rebuild_board`（满编公共牌堆按模板优先级排序 + 每人空牌堆）→ 解锁
- 一键清计数器独立于清场（不动牌堆），但复用同一把锁

## 项目约定

- **unsafe 警告当错误**：`unsafe_property_access / unsafe_method_access / unsafe_cast / unsafe_call_argument / unsafe_void_return` 全部置 2；跨类型调用先显式转型（如 `var key_event := event as InputEventKey`）
- RPC 一律显式标注 `[("any_peer"|"authority"), ("call_local"|"call_remote"), "reliable"]`；客户端发往服务器的请求在服务器端用 `Util.sender_id()` 取发送者，注意 host 本地直调时 sender 为 0 需映射为 1
- "preready" 模式：实例化后、`add_child` 前调用 `preready(...)` 注入初始数据（节点名、栈内容），`_ready` 时生效
- 服务器权威：客户端函数只做"申请"，所有状态变更都在服务器函数里校验（占用、锁、合法性）后广播

## 自动化测试

`tests/` 下每个功能对应一组 GDScript 测试（按角色分进程）+ Python 编排脚本：

| 脚本 | 覆盖 |
| --- | --- |
| `run_player_name_tests.py` | 昵称清洗、花名册同步 |
| `run_deck_change_tests.py` | 卡组校验、换库事务 |
| `run_chat_tests.py` | 消息清洗、通知横幅、焦点互斥、快捷键不误触、联机收发 |
| `run_counter_tests.py` | 计数器解析/格式化、3D 按钮路由、占用互斥、查看器编辑、晚加入同步、一键清计数器 |
| `run_sfx_tests.py` | 音效：解析与本地行为、拖动/抽牌/入堆/翻面广播音、查看器理牌音、2D 翻面仅本端、批量抽牌同帧合并 |

运行方式（以计数器为例）：

```bash
python3 tests/run_counter_tests.py
```

流程：`parser`（纯解析，无窗口）→ host 先起（headless 自动开房）→ `client` 连入执行全流程 → `late_join` 验证状态补齐 → 断言各角色的 marker（`PARSER_OK` / `HOST_*_OK` / `CLIENT_OK`）与退出码。测试复用生产 `Game.tscn`，仅以 `deck_test_game.gd` 抑制无头自动开房。注意 runner 用行迭代器读 host 输出后**不要**再混用 `communicate()`（迭代器预读缓冲会丢行），统一用同一个文件对象排空。

## 相关设计文档

- [docs/counter-design.md](docs/counter-design.md) — 计数器完整设计（含已确认决策记录）
- [docs/sound-effects-design.md](docs/sound-effects-design.md) — 音效系统设计（触发点对照、测试用例表）
- [docs/in-room-chat-design.md](docs/in-room-chat-design.md) — 房间聊天设计
- [docs/player-name-customization.md](docs/player-name-customization.md) — 玩家昵称与花名册
- [docs/card-text-wrapping-and-centering.md](docs/card-text-wrapping-and-centering.md) — 卡牌文本排版
- [docs/godot-472-and-godot-ai-mcp.md](docs/godot-472-and-godot-ai-mcp.md) — Godot 4.7.2 与 godot-ai MCP 环境说明
