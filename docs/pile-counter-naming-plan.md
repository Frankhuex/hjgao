# 牌堆与计数器命名实施计划

状态：已按用户授权实现，最终链路及验证记录见第 9 节。日期：2026-10-04。

## 1. 目标与已确认边界

牌堆、计数器新增初始为空的自定义名称。牌堆右键打开 DeckViewerUI 后，通过名称输入框旁的“修改”按钮或输入框回车立即提交；服务器校验并广播全部玩家。关闭查看器、确认取牌、取消理牌均不触发名称提交或回滚已生效名称。3D 悬浮详情复用散牌 description 浮层的显示体验。

用户已确认以下边界。

| 问题 | 确认方案 | 当前状态 |
| --- | --- | --- |
| 计数器编辑入口 | CounterViewerUI 同样增加输入框、修改按钮与回车提交 | 已确认 |
| 悬浮内容及 description 范围 | 只显示自定义名称，不新增 description，不附加牌数/计数值或堆内卡牌信息 | 已确认 |
| 空名称时的显示 | 隐藏独立名称标签与名称提示；既有牌数/计数值标签保留 | 已确认 |

其余设计采用以下具体约定：名称最多 64 个 Unicode 字符，单行纯文本，去除首尾空白，将换行、制表符等空白归一为普通空格；全部空白转换为 `""`，允许清空名称、允许重名。超长输入在本地提示并由服务器拒绝，不静默截断。自定义名称只作为房间内运行时物体状态；节点销毁后不保留，不写入卡组 JSON。一键清场/换库重建的牌堆初始化为空；保留下来的计数器保留名称。清计数器、删除物体、退出房间按原生命周期清理。

## 2. 当前源码依据

`Pile.preready()` 把“公共牌堆”、`pile<peer_id>`、`extra_pile_N` 等名称写入 Node.name，这些标识参与节点路径及 MultiplayerSpawner/RPC 寻址。Pile 的 Label3D 当前只显示牌数；Counter 的 ValueLabel 只显示格式化数值。用户可编辑字段必须独立，禁止修改 Node.name。

计数器参数当前从 CounterViewerUI 调用 Counter.request_apply_value 等入口，服务器验证 COUNTER_VIEW owner 后广播状态；牌堆正反面/正逆位从 DeckViewerUI 发信号，经 PileAccessor 校验占用再发请求，即时应用，独立于关闭时的理牌事务。新功能沿用这两类即时链路及占用约束。

现有 CardDescriptionTooltip 持有 CardDatabase 与 card_id，只能显示卡牌内容；它已经实现纯文本、智能换行、鼠标偏移、屏幕边缘避让、来源销毁检查和全局开关。Card、UICard 均使用该浮层，需保留背面不展示卡牌描述的既有规则。

OwnerMux._set_owner 对物体递归执行 set_multiplayer_authority，查看期间根节点权限属于查看者。新增广播若直接在物体根节点声明 authority RPC，服务器可能失去调用权限。方案必须明确区分操作占用与名称同步 authority，禁止假设两者始终一致。

## 3. 数据与组件划分

Pile 和 Counter 对外暴露 `display_name: String`，初值 `""`，通过 `is_empty()` 判断未命名；Node.name 继续保留网络标识。Card 继续从 CardDatabase 读取模板名称，不开放散牌改名，不改变卡组数据模型。

使用轻量共享组件 `NameEditor`（脚本 `name_editor.gd`），供 Pile/Counter 场景实例化，保存名称的唯一状态，并提供名称校验、请求、服务器应用、广播、晚加入快照和 `name_changed` 信号。物体根脚本的 display_name 作为只读访问接口转发组件值，避免根脚本与组件重复保存不同步的名称。具体类型与 GDScript 语法在实现时通过项目严格解析检查。

组件通过明确配置获得目标物体、OwnerMux 和需要的查看 purpose；使用类型明确的 Callable 或配置方法验证 PILE_VIEW/COUNTER_VIEW，不用任意属性反射，不要求两个物体改变继承关系。Pile/Counter 各保留 `request_apply_name` 业务入口，转交组件同后缀 `request_apply_name/server_apply_name`，避免 UI 持有 RPC 细节。共享组件不会接管牌堆栈、计数器数值或 OwnerMux。

NameEditor 在各端都固定 multiplayer authority 为 peer 1。父节点 OwnerMux 切换权限后，利用 on_owner_change 在每端重新固定该子节点及其子树权限；此连接在物体配置阶段建立，客户端发送名称请求前已完成恢复。组件只使用 reliable RPC；广播声明 authority、call_local，接收端防御性校验远端 sender 为 1。开发时重点验证主机与客户端占用时权限均保持一致，不改变现有其他节点权限。

## 4. 查看器交互与即时生效

DeckViewerUI 的顶部操作区之前新增 NameRow：名称标签、可横向扩展的 LineEdit、文案“修改”的 Button，以及简短状态提示。CounterViewerUI 在标题下加入同样的名称行。可抽取共享 `NameEditorUI` 控件处理输入、显式提交和回包显示；该控件只发提交信号，不管理网络或 owner。

pressed、text_submitted 连接固化在各自 tscn。按钮和回车进入同一提交方法，禁止绑定 text_changed、focus_exited 或查看器关闭自动提交。输入框失焦保留未提交草稿；关闭丢弃草稿，已经服务器确认的名字持续保留。清空输入并提交恢复未命名状态。输入中收到其他状态广播不覆盖草稿；自身名称提交成功时以服务器返回值更新输入框，即使输入框仍有焦点。

提交时本地先校验目标有效、当前仍为查看 owner、会话及全局锁，校验名称后发送请求。等待回包期间禁用重复提交，显示“修改中”；收到权威结果后显示“已修改”或失败原因。客户端发送请求不先改变 3D 名称，也不提前声称成功。名称未变化时反馈“名称未变化”，不广播重复状态。未提交草稿不随计数器数值刷新被覆盖。

新增输入框接入键盘焦点守卫：T/Q/空格输入按文字处理，Enter 只提交名称，Esc 沿现有暂停处理；DeckViewerUI 新增 is_editing_text，GameSession 现有仅检测 CounterViewerUI 的文本编辑判断扩展为两类查看器。打开、关闭、暂停、失去占用、断线和目标销毁时正确恢复玩家输入。新增按钮使用 Sfx 既有按钮钩子；回车与按钮反馈遵循一次提交一次音效，不新增网络音效 RPC。

## 5. 请求、校验与同步

链路为“名称编辑控件提交 → 查看器/Accessor 验证本地查看状态 → Pile/Counter.request_apply_name → NameEditor.request_apply_name → server_apply_name → sync_name 广播”。牌堆沿现有 Accessor 信号转发；计数器可沿现有参数直接请求根脚本。主机走同一服务器校验函数，remote sender 0 映射为 1。

服务端验证运行在服务器、会话有效、目标仍存在且未排队删除、桌面未锁定、请求者是当前已连接玩家（或本地主机）、OwnerMux owner 等于实际 sender 且 purpose 对应目标查看器，再校验字符串长度与单行清洗规则。房主编辑同样须获得查看占用，不额外绕过他人查看锁；伪造无占用请求、拖动用途请求、过期请求和非法名称均拒绝。

成功时更新服务器组件状态，以服务器 authority 的 `sync_name` reliable RPC 广播新值，包含主机本地应用并发出 name_changed。该广播只更新名称、查看器名称状态和悬浮显示；不修改卡牌顺序、待取出区、is_front/is_upright、计数值、步长、小数位及 owner，不释放查看器占用。

请求携带本地递增 request_id；成功或失败都对请求者回传处理结果，回包同样受服务器 authority 约束。成功广播负责全端状态，处理结果负责本地输入框确认和错误反馈，两者职责明确。UI 只处理当前实例和当前待提交编号，已关闭/销毁查看器忽略晚回包。服务器失败结果带当前权威名称；若目标已经消失则由既有销毁流程关闭查看器。回包不影响其他客户端。

晚加入：NameEditor 在客户端 ready 后请求 `server_sync_name`，服务端只向请求者回传当前名称；保留原牌堆栈/计数器参数同步协议，避免修改既有大批调用点。所有新生成物体默认空字符串。快照与实时修改沿同一可靠通道由服务器串行发送，避免初始空值或旧快照覆盖新名称。名称由独立状态广播维护，不加入随 owner 切换权限的根节点 Synchronizer。

## 6. 悬浮详情复用

在保留现有 CardDescriptionTooltip 节点路径、资源 UID 与 show_for(source, card_id) 兼容入口的基础上，将底层渲染扩展为通用纯文本入口 `show_text_for(source, text)`。卡牌兼容入口继续做 CardDatabase 与正面判断，再交给通用渲染；牌堆/计数器自行提供确认后的悬浮内容。浮层记录来源与内容类型，使 Q/暂停菜单开关重新启用时正确刷新对应物体，不局限于 card_id。

若共用悬浮绑定代码足够明显，可新增 `DetailViewer` 小组件：绑定输入来源、提供内容 Callable、监听内容变化、在来源销毁时隐藏；它只管显示生命周期，不承载名称 RPC。保留 Card/UICard 现有正反面逻辑，避免为了通用化全面改写其交互。

牌堆拾取来自根 body、BaseArea 以及底/随机热点，需要将这些来源归一到同一个 Pile，切换子区域不闪烁、不残留，也不吞掉原抽牌/收牌/拖动事件。计数器沿根 body hover 接入，同时保留加减按钮原有悬停音。显示受全局详情开关、鼠标可见、打牌模式与模态遮挡门控；打开查看器/暂停或拖动时隐藏旧提示，退出目标、删除、清场、断线都回收来源。

名称变化时，当前正在悬浮的物体立即刷新提示。非空名称时，Pile/Counter 独立 NameLabel 显示自定义名称，浮层只展示该名称；空名称时隐藏 NameLabel 及名称提示，不回退默认文案，不暴露 Node.name 的网络标识。现有牌数/计数值标签保留。NameLabel 设置明确的宽度、换行和字号，牌堆标签随堆高更新位置，计数器标签避开数值与加减按钮；名称显示不新增碰撞或改变拾取形状顺序。

## 7. 文件范围与实施顺序

| 文件 | 计划内容 |
| --- | --- |
| `name_editor.gd`、对应场景或场景子节点 | 独立服务器权限的共享名称状态、校验、RPC、快照与结果反馈 |
| `pile.gd` / `counter.gd`、`Pile.tscn` / `Counter.tscn` | 暴露 display_name、挂接组件、配置查看 purpose、接入悬浮及独立 NameLabel |
| `DeckViewerUI.tscn` / `deck_viewer_ui.gd`、`pile_accessor.gd` | 名称行与固化信号、显式即时提交、回包和焦点处理 |
| `CounterViewerUI.tscn` / `counter_viewer_ui.gd` | 加入对应名称行，避免参数刷新覆盖名称草稿 |
| `card_description_tooltip.gd` / 其场景 | 通用纯文本渲染与来源刷新，保留现有卡牌入口及资源引用 |
| 可选 `NameEditorUI` / `DetailViewer` 组件 | 抽取重复 UI 与 hover 生命周期，不扩大业务继承或 RPC 改名 |
| `game.gd` | 两类查看器文本焦点识别、共用详情开关/清理核实 |
| `tests/` | 名称校验、host/client/late_join、权限与 UI/悬浮回归 |
| `README.md` / `AGENTS.md` / 本计划 | 实现后记录操作、边界与最终差异 |

实施顺序：名称校验与服务器组件 → 同步和晚加入 → 名称编辑行与输入保护 → 通用浮层及物体绑定 → 相关 CLI/联机回归和 GUI/MCP 验证 → 更新文档。任何组件抽取以减少实际重复为准，避免新增空包装、修改第三方插件或全面重构现有物体。

## 8. 验证与验收

| 场景 | 预期 |
| --- | --- |
| 初始生成及清空名称 | display_name 为 `""`，Node.name/RPC 路径稳定；名称标签/名称提示隐藏，3D 牌数/数值仍正确 |
| 按“修改”或回车 | 不关闭查看器即可全端看到权威名称；按钮与回车走同一链路 |
| 输入失焦/关闭但未提交 | 不发名称请求，草稿被丢弃；已提交名称不回滚 |
| 理牌、待取出区移动、翻面/正逆位与改名交错 | 名称独立生效，不重载牌列、不重置牌序或改变卡牌状态 |
| 计数器修改值/步长/小数位 | 名称草稿不被覆盖，参数同步与名称同步互不改写 |
| 客户端作为查看 owner、房主本地查看、晚加入 | 名称广播始终来自 peer 1；各端一致、快照取得最终名称 |
| 未占用、他人占用、DRAG purpose、伪造直接广播 | 拒绝改名/广播；权威状态不变 |
| 清场锁、换库、断线、删除以及晚回包 | 拒绝过期操作，查看器和悬浮来源安全清理，无 freed 错误 |
| 中文/emoji/重名/空白/64 字符/超长/控制字符 | 统一清洗、允许清空与重名、超长拒绝、纯文本展示 |
| 悬浮各物体及牌堆不同拾取区 | 正确内容、稳定切换、边缘避让、Q 开关一致、模态下不残留 |
| 原卡牌正/背面与 UICard | 正面详情保持，背面内容隐藏，既有格式与开关兼容 |
| 键盘与按钮音效 | 输入 T/Q/空格无穿透；回车仅改名；重复按键无重复提交/音效 |

实现后先运行 Godot 4.7.2 编辑器解析与相关 --check-only，检查实际 parse/script/load 日志；再运行名称专项 host/client/late_join 测试及 pile_lifecycle、counter、必要的 deck_change/chat/sfx 回归。GUI/MCP 验证真实悬浮、输入焦点、按钮、窄窗口和销毁；角色测试不可由 MCP test_run 替代。实际检查记录见第 9 节。

## 9. 最终实现与验证记录

最终命名采用 NameEditor / name_editor.gd、NameEditorUI / NameEditorUI.tscn / name_editor_ui.gd，以及 DetailViewer / detail_viewer.gd，遵循用户提出的“名词 + 动词 er”形式。Pile/Counter 的 display_name 为只读接口，唯一名称状态存放在 NameEditor，Node.name 保持不变。3D NameLabel 空名称隐藏，牌数/计数值继续显示，悬浮只显示名称。

NameEditorUI 直接绑定目标 NameEditor 并提交请求，组件统一校验当前查看 purpose 和 owner；没有为根脚本/Accessor 再增加空请求包装。链路简化为“共用名称行 → NameEditor.request_apply_name/server_apply_name → sync_name 权威广播 + name_result 定向反馈”。请求序号由每个客户端的组件在查看器重新打开后继续递增，避免晚回包与新查看器请求混淆。主机和客户端均走同一服务器校验。

NameEditor 在 OwnerMux 的每次权限切换后恢复 server authority；名称变化不会释放查看占用。DetailViewer 用来源集合合并牌堆 body、BaseArea、底/随机热点的悬浮，统一提供内容 Callable。Card 也使用该组件；UICard 保留已有 show_for 兼容入口，共用同一个扩展后的 CardDescriptionTooltip 浮层。共享组件通过明确节点/类型校验读取会话与输入状态，避免引入 GameSession 与查看器之间新的强类型循环依赖。

名称只由按钮或回车提交，失焦与关闭不提交。名称行守卫 T/Q/空格，Esc 打开暂停并清理查看器；回车音效复用 Sfx，不增加音效 RPC。DeckViewerUI 名称行给现有暂停按钮预留空间，CounterViewerUI 保持原参数排版。

验证：Godot 4.7.2 编辑器加载及 name_editor_test.gd 的 check-only 无 parse/script/load 错误；python3 tests/run_name_editor_tests.py 覆盖 parser、host、client、late_join，通过名称清洗/64 字符边界、按钮/回车、清空、草稿、无权限/错误 purpose/锁定拒绝、权威身份、晚加入、参数独立、悬浮开关与销毁。pile_lifecycle、counter、deck_change、chat、sfx 联机回归通过。GUI/MCP 实测牌堆回车提交、计数器真实按钮点击、真实鼠标悬浮、输入焦点、Esc 暂停及名称保留，最新 GUI 运行无新增 editor 脚本错误。已停止测试游戏，保留用户编辑器。

运行器日志仍存在项目既有的断连后计数器读取无 peer 与动态权限切换期间 Synchronizer 的同步告警；本次名称专项无 SCRIPT ERROR/TEST FAILED。此前 GUI 编辑器在多文件新增期间缓存了未注册类的解析错误，完成类扫描与刷新后，最新启动及 CLI 检查均无新增编译错误。窄窗口的进一步视觉调整可按实际目标分辨率追加验收。

## 10. 中文输入法移动卡键修复

名称行与计数器参数输入框的焦点进入/退出和销毁均清理移动动作，沿用聊天窗的 flush_buffered_events + action_release 四个 move_* 的方式，统一到 Util.clear_pending_move_input。Player.set_input_enabled 与 CARD/MOVE 切换同时清理动作和速度，避免关闭查看器后重返移动模式继续漂移。专项回归模拟缺少 key-up 的动作状态，覆盖两类名称框、计数器数值/步长/小数位、关闭查看器及后续正常移动。此测试验证输入状态恢复，未自动化操作 macOS 原生中文输入法。
