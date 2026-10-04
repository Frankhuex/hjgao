# HJGAO 项目协作指南

本文件适用于整个仓库。开始任务时先阅读本文件，再阅读相关设计文档和实际源码；文档中的设计方案、历史代码片段和“实现状态”可能落后于当前代码，应核实后再修改。用户当前指令优先于本指南。

## 沟通与工作约定

- 默认用中文沟通，禁止使用先否定再转折对照的句式。使用连贯、紧凑的段落，避免频繁换行、无意义的纯文本代码框和流程图；代码框仅用于可执行命令、代码或有效配置示例。
- 修改前检查 `git status --short`，保留已有改动。围绕任务做必要修改，不顺带重构、不覆盖无关文件，不默认提交或推送。
- 搜索文件和文本优先使用 `rg --files`、`rg`。新增功能遵循现有组件和服务器校验方式，修改实现后同步更新相关文档中的已知差异。
- 保留 Godot 的 `.gd.uid`、`.gdshader.uid` 和资源引用；移动或重命名脚本、场景时检查所有引用。`.godot/` 是生成缓存，不作为源码修改。`Game.tscn.bak`、`nohup13002.out` 属于备份或运行产物，开发以正式场景和脚本为准。
- `addons/godot_ai/` 是第三方插件，附有 `godot-ai-LICENSE.txt`。业务功能优先在项目代码中实现，修改插件须有明确的任务原因。

## 项目概况与结构

HJGAO 是 Godot 4.7.2 / GDScript 编写的多人 3D 桌面棋牌工具，使用 ENet、MultiplayerSpawner、MultiplayerSynchronizer 和 RPC。入口为 `res://Game.tscn`，根脚本类为 `GameSession`，运行时根路径为 `/root/Game`。主要脚本、场景和着色器直接放在仓库根目录，没有独立的 `src/`。`project.godot` 注册 `Sfx` 和 `_mcp_game_helper` 两个 autoload，启用 Godot AI 插件。

| 文件或目录 | 职责 |
| --- | --- |
| `Game.tscn` / `game.gd` | 大厅、开房/加入、认证、玩家与桌面容器、暂停菜单、聊天、清场、计数器生成、会话清理 |
| `Player.tscn` / `player.gd` | 玩家权限、CARD/MOVE 模式、移动与相机、输入启停、显示名 |
| `Card.tscn` / `card.gd` / `Card.gdshader` | 桌面 3D 散牌、翻面、拖动、入堆检测、牌名和说明提示 |
| `Pile.tscn` / `pile.gd` | 牌堆数据栈、外观高度、碰撞与状态同步 |
| `pile_card_spawner.gd` / `pile_card_receiver.gd` / `pile_accessor.gd` | 顶/底/随机出牌、收牌、查看器事务及正逆位请求校验 |
| `Hotspot.tscn` / `hotspot.gd` | 牌堆“底”“随”热点，选择抽牌或入堆来源 |
| `DeckViewerUI.tscn` / `deck_viewer_ui.gd` | 本地牌堆查看、排序、洗牌、翻面、正逆位、拖动与确认取牌 |
| `UICard.tscn` / `ui_card.gd` / `UICard.gdshader` | 2D 卡牌显示、拖动预览、翻面与正逆位交互 |
| `Counter.tscn` / `counter.gd` | 3D 计数器、加减按钮拾取、数值同步与拖动 |
| `CounterViewerUI.tscn` / `counter_viewer_ui.gd` / `counter_accessor.gd` | 计数器查看、数值/步长/小数位编辑与删除 |
| `OwnerMux.tscn` / `owner_mux.gd` | 分布式占用互斥与操作用途，动态切换多人权限 |
| `Dragger.tscn` / `dragger.gd` | 卡牌、牌堆、计数器共用拖动、升降动画、朝向同步 |
| `card_sorter.gd` | 服务器维护桌面散牌栈与落牌高度 |
| `card_template.gd` / `deck_template.gd` / `deck_instance.gd` | 卡牌模板、卡组模板、按唯一 ID 索引的运行时卡组及快照 |
| `deck_json.gd` / `card_database.gd` | JSON 校验、运行时查询、正反面与正逆位同步 |
| `deck_change.gd` | 全端换卡组事务、确认、超时与重建 |
| `ChatPanel.tscn` / `chat_panel.gd` / `ChatBanner.tscn` / `chat_banner.gd` | 聊天历史、输入焦点、实时通知与动画 |
| `CardDescriptionTooltip.tscn` / `card_description_tooltip.gd` | 3D 与 UI 卡牌共用的说明浮层 |
| `sfx_manager.gd` / `sounds/` | 音效播放池、按钮钩子、播放记录与背景音乐 |
| `util.gd` / `const.gd` | 服务器/发送者工具、输入判定、文本清洗、全局锁、枚举与映射 |
| `deck_instances/` | 内置卡组 JSON，如扑克、UNO、塔罗、三国杀等 |
| `tests/` | GDScript 按角色测试及 Python 多进程运行器 |
| `docs/` / `README.md` | 功能设计、工具用法与项目操作说明 |
| `export_presets.cfg` / `headlessrun.sh` | 导出配置与历史部署脚本；部署脚本引用已有 Linux 二进制，使用前核实路径 |

## 核心知识与修改约束

### 权威、占用与生命周期

服务器 peer ID 固定为 `1`。沿用“本地 request 方法 → 服务器 server 方法校验 → sync RPC 广播”的风格。离散业务状态通常用 reliable RPC；位置由 Synchronizer 复制，`Dragger._sync_rot_y` 当前使用 unreliable RPC。新增 RPC 显式声明发送权限、调用方式和传输模式，服务端检查真实发送者、占用、全局锁和参数合法性。主机本地直调时 remote sender 可能为 `0`，按现有代码将其映射为 `1`。动态 authority 会随 OwnerMux 变化，修改 RPC 时核实实际所属节点的权限。

`OwnerMux` 同时保存 owner 和 `Const.Purpose`。owner 为 `0` 表示空闲；DRAG、PILE_VIEW、COUNTER_VIEW 持续占用，抽牌、入堆和加减是短暂占用事务。`request_own()` 返回成功仅表示申请发出，操作是否获准取决于服务器广播和 `on_owner_change`。占用切换会修改父节点 multiplayer authority；释放后归还服务器，断线时服务器回收。不要绕过此机制创建第二套互斥状态。

清牌、清计数器和换卡组共用 `clear_table_in_progress` / `Util.board_locked()` 门控。先置锁、关闭查看器并释放交互，等待待删除节点真正离树后再重建或解锁。“一键清场”重建牌堆和散牌并重置正反面/正逆位，保留计数器；“一键清计数器”仅删除计数器。暂停、断线、离房和换库都须清理查看器、焦点与本地交互。查看器可能直接挂在 `/root` 下，清理时不能只遍历 Game 子树。

玩家由 MultiplayerSpawner 的自定义生成函数携带 peer ID、显示名和服务器随机选择的四边方向生成，入树前通过 Player.preready 复用主菜单摄像机初始位置，并计算面向桌面中心的水平朝向和固定俯角；客户端不得重新随机。玩家占第 2 碰撞层，仅检测第 1 层，允许玩家互相穿行。

实例化对象沿用 `preready(...)`：在 `add_child()` 前注入 ID、名称、位置或栈数据，供 `_ready()` 使用。`Player.name` 是 peer ID 字符串，Card 节点名是 card ID；这些名称参与权限和数据索引，禁止用显示名替换。

### 卡组、牌堆与朝向

`DeckJson.parse()` 是本地预检、服务器校验和认证加载的共用入口，成功前不修改活动卡组。当前限制为 JSON ≤1 MiB、总牌数 ≤1000、牌名 ≤64 字符、描述 ≤1000 字符；名称唯一，数量为正整数，显式 ID 映射必须与模板一致，JSON ID 键为规范正整数字符串（拒绝 `01`）。修改格式时维护模板加载、运行时序列化、旧卡组兼容与认证快照往返。

牌堆 `card_ID_stack` 的前端是顶牌，堆内卡牌仅保存为数据；抽取后由 `PileCardSpawner.server_spawn_card_by_IDs()` 创建 Card，放回后回收 3D 节点。`CardSorter` 负责散牌栈与高度：拿起时移出，落下时注册并重排。

当前源码已实现 `card_ID_to_is_front` 和 `card_ID_to_is_upright` 两个独立布尔映射，缺省均为 `true`，快照会序列化二者。普通右键翻面，Shift+右键切换正逆位；查看器已有全部正位、全部逆位、全部颠倒、随机正反面和随机正逆位操作。新增状态请求沿 `DeckViewerUI` 信号到 `PileAccessor`，服务器校验 PILE_VIEW owner、全局锁和牌 ID 属于目标堆后应用；批量操作取上方牌列 ID，不包含下方待抽取区。2D 旋转由 UICard 的视觉子节点承担，保留外层布局和拾取区域。3D 出牌按正逆位初始化根节点 Y 旋转，翻面由 Pivot 的 X 旋转承担，spawn 同步包含 rotation。

`Dragger.auto_orientation_enabled` 是本地偏好，开启后拖动朝向跟随相机，并由 RPC 同步结果；关闭时保留当前朝向。拖动不反写牌堆正逆位，也不持续叠加逆位的 180 度偏移。正逆位设计稿的部分步骤与验收描述存在历史差异，以当前源码和任务要求核实。

3D `Label3D` 和 UI `Label` 共用 CardDatabase 牌名。当前两套场景已有智能换行与居中；3D 文本 `width=100`，`pixel_size=0.005` 对应约 0.5 世界单位。卡面尺寸变化须同步检查文本宽度、边距和拖动预览。64 字符极端名称的高度适配属于文档中的扩展方案，不能仅凭换行设置声称所有名称都不越界。

### 认证、换库、聊天和计数器

加入时服务器先通过 SceneMultiplayer auth 通道发送 DeckInstance 快照，客户端加载后回 `{version: 1, deck_ready: true, player_name: ...}`；服务器校验再 complete_auth，随后创建玩家、个人牌堆并同步名册。显示名由服务器清洗，最长 24 字符，空白回退为 `玩家<peer_id>`，允许重名并用 peer ID 区分。认证确认载荷上限为 1024 字节，失败/断线/退出时清理待认证名称与名册缓存。

换卡组使用 `DeckChange` 两阶段事务：先冻结交互并等待释放，再服务器清桌面、广播安装新 JSON、等待各端 ack 后重建。事务编号避免旧消息干扰，连接变化会中止流程；换库期间拒绝新连接，超时逻辑沿用源码。

聊天 UI 只发请求信号，GameSession 负责发送者身份、服务器清洗、历史和限流。当前历史上限 200 条、消息 500 字符/8 行、令牌容量 5、每秒补 1。聊天 RPC 当前沿用默认可靠通道，文档早期的独立通道建议不代表已实现。玩家名和消息按纯文本处理，避免 BBCode 注入。T 开关面板时不自动聚焦；CARD 模式点击输入框后关闭玩家键盘输入，空格/Q/T 进入文字，Enter 发送、Shift+Enter 换行，Esc 走暂停。暂停、模态界面、模式变化及离房须正确恢复焦点和输入；本地消息与历史快照不产生远端实时横幅。

Counter 的同一 StaticBody3D 使用三个 collision shape：`0` 底座、`1` 减号、`2` 加号，按 shape_idx 分流并以命中位置兜底；修改场景不能随意改变这一顺序。交互限制在 CARD 模式，查看器编辑即时提交，服务端检查查看者；加减通过 OwnerMux 串行处理。数值/步长/小数位要校验有限数、正步长和合法小数位，显示使用 printf 定点格式保留末尾零并归一负零。添加仅房主允许，删除沿用房主或当前 owner 校验，晚加入要补齐状态。

### 音效与脚本规范

音效统一经 `SfxManager.I.play(SfxManager.Snd.…)`，autoload 名为 `Sfx`；类单例访问兼容 `--check-only` 不注册 autoload 全局名的情况。3D 动作音复用占用/翻面广播和生成销毁生命周期在各端播放，2D 查看器反馈只在本端播放，不额外增加音效 RPC。成功反馈等状态实际落地后播放；普通按钮确认音按下即播。`sfx_no_confirm` 组用于排除自带成功音的按钮，避免双重反馈。维持 SPAWN 同帧合并、悬停去抖、随机音高、headless 播放记录和清场/离房静音门控；背景音乐进房约 10 秒后循环。

`project.godot` 把 `unsafe_property_access`、`unsafe_method_access`、`unsafe_cast`、`unsafe_call_argument`、`unsafe_void_return` 均设为错误（值 `2`）。跨类型节点、InputEvent、Variant 数据和 eval 代码使用明确类型并验证空值，沿用 `class_name`、类型注解、snake_case 文件名和现有缩进。修改脚本/场景后执行解析检查，不能以编辑器保存成功代替验证。

## Godot 4.7.2 CLI

本机可执行文件为 `/Applications/Godot 4.7.2.app/Contents/MacOS/Godot`，已核实版本 `4.7.2.stable.official.ed1daf0bf`。以下命令在项目根目录执行，其他机器先替换路径；需要新参数时先查本机 `--help`。

```bash
GODOT_BIN='/Applications/Godot 4.7.2.app/Contents/MacOS/Godot'
"$GODOT_BIN" --version
"$GODOT_BIN" --help
"$GODOT_BIN" --path . --editor
```

修改脚本或场景后，加载项目、扫描资源并检查错误；首次导入或资源有变化时可使用 `--import` 等待导入完成。检查日志中的 parse/script/load 错误，不能只看进程退出码。

```bash
"$GODOT_BIN" --headless --path . --editor --quit --no-header --log-file /private/tmp/hjgao_parse.log
"$GODOT_BIN" --headless --path . --import
"$GODOT_BIN" --headless --path . --check-only --script res://tests/chat_test.gd
"$GODOT_BIN" --headless --path . --script res://tests/chat_test.gd -- parser
```

`--check-only` 与 `--script` 配合，仅解析，不执行测试。测试角色属于 `OS.get_cmdline_user_args()`，放在 `--` 后。主场景在 headless 下自动开服务器，默认 `game.gd.PORT=7788`；生产自定义端口由 `OS.get_cmdline_args()` 读取 `--port=…`，沿用如下格式，避免把两类参数混用：

```bash
"$GODOT_BIN" --headless --path . --port=7777
```

联机回归优先用 Python 运行器，各脚本自带本机 Godot 路径及进程编排；迁移机器时核实运行器路径。按改动选择相关测试，涉及共用认证、锁、占用或生命周期时扩大到相关套件。

| 命令 | 主要覆盖 |
| --- | --- |
| `python3 tests/run_player_name_tests.py` | 昵称清洗、认证、花名册同步 |
| `python3 tests/run_deck_change_tests.py` | JSON 校验、换库、清场、正逆位解析和 UI 等已有回归 |
| `python3 tests/run_chat_tests.py` | 聊天清洗、收发、历史、通知、焦点与快捷键 |
| `python3 tests/run_counter_tests.py` | 计数器解析/格式化、拾取、占用、编辑、晚加入与清计数器 |
| `python3 tests/run_sfx_tests.py` | 音效记录、全端与本端反馈、批量合并 |

运行器执行 parser、host、client 等角色，部分包含 late_join；通过退出码和各角色 marker 验收。`tests/deck_test_game.gd` 复用主场景并抑制 headless 自动开房。ENet 使用 UDP，本地测试必须允许 localhost 监听与连接；工具说明中“TCP 端口”的措辞不准确。同一时间避免多个运行器争用端口，清理只针对本轮启动的进程。Python runner 已用 host.stdout 行迭代时，继续用同一文件对象排空，避免混用 communicate() 导致预读日志丢失。文档编辑只需核实引用与命令，无须为其运行所有游戏测试。

## godot-ai MCP 使用方法

### 前提与会话

本项目插件目录 `addons/godot_ai/`，配置为 `addons/godot_ai/plugin.cfg`，当前插件与服务器版本均为 `3.2.5`。Godot GUI 编辑器必须打开本项目且插件启用；headless 输出 `MCP | plugin disabled in headless mode` 属预期。`_mcp_game_helper` 提供运行中检查，不要在业务改动中移除。

新环境在 Godot 的 Project Settings > Plugins 启用 Godot AI，打开停靠面板配置支持的客户端并重新连接 MCP。本机文档中的启动方式为 `/opt/homebrew/bin/uvx --link-mode copy --from godot-ai==3.2.5 godot-ai attach --port 8000 --ws-port 9500`，完整客户端 JSON 见 `docs/godot-472-and-godot-ai-mcp.md`。这是工具连接端口，区别于游戏 ENet 端口；当前环境已配置时直接使用现有工具，无须重装或覆盖客户端配置。

先调用 `session_manage({"op":"list"})`，根据 project_path 确认目标项目，再 `session_activate({"session_id":"返回的 ID"})` 或在每次调用顶层传 session_id。会话 ID 随编辑器连接变化，不硬编码历史值。接着 `editor_manage({"op":"state"})` 确认 readiness、当前场景与播放状态。工具通常暴露为 `mcp__godot_ai__…`；以本轮实际工具 schema 为准，管理类采用 `{"op":"操作","params":{…},"session_id":"…"}`，session_id 放顶层。

### 常用调用

| 目的 | 工具及参数示例 |
| --- | --- |
| 编辑器状态与选中节点 | `editor_manage({"op":"state"})` / `{"op":"selection_get"}` |
| 打开目标场景 | `scene_open({"path":"res://Game.tscn"})` |
| 保存编辑器场景改动 | `scene_save({})` |
| 运行主场景 | `project_run({"mode":"main","autosave":false})` |
| 运行指定场景 | `project_run({"mode":"custom","scene":"res://目标.tscn","autosave":false})` |
| 停止游戏 | `project_manage({"op":"stop"})` |
| 运行时场景树 | `game_manage({"op":"get_scene_tree","params":{"root_path":"/root/Game","depth":10}})` |
| 运行时 UI | `game_manage({"op":"get_ui_elements","params":{"include_hidden":false,"max_depth":10}})` |
| 运行时单节点 | `game_manage({"op":"get_node_info","params":{"path":"/root/Game/CardDatabase"}})` |
| 键鼠与动作模拟 | `game_manage` 的 `input_key`、`input_mouse`、`input_action`；按下和释放配对，帧级时间线使用 `input_sequence` |
| 运行时 GDScript | `editor_manage({"op":"game_eval","params":{"code":"var game: GameSession = get_node(\"/root/Game\") as GameSession\nreturn game.session_active"}})` |
| 日志 | `logs_read({"source":"editor","count":50})` / source 为 `game` 或 `plugin` |
| 游戏画面 | `editor_screenshot({"source":"game","max_resolution":1280})` |
| 编辑器画面 | `editor_screenshot` 的 source 为 `viewport`（3D）、`viewport_2d`（2D）、`cinematic`（Camera3D） |
| 引擎 API 核实 | `api_manage({"op":"get_class","params":{"class_name":"Label3D","sections":["properties"]}})` |

编辑器节点路径以场景根命名，如 `/Game/...`；运行时路径为 `/root/Game/...`。打开场景后检查 `scene_open` 的 switched；若为 false，重新确认 state 后再写入。同一路径重复 open 默认保留内存改动，`force_reload=true` 会丢弃未保存场景，仅在明确以磁盘为准时使用。MCP 节点和属性编辑通常先改内存，需 `scene_save` 才落盘；文件脚本编辑后检查文件扫描/重载状态。外部编辑 .tscn 后要协调内存版本，避免随后 autosave 覆盖磁盘修改。

`project_run` 默认 autosave=true，会保存场景；只做验证时使用 false，任务要求保留场景修改时显式保存再验证。运行返回 `game_status`、helper_live、session_active 和 recent_errors；helper_live 或编辑器 game_capture_ready 就绪后再运行 game_manage、game_eval、game 截图。已在运行时重复 project_run 不切换场景，需先 stop 再启动。若启动卡在 debugger break，先读 editor 日志，stop、修复并重启。

日志需同时考虑 editor 与 game：启动前解析错误不会进入 game buffer。editor 返回 next_cursor，后续用 since_cursor；game 用返回的 run_id（请求字段 since_run_id）和 offset 跟踪同一次运行。干净的 game 日志若提示 editor_errors_count，仍需排查 editor。截图 stale_frame 时恢复游戏窗口焦点并重试，不能据旧帧断言布局。性能用 editor_manage 的 monitors_get，通信问题读 plugin 日志。

`batch_execute` 使用底层命令名，如 `{"commands":[{"command":"set_property","params":{…}}],"undo":true}`，按顺序执行，失败时默认回滚已完成的场景 undo 修改；文件写入等操作不能假设都可回滚。禁止嵌套 batch，不把 test_run、运行项目等延迟操作塞入 batch。复杂 UI 修改后要检查容器尺寸、遮挡、焦点、输入穿透和截图，随后显式保存及 CLI 解析。

`test_run` 自动发现 `res://tests/test_*.gd` 的 `test_*` 方法，可传 suite/test_name/exclude_test_name/verbose，整轮约 300 秒预算。本项目现有 `tests/chat_test.gd`、`tests/counter_test.gd` 等是按角色启动的脚本，文件名和入口不同，不能用 MCP test_run 替代 Python runner 并声称完整联机回归通过。游戏运行时长时间阻塞主线程会影响 MCP 会话，eval 应返回小量数据并避免无期限 await。

推荐开发验证顺序：相关源码修改 → CLI 解析/必要脚本 check-only → Python 相关回归 → 必要的 GUI/MCP 真实交互、截图及日志检查。停止本轮启动的游戏，保留用户编辑器；仅明确要求关闭编辑器时使用 editor_manage 的 quit。总结实际执行的检查和未验证事项。

## 文档索引与历史差异

| 文档 | 何时阅读 |
| --- | --- |
| `README.md` | 操作方式、功能总览与模块导航 |
| `docs/player-name-customization.md` | 认证、显示名、名册、连接清理 |
| `docs/in-room-chat-design.md` | 聊天输入优先级、历史、通知、服务端校验 |
| `docs/counter-design.md` | 计数器 shape 路由、占用、数值与清场范围 |
| `docs/sound-effects-design.md` | 音效触发、播放端、成功判定、去重与历史记录 |
| `docs/card-text-wrapping-and-centering.md` | 双套卡面排版、文本物理宽度与高度适配边界 |
| `docs/pile-card-orientation-design.md` | 正逆位数据模型、权限、出牌朝向和兼容；源码已有实现及随机操作扩展 |
| `docs/godot-472-and-godot-ai-mcp.md` | 本机 CLI、客户端配置、MCP 使用及故障排查 |
| `docs/computer-use.md` | 历史 Computer Use 说明；当前工具为 cua_repl 时按其实际文档执行，优先用 Godot MCP 完成编辑器和游戏操作 |

上述文档含设计草案和旧接口说明，避免照抄状态标签、早期 Sfx 调用方式、旧 eval 错误描述、TCP 措辞或正逆位朝向偏移验收。遇到差异时核对源码、当前工具 schema、本机 CLI 帮助与相关测试，并在任务交付中说明有影响的差异。

## 牌堆生命周期补充

暂停菜单“新建牌堆”允许所有已入房玩家请求服务器创建空堆，命名 extra_pile_N，位置在加入 Piles 前设置并复用计数器空位扫描。DeckViewerUI 的删除入口只在绑定堆的服务器实际栈为空时显示，待抽取区的本地移动不会改变判定。删除经 PileAccessor 转交 Pile，由服务器校验有效会话、全局锁、空栈和房主或当前 PILE_VIEW owner 权限，Spawner 同步销毁；PileAccessor 出树时回收 /root 查看器。清场/换库清理新增堆并重建标准桌面。相关文档：docs/pile-create-delete-plan.md，测试：python3 tests/run_pile_lifecycle_tests.py。当前计数器创建同样允许所有玩家，以上旧模块说明中的“仅房主添加”应以源码为准。

## 请求与服务器函数命名

直接包装同一服务器操作的请求入口使用同后缀 request_xxx / server_xxx，例如 request_delete_pile/server_delete_pile、request_delete_counter/server_delete_counter。服务端 RPC 使用 server_，调用点、字符串 RPC、测试和文档须一起更新，客户端与服务器使用一致代码版本。

命名配对只适用于语义对应的直接包装，修改前逐项检查参数、返回值、身份补充、权限判断及主机/客户端分支，不为了配对改掉已有的独立语义。OwnerMux 保留 request_own(purpose)：它为自己申请占用并补充 my_id，server_set_owner(purpose, new_owner) 设置显式 owner；保留 request_release()：它先检查自己是否为 owner，server_reset_owner() 则执行服务器重置。DeckChange._ack 保留本地阶段确认语义，主机直接移除自身等待项，客户端才调用 server_acknowledge。GameSession._request_player_roster/_request_chat_history 保留仅客户端请求的私有入口；各自的 server_ RPC 负责校验并回传数据，不机械要求本地入口改名。

UI 回调、服务器内部辅助方法、由占用变化触发的业务处理及 sync/receive 广播保持自身职责名称。新建纯请求包装可按 request_/server_ 配对；发现现有函数承担不同语义时，保留原名并记录原因，不增加无意义别名或空包装来满足形式配对。


## 可编辑名称与悬浮详情

牌堆/计数器的用户名称为 display_name（初值空字符串），唯一状态由 NameEditor 子组件维护，禁止改动 Node.name/RPC 路径。NameEditorUI 仅在修改按钮或回车时提交，关闭、失焦和理牌事务均不提交名称；64 字符上限、纯文本清洗、允许清空与重名。server_apply_name 检查有效会话、真实 sender、全局锁和对应 PILE_VIEW/COUNTER_VIEW owner；sync_name/name_result 使用固定服务器 authority，OwnerMux 递归切换父节点权限后必须恢复 NameEditor 为 peer 1。晚加入通过 request_sync_name/server_sync_name 取得状态，勿交给随 owner 切换的根 Synchronizer。

DetailViewer 是 Card/Pile/Counter 的共用 3D 悬浮绑定，内容由 Callable 提供；UICard 通过兼容入口使用同一个 CardDescriptionTooltip 渲染器。名称浮层只显示名称，空名隐藏独立 NameLabel 和浮层，牌数/计数值保留；卡牌正反面隐藏逻辑保留。物体查看器加入 object_viewer 组，浮层据此隐藏被模态遮挡的 3D 提示。牌堆需合并 body、底座和热点悬浮，销毁来源时安全回收。相关方案 docs/pile-counter-naming-plan.md，专项测试 python3 tests/run_name_editor_tests.py。

文本输入及模态界面切换必须通过 Util.clear_pending_move_input 清空缓冲事件并释放四个 move_* 动作，防止中文输入法吞掉 key-up 后卡键。焦点进入/退出、查看器销毁、玩家输入启停及 CARD/MOVE 切换都应覆盖，不能只把 velocity 置零；清理仅在切换时执行，保持后续真实移动输入有效。
