# 玩家名称自定义与暂停界面玩家列表调研

## 调研结论

该需求可以在现有架构内完成，不需要替换 ENet、场景复制或卡牌同步方案。项目已经使用 `SceneMultiplayer` 的认证回调和服务器权威的 `peer_id`，认证阶段可以安全地携带玩家名称；暂停界面也已经有统一入口，适合增加只读玩家名册。

推荐把玩家名称保存为独立的显示名字段，不要修改 `Player.name`。原因是 `Player._enter_tree()` 使用 `name.to_int()` 设置多人权限，`create_pile_for_player()` 使用 `player.name` 生成牌堆节点名。把节点名改成自定义文本会同时破坏玩家权限和牌堆标识。

本机使用的 Godot 版本已确认是 `4.7.2.stable.official.ed1daf0bf`。编辑器通过 Godot AI MCP 报告当前场景为 `res://Game.tscn`，项目状态为 ready；现有 `deck_change_test.gd` 的 parser 测试也已通过。需求需要的 `LineEdit.max_length`、`SceneMultiplayer.send_auth()`、`SceneMultiplayer.complete_auth()`、`Node.rpc()` 和 `Node.rpc_id()` 均存在于该版本。

## 实现状态

该方案已经完成首轮实现。大厅新增共享名称输入框，认证确认消息升级为带版本号的 JSON，服务器清洗名称后写入 `Player.display_name`，暂停界面通过服务器名册显示在线玩家、主机标记和本地玩家标记。

名称清洗放在 `Util.sanitize_player_name()`，便于独立测试。专用测试位于 `tests/player_name_test.gd`，双进程运行器位于 `tests/run_player_name_tests.py`。真实编辑器画面已经检查大厅和暂停面板，现有牌库网络回归也保持通过。

## 当前结构

项目的联机入口、认证、暂停菜单和玩家创建都集中在 `game.gd`。`_ready()` 注册连接和认证信号，`start_server()` 创建 ENet 服务端，`_on_join_button_pressed()` 创建客户端，`_on_peer_authenticating()` 与 `_on_auth_data_received()` 完成牌库快照同步，`_on_peer_connected()` 在服务器创建 `Player`。

`Game.tscn` 的大厅位于 `CanvasLayer/MainMenu`，当前只有主机端口、加入 IP 和加入端口。暂停面板位于 `PauseCanvasLayer/PauseOverlay/PanelContainer`，当前包含工具提示开关、返回游戏、一键清场、更换卡组和退出房间，没有玩家列表。

`Player.tscn` 的根节点名由服务器设置为 `str(peer_id)`。`player.gd` 使用该节点名确定权限，`Player.tscn` 的 `MultiplayerSynchronizer` 同步位置和旋转。`Players` 节点下的玩家由 `MultiplayerSpawner_Players` 自动复制，现有机制足够支持玩家加入和离开，不需要为名称另建生成器。

## 可行性判断

该需求的数据量很小，每个玩家只需要一个 `peer_id` 和一个显示名。认证流程天然知道消息来自哪个连接，服务器可以忽略客户端自称的身份，只使用 `multiplayer.get_remote_sender_id()` 建立映射。后加入的玩家可以通过服务器名册获取已有玩家名称，因此不需要依赖先前广播是否已经到达。

实现风险主要集中在三处。第一处是认证数据格式需要从固定字符串升级为带版本号的 JSON。第二处是服务器创建 `Player` 时要把名称一起写入，并在断开、认证失败和返回主菜单时清理缓存。第三处是暂停面板高度和列表刷新时机，需要保证列表在打开时拿到服务器确认的数据。

预计核心逻辑改动约 120 至 180 行，场景节点改动约 30 至 60 行。现有牌库认证、卡牌复制、场景生成和权限设计均不需要重构。

## 推荐方案

### 数据模型

在 `player.gd` 增加显示名字段：

```gdscript
var display_name: String = ""
```

在 `GameSession` 中保存服务器权威名称和待认证名称：

```gdscript
var pending_player_names: Dictionary = {}
var player_names: Dictionary = {}
var player_roster_cache: Array = []
```

`pending_player_names` 的键是认证中的 `peer_id`，值是通过认证时客户端提交的名称。`player_names` 的键是已经进入房间的 `peer_id`，值是服务器清洗后的最终名称。`player_roster_cache` 保存最近一次由服务器发送给当前客户端的只读名册。

服务器的联机事实来源是 `player_names` 和服务器 `Players` 节点下的 `Player.display_name`。客户端暂停界面只展示服务器名册，不直接把任意客户端发来的名称当成可信数据。

### 大厅输入框

在 `Game.tscn` 的主菜单 `VBoxContainer` 顶部增加一个名称行，包含 `Label` 和 `LineEdit`。建议节点名为 `InputPlayerName`，设置 `placeholder_text = "玩家名称"`、`max_length = 24`，并给输入框设置稳定的最小宽度。

创建房间和加入房间共用同一个名称输入框。点击创建房间时，在主进程创建本地 `Player` 之前读取一次名称；点击加入房间时，在发起 ENet 连接之前读取一次名称，并保存到 `requested_player_name`。连接发起后不再从输入框重新读取，这样认证期间修改文本不会造成客户端显示名和服务器记录不一致。

空白名称由服务器回退为 `"玩家" + str(peer_id)`。客户端也可以提前显示提示，但最终校验必须放在服务器。

### 认证携带名称

现有客户端认证确认是固定字符串 `deck_instance_ready`。建议保留原来的两步握手，只把客户端返回的数据升级为 JSON：

```json
{
  "version": 1,
  "deck_ready": true,
  "player_name": "玩家名称"
}
```

服务端仍先向客户端发送 `DeckInstance` 快照。客户端完成 `card_db.init_deck_instance_from_json_str()` 后，构造包含 `deck_ready` 和 `player_name` 的 UTF-8 JSON，再调用 `scene_multiplayer.send_auth(1, payload)`。

服务器在 `_on_auth_data_received(id, data)` 中执行以下检查：

1. 认证数据大小设置上限，例如 1 KiB，避免异常大包进入 JSON 解析。
2. JSON 必须解析为字典。
3. `version` 必须等于当前协议版本。
4. `deck_ready` 必须为 `true`。
5. 名称只从当前认证连接的数据中读取，键使用认证事件的 `id`。

校验通过后，先写入 `pending_player_names[id]`，再调用 `scene_multiplayer.complete_auth(id)`。认证失败、超时或断开时同时删除该 `id` 的待处理名称。

这种修改保持现有牌库快照和认证顺序，不增加第三个网络连接，也不改变玩家进入房间后的场景生成流程。

### 服务器关联名称

`add_player()` 改为接收显示名：

```gdscript
func add_player(id: int, display_name: String) -> Player:
	var player := PLAYER.instantiate()
	player.name = str(id)
	player.display_name = display_name
	player_names[id] = display_name
	players.add_child(player)
	return player
```

本地主机创建服务器时，名称来自大厅输入框。远程玩家在 `_on_peer_connected(id)` 触发时，从 `pending_player_names` 取出名称，然后创建 `Player`。`peer_connected` 在该项目现有的认证顺序之后触发，因此名称在此之前已经到达服务器。

`_on_peer_disconnected()` 需要同时删除 `player_names[id]` 和 `pending_player_names[id]`。`_on_peer_authentication_failed()`、`_return_to_main_menu()` 和连接超时清理也要清空待处理名称，防止同一个 `peer_id` 重连时使用旧名称。

`Player.name` 仍然是 `str(peer_id)`，`display_name` 只用于界面和未来可能的玩家标识。这样可以保持 `player.gd` 的权限计算、`create_pile_for_player()` 的牌堆名称以及 `MultiplayerSpawner` 的节点路径不变。

### 服务器名册同步

暂停界面需要看到所有玩家，推荐由服务器生成名册并发送给客户端。服务器可以遍历 `Players` 子节点，按 `peer_id` 排序后生成 `Array[Dictionary]`，每项包含 `id`、`name` 和 `is_host`。客户端只展示该数组。

建议增加两个 RPC：

```gdscript
@rpc("any_peer", "call_remote", "reliable")
func request_player_roster() -> void:
	if Util.not_server(self):
		return
	var sender_id := Util.sender_id(self)
	receive_player_roster.rpc_id(sender_id, _build_player_roster())


@rpc("authority", "call_remote", "reliable")
func receive_player_roster(roster: Array) -> void:
	player_roster_cache = roster
	_apply_roster_to_player_nodes(roster)
	_refresh_player_list()
```

打开暂停菜单时，主机直接调用 `_apply_roster`，客户端调用 `request_player_roster.rpc_id(1)`。服务器在玩家加入、断开或名称变化后也可以主动调用 `receive_player_roster.rpc(roster)` 更新所有已连接客户端。请求式刷新保证新玩家一定拿到完整名册，主动广播保证暂停界面打开期间能及时看到变化。

客户端收到名册后，还可以按 `peer_id` 找到对应的 `Player` 节点并写入 `display_name`。该字段在客户端是展示缓存，服务器上的 `player_names` 和服务器 `Player.display_name` 才是名称事实来源。

如果后续需要把名称复制到所有客户端而不经过暂停菜单，可以再增加一个服务器权限的 `MultiplayerSynchronizer` 同步 `display_name`。当前需求只需要暂停界面查看，增加同步器会扩大场景复制和权限验证范围，建议放到后续迭代。

### 暂停界面玩家列表

在暂停面板的 `VBoxContainer` 中增加 `Label` 和 `ItemList`。建议把 `PlayerList` 的 `custom_minimum_size.y` 设置为 96 至 140 像素，列表只读展示，不接受玩家编辑。面板当前的固定高度约 290 像素，增加列表后应同步扩大上下偏移，例如把 `offset_top` 和 `offset_bottom` 调整为能容纳约 460 至 500 像素内容。

每行建议使用 `名称  [ID]` 的格式。主机行增加 `[房主]`，本地玩家行增加 `[我]`。玩家默认允许重名，通过 `peer_id` 区分；如果未来要求名称唯一，必须由服务器在认证阶段执行唯一性校验，并向客户端返回明确错误。

暂停菜单打开时刷新列表，菜单关闭时不需要销毁缓存。下一次打开可以立即显示最近一次名册，同时发起一次请求，确保内容最终与服务器一致。

## 修改范围

| 文件 | 需要的修改 | 风险 |
| --- | --- | --- |
| `game.gd` | 增加名称状态并调用清洗函数；修改认证载荷；修改 `add_player()`；增加名册 RPC、缓存更新和断开清理；暂停菜单打开时刷新列表 | 中，认证协议和连接生命周期是主要回归点 |
| `Game.tscn` | 大厅增加名称 `Label` 与 `LineEdit`；暂停面板增加玩家列表；扩大暂停面板并连接必要信号 | 低到中，主要是布局适配 |
| `player.gd` | 增加 `display_name` 字段，保持节点名和权限逻辑不变 | 低 |
| `util.gd` | 增加名称清洗、空白标准化、长度截断和空名称回退 | 低 |
| `tests/player_name_test.gd` | 覆盖名称清洗、服务器关联、客户端名册和暂停列表 | 中，包含双进程网络测试 |
| `tests/run_player_name_tests.py` | 启动 parser、主机和客户端测试流程 | 低 |
| `Player.tscn` | 推荐方案不修改；只有后续增加世界内名称牌或服务器权威同步器时才需要改 | 当前不需要 |
| `project.godot` | 不需要修改 | 无 |

## 关键兼容约束

名称清洗必须在服务器执行。建议先替换换行和制表符，再执行 `strip_edges()`，最后按字符数截断到 24 个字符。客户端输入框的 `max_length` 只能改善交互，不能代替服务器校验。

协议需要带版本号。旧客户端发送纯字符串 `deck_instance_ready` 时，新服务器应拒绝认证并断开连接；新客户端向旧服务器发送 JSON 时，旧服务器会因无法匹配固定确认字符串而拒绝认证。正式发布时应让客户端和服务器保持同一版本。

玩家名只作为纯文本显示，暂停列表应使用 `ItemList` 或普通 `Label`。如果以后改用启用 BBCode 的 `RichTextLabel`，需要对名称中的标记字符进行转义。

名称允许中文、Emoji 和其他 Unicode 字符。JSON 使用 UTF-8 编码，现有 `to_utf8_buffer()` 和 `get_string_from_utf8()` 可以直接复用。服务端截断应基于字符串长度，不按字节数截断。

暂停菜单依赖 `local_player` 已建立。当前逻辑只在 `session_active` 且 `local_player` 有效时打开暂停菜单，因此玩家列表请求不会在玩家节点尚未生成时发出。

无头服务器不创建主机玩家，未来可以只在有客户端加入时生成名册。当前需求面向带界面的创建和加入房间流程，无头模式不需要名称输入。

## 边界情况

空白名称回退为 `玩家<peer_id>`。名称前后空白会被移除，连续换行和制表符会变成空格。超长名称截断到 24 个字符。

重名允许存在。列表通过 `[ID]` 区分，主机和本地玩家使用额外标记。如果产品要求拒绝重名，服务器需要在 `pending_player_names` 写入前检查已在线名称，并在拒绝后通过认证失败流程断开客户端。

玩家在认证过程中断开时，`pending_player_names` 必须删除。认证完成但 `complete_auth()` 返回错误时，也要删除待处理名称，避免残留数据被相同 `peer_id` 复用。

玩家在房间内断开时，服务器先删除 `player_names` 和 `Player` 节点，再广播新名册。客户端收到名册后按当前节点集合更新列表，避免展示已经离开的玩家。

玩家返回主菜单后再次加入时，输入框内容可以保留，方便重新使用或修改。服务器侧缓存、客户端名册缓存和 `Player.display_name` 必须清空。

更换卡组期间，服务器当前会拒绝新玩家认证。名称逻辑应沿用这个行为，不要在 `deck_change.active` 时创建待处理名称。

## 测试计划

现有 parser 和牌库回归测试先保持通过。新增测试至少覆盖名称清洗的纯函数，包括空名称、首尾空格、换行、超长名称、中文名称和 Emoji。

网络测试使用同一台机器启动一个主机和两个客户端。主机使用名称 `房主` 创建房间，第二个客户端使用 `玩家二` 加入，第三个客户端使用 `玩家三` 后加入。三个客户端打开暂停菜单后都应看到相同的完整名册。

断开测试让 `玩家二` 退出，确认主机和 `玩家三` 的名册不再包含该玩家。认证失败测试发送错误版本、缺少 `deck_ready` 和超大 JSON，确认服务器拒绝连接且没有残留 `pending_player_names`。

重名测试让两个客户端使用相同名称，确认列表能依靠 ID 区分。空名称测试确认服务器将客户端空字符串替换为回退名称。

回归测试继续运行现有牌库认证、换卡组、清场和重连流程，重点确认 JSON 认证改动没有影响 `DeckInstance` 同步。

## 实施顺序

1. 在 `player.gd` 增加 `display_name`，保持 `Player.name` 的现有用途。
2. 在 `Game.tscn` 增加大厅名称输入框和暂停玩家列表，先使用静态占位数据检查布局。
3. 在 `game.gd` 增加名称清洗、主机名称读取和客户端名称暂存。
4. 升级认证确认载荷，服务器解析名称并写入 `pending_player_names`。
5. 修改玩家创建流程，将名称写入服务器 `Player` 和 `player_names`。
6. 增加名册 RPC、客户端缓存和暂停列表刷新。
7. 完整处理认证失败、断开、返回主菜单和重新连接时的清理。
8. 增加名称与三人联机测试，并运行现有牌库回归测试。

该顺序可以先独立验证 UI，再接入网络逻辑，便于在认证协议改动出现问题时快速区分布局问题和联机问题。

## 暂不包含

本次需求没有要求在房间内改名、保存上次名称、跨房间名称持久化、名称唯一性、管理员踢人或名称审核。如果后续增加房间内改名，应在服务器名册写入成功后广播更新，并继续使用服务器端清洗和长度限制。

如果后续需要在 3D 玩家上方显示名称，可以为 `Player.tscn` 增加 `Label3D`，名称文本只从服务器授权的同步字段读取。该功能和暂停列表可以复用同一份名称数据，当前文档不把它列入首轮实现。
