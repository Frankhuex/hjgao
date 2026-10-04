# 卡牌类型索引与分类初始化牌堆计划

状态：已按确认方案实现，第 10 节记录最终实现与验证。日期：2026-10-04。用户已确认居中换行布局、名称初始化为类型名、显式 null 归为空类型，以及使用空字符串 UNTYPED 常量。用户已确认类型较多时允许布局超出桌面，与计数器重叠时保持固定布局；混合堆排序继续遵守 ordered_card_templates 原始全局顺序。当前无待确认的产品行为。

## 1. 目标与范围

卡牌模板增加可选 type，建立 type_to_ordered_card_names 索引，同时明确维护类型之间的顺序和每种类型内部的牌名顺序。缺失或空类型归入 CardTemplate.UNTYPED（空字符串）分组，显示名称为“未分类”。换卡组和一键清场重建时，按类型在桌中央创建多个递增牌堆，各牌 ID 恰好分配到一个堆。

首次开房也采用同一分类建堆辅助方法，使首次初始化、换卡组和清场一致。个人空牌堆继续按玩家创建；手工新增、取出到新牌堆、普通收牌与抽牌行为保留，玩家仍可把不同类型混入同一个堆。本需求不限制运行中的堆只能保存一种类型，也不新增运行时“按类型整理现有堆”按钮。原“一键清场”继续删除所有散牌及牌堆、重建个人空堆、保留计数器；菜单是否改文案不属于当前必需改动。

## 2. 已核实的源码与调用链

JSON 中的实际字段是 deck_template.ordered_card_templates，用户所述 order_card_templates 在本项目对应此数组；继续使用现有拼写，避免另建兼容别名。DeckJson.parse/validate 是本地预检、服务器换库校验及客户端认证加载的共同入口，成功前不替换活动 CardDatabase.deck_instance。

CardTemplate 当前保存 name/count/description，构造函数三个必需参数，to_dict 输出这些字段。DeckTemplate 保存 ordered_card_names、card_name_to_card_template、card_name_to_priority，由数组顺序建立牌名优先级。DeckInstance 保存牌 ID 到牌名及正反面、正逆位映射；未提供 ID 映射时，当前生成逻辑遍历模板字典，计划改为显式遍历 ordered_card_names，确保编号依据有明确顺序。显式 ID 映射不能假设 ID 大小或 JSON 字典遍历顺序与模板顺序一致。

| 入口 | 当前链路 | 本次落点 |
| --- | --- | --- |
| 首次开房 | start_server → init_deck_instance → 建立 ENet 与会话 → add_pile(get_all_IDs(), 公共牌堆) → 创建房主及个人空堆 | 用共用分类建堆辅助方法替换单公共堆生成，保留玩家创建步骤 |
| 更换卡组 | DeckChange.server_change → DeckJson.parse → serialize_to_json → 置全局锁 → 等待各端释放 → 清旧节点并等待离树 → install_change/各端加载并 ack → _rebuild_board → finish_change/解锁 | _rebuild_board 按新模板类型重建，保留事务时序 |
| 一键清场 | request_clear_table/server_clear_table → 置锁 → prepare_for_table_clear → reset_face_and_orientation → 清旧节点并等待离树 → _rebuild_board → 解锁 | _rebuild_board 按当前模板类型重建，继续重置面向 |
| 加入/晚加入 | 服务器 auth 发送 export_deck_instance → 客户端 DeckJson.parse → complete_auth → Spawner 同步当前物体 → Pile 请求当前栈、NameEditor 请求名称 | type 随模板快照传输，索引在本端重建；物体仍由服务器创建 |

当前 _rebuild_board 使用 get_all_IDs 后按 _card_id_less 排序：先比较全局牌名优先级，相同牌名再按数值 ID 递增，然后生成一个公共牌堆。当前 start_server 没有排序步骤，README 中“洗好的公共牌堆”描述与源码不符，本次文档更新应描述实际分类递增初始化。

当前缺省正反面为背面，正逆位为正位；更换卡组保留导入映射，一键清场统一重置正面/正位。分类建堆不能额外重置映射。当前桌面约 10×10 世界单位，Pile 底座约 1×1.8，布局要考虑底座、两侧热点与牌名，不宜只用牌面尺寸估算间距。

## 3. 数据模型与顺序规则

CardTemplate 新增 type: String，默认空字符串，在现有构造参数末尾加可选参数，保持 CardTemplate.new(name,count,description) 调用兼容。定义 const UNTYPED: String = ""，通过 CardTemplate.UNTYPED 引用。缺失、显式 null、空字符串以及去首尾空白后为空的值统一规范化为该常量；模板 type、ordered_types 元素、type_to_priority 与 type_to_ordered_card_names 的键都直接使用空字符串。空字符串键是合法且正常参与排序的类型，判断索引存在须用 has，禁止把空键当作没有分组而跳过。序列化统一输出规范 type 字符串，包括空类型的 "type": ""，不保留 null；旧输入允许省略。显式 type="untyped" 是普通非空类型，其显示名为 untyped，与空类型分别建堆。

DeckTemplate 增加以下派生索引，统一在构造/加载阶段从 ordered_card_names 及模板建立，之后不单独修改索引。派生索引不写入 JSON，由每端从相同模板重新计算。

| 字段 | 用途与顺序 |
| --- | --- |
| ordered_card_names | 保留原 JSON 数组全局牌名顺序，是现有全局排序的依据 |
| card_name_to_priority | 保留原全局牌名优先级，避免改变混合堆的现有升序/降序语义 |
| ordered_types: Array[String] | 有效类型首次出现在 JSON 数组中的顺序，空类型 "" 也按首次出现插入，不强制放最后 |
| type_to_ordered_card_names | 每个有效类型对应有序牌名数组，从原数组提取同类型子序列，每个模板名出现一次，不按 count 展开 |
| type_to_priority: Dictionary[String,int] | 类型到 ordered_types 序号的映射，显式保存跨类型比较依据 |

推荐逐条扫描 ordered_card_names：有效类型第一次出现时记录 ordered_types/type_to_priority，并初始化对应数组；随后把该牌名追加进对应数组。禁止按类型字符串字典序、ID 大小或导入对象键顺序确定类型次序。虽然字典存在迭代顺序，公共布局和任何跨类型遍历都显式使用 ordered_types。

GDScript 的索引值应保持实际 Array[String]；具体声明需适配本机 4.7.2 的嵌套类型支持。可采用 Dictionary[String,Array]，每项创建为 Array[String]，在方法边界明确转换/校验，避免在设计中直接承诺 Dictionary[String,Array[String]] 一定可以编译。访问函数返回明确的类型，遵守项目 unsafe_* 警告即错误的约束。

例：原数组依次为 A(type=怪物,count=2)、B(type=事件)、C(type=怪物)、D(无 type)、E(type=事件)。全局牌名顺序仍为 A/B/C/D/E；ordered_types 为 ["怪物", "事件", ""]；对应牌名数组分别为 A/C、B/E、D。因此分堆顺序为怪物堆、事件堆、未分类堆，各堆内部按这些子序列展开实际 ID。

两类顺序不能合并成一份扁平数组替换 ordered_card_names：原数组可以交错出现不同类型，全局原序与分类后拼接序各有明确用途。本轮分类初始化使用 ordered_types 和各类型子序列；普通混合堆现有升降序继续遵守原 JSON 的全局牌名顺序。

## 4. type 校验、空值与快照兼容

已确认：缺失、null、空字符串、仅空白归为空字符串类型；非空值去首尾空白、保留内部空格、区分大小写，不对非字符串调用 str 强制转型。null 直接规范化为空字符串；数字、布尔、数组、对象拒绝。建议 type 最大 64 字符，拒绝换行及控制字符，适配名称展示并避免无法区分的隐形类型；具体清洗规则由 CardTemplate 的共用方法负责，DeckJson.validate 使用同一规则，不能出现预检成功而加载器分组不同的情况。

现有 name 全局唯一规则保持：两个不同类型也不能拥有同名模板，避免修改 card_ID_to_card_name 语义。count、描述、总牌数、文件大小和显式 ID 校验沿用现有约束。CardTemplate.load_from_json 自身也检查 type，保证直接加载器调用不绕过新字段约束；不把本次扩展变成整个旧加载器重写。

CardTemplate.to_dict 输出规范 type；DeckTemplate.to_dict 继续按 ordered_card_names 输出 ordered_card_templates，不能按类型分组重排 JSON 数组。DeckInstance.serialize_to_json 自然携带 type，覆盖服务器换库的 canonical JSON 与认证快照。重新解析应得到相同 ordered_types 和 type_to_ordered_card_names。输出展开后的完整 JSON 仍受现有 1 MiB 限制，新增字段计入体积校验。

旧卡组所有模板无 type 时只有一个空字符串类型分组，形成一个中央完整递增堆，原 ID 与牌面状态不变。内置 deck_instances 本轮不猜测或批量补充类型，新增专项 fixture 展示类型格式。客户端和服务器须使用同一代码版本；本轮不扩展认证协议版本或增加独立类型 RPC。

## 5. 按类型展开牌 ID 与生成牌堆

在 CardDatabase 或 DeckInstance 提供类型明确的分组查询方法，输入为已安装 DeckInstance，输出是按 ordered_types 对应的 ID 栈。先遍历全部 card_ID_to_card_name，为每个牌名收集实际 ID，按数值递增排序；再按每类的 type_to_ordered_card_names 依次追加各牌名的 ID。每个类型栈从前端到后端递增，前端为堆顶。相同牌名有多张时仅按数值 ID 决定稳定次序，不重新编号，也不假设显式 ID 连续。

例如 A 的 ID 为 303、101，C 的 ID 为 9，怪物类栈应为 [101,303,9]；牌名子序列 A/C 优先于 ID 数值大小，不能把整个堆直接按 ID 排成 [9,101,303]。全部分组的 ID 并集等于活动卡组所有 ID，分组之间没有交叉，总数量等于模板 count 总和。

抽取共用服务器内部 _create_initial_type_piles 或职责相近的辅助方法。它按 ordered_types 生成完整分组堆，不创建空类型组；初始栈、位置、朝向及需要的初始显示名在入树前设置，复用 Pile.preready 与 MultiplayerSpawner_Piles。该内部辅助必须能够在 clear_table_in_progress=true 时执行，不能转调会拒绝全局锁的 request_add_pile/server_add_pile 或取出到新牌堆请求。

分类堆的网络节点名建议稳定且独立于用户类型文本：只有一个空类型时，该堆保留“公共牌堆”以兼容旧入口；其余采用 type_pile_1、type_pile_2 等序号。节点名不直接使用 type，避免斜杠、保留字符、超长文本及名称碰撞；type_pile_ 前缀与个人 pile<peer_id>、手工 extra_pile_N 分离。更新测试时不要依赖只有一个完整公共堆或第一个 child 一定代表全部牌。

分类堆不强制保存 pile_type 状态：类型属于卡牌模板，初始化分组仅是一种生成策略。后续可改名、混牌、删空堆和再次拆堆，不引入新的互斥用途或持续分类约束。

用户已确认名称初始化为类型名。使用 NameEditor 的服务器初始化路径，在入树前给它设置初始 display_name；空类型显示“未分类”。不借用 request_apply_name，因为初始化时没有 PILE_VIEW owner 且清场锁仍开着。名称初值继续由 NameEditor 单点保存，主机 _ready 渲染与客户端 request_sync_name 补齐生效，不能改 Node.name。名称以后可编辑，下一次重建按类型规则恢复默认初值。

## 6. 中央布局与确认事项

用户已确认按类型序号在世界 X/Z 平面居中排列，朝向统一为普通中央堆朝向、Y=0，单类位于原点。多个类从世界 X 负方向到正方向排列，超过一行后按 Z 方向换行；每行内部居中，整体行列关于桌中央居中，末行不足列数时也居中。推荐初始参数每行最多 4 堆，X 间距约 1.5、Z 间距约 2.0，实施阶段依据底座/热点和实际截图微调，不改牌堆物理尺寸。

布局只由服务器根据类型数量与序号计算，客户端不自行生成或随机摆放。计数器在清场/换库中保留，用户已确认采用确定的中央布局；若与玩家已放到中央的计数器重叠，保持重叠并允许手动移动，不把已有空位扫描加入类型顺序布局。本轮不移动计数器或个人物体来为分类堆腾位置。

| 事项 | 方案 | 状态或影响 |
| --- | --- | --- |
| 一行还是换行 | 居中排列，超过一行容量换行 | 已确认 |
| 默认可编辑名称 | 类型名，空类型显示“未分类” | 已确认，显示名可在查看器修改 |
| 空类型表示 | const UNTYPED = ""；缺失/null/空字符串/纯空白归为空类型 | 已确认，人工输入 "type": "" 直接归入同一组 |
| 类型很多时的空间边界 | 保持现有导入限制，按固定间距换行，允许向桌面外延伸 | 已确认，不新增类型数量上限，不丢弃任何分组 |
| 中央计数器重叠 | 保持固定居中布局，允许重叠 | 已确认，不自动避让或移动保留物体 |
| 混合堆升降序 | 遵守 ordered_card_templates 原始全局顺序 | 用户重申原数组已确定混合类型顺序，分类索引不替换全局优先级 |

类型顺序按首次出现、同类型牌名按子序列、缺失/null/空 type 归空字符串类型已确定。空间边界及计数器重叠已确认，混合堆升降序保留原数组全局顺序。本轮不因有限桌面空间擅自缩减当前允许的模板数或卡牌总数。

## 7. 全局锁、占用与同步顺序

更换卡组继续先校验全部 JSON 与规范化快照，再开启全局锁；各端释放交互并确认后，服务器删除旧节点，等待离树，广播安装带 type 的新模板并等待安装 ack，然后在锁内分类重建。分类堆所有初始数据和位置先准备，入树后由 Spawner 同步；最后沿用 finish_change 和 set_clear_table_busy(false)。禁止在分类堆尚未建齐时提前解锁或允许请求创建/抽取。

一键清场继续先置锁、关闭查看器并复用当前交互清理，再重置牌面/正逆位，删除并等待旧牌堆/散牌离树，在锁内创建分类堆与个人空堆，最后解锁。保持现有清场与换库的占用处理差异，核对当前释放链；本轮不借分类需求把清场改造成新的多端确认协议。

服务器建堆本身使用同步循环，无需逐堆 await，没有给每个新堆申请 OwnerMux。旧节点未离树前不得复用 type_pile_N 或公共牌堆路径。并发的新建/删除/取出到新堆请求仍受全局锁拒绝。新类型索引通过 DeckInstance 模板快照恢复，牌堆实际栈与名称通过现有请求补齐，不能据模板重新替晚加入者摆出初始堆而覆盖房间当前状态。

实现时在开启破坏性事务前准备分类数据并验证牌数守恒；所有有效类型均生成牌堆，类型数量仍受现有模板数及卡牌总数约束，布局允许超出桌面。类别很多时考虑生成性能及 SPAWN 同帧合并，不增加逐堆音效 RPC或逐堆等待网络确认。

## 8. 文件范围与实施顺序

| 文件 | 计划修改 |
| --- | --- |
| card_template.gd | type 属性、可选构造参数、空字符串 UNTYPED 常量、共用规范化/校验与 JSON 输出 |
| deck_template.gd | ordered_types、type_to_ordered_card_names、type_to_priority 的统一派生构建，保持原顺序输出 |
| deck_json.gd | type 格式/长度/控制字符/null 校验与具体错误反馈 |
| deck_instance.gd / card_database.gd | 自动编号显式遵守原模板顺序；按类型展开稳定 ID 栈查询 |
| game.gd | 共用中央分类建堆与布局，接入 start_server 和 _rebuild_board，保留个人堆和计数器规则 |
| pile.gd / name_editor.gd | 补充入树前初始名称支持，不绕过编辑时的权限校验 |
| Game.tscn | 清场确认文案更新为按类型重建，按需要标注类型归堆行为 |
| tests/ 新增专项及相关回归 | 顺序/兼容/快照/分类堆/锁/晚加入验证，替换多分类场景中的单堆假设 |
| README.md / AGENTS.md / 本文 | JSON type 用法、空类型规则、初始化行为、操作影响及真实验证记录 |

开发顺序：确认布局与字段边界 → type 校验和序列化 → 派生顺序索引 → 显式 ID 分组 → 共用分类初始化及名称/位置 → parser 与服务器/客户端/晚加入专项 → 现有回归和 MCP 界面检查 → 文档记录。保留默认内置卡组原样，无需引入第三方插件或新网络通道。

## 9. 验证计划

| 场景 | 验收要求 |
| --- | --- |
| 旧卡组无 type | 一个空字符串类型索引与中央完整递增堆，原 ID/count/描述保持 |
| 交错类型 A/X、B/Y、C/X、D/空、E/Y | 类型顺序 ["X", "Y", ""]，各子序列 A/C、B/E、D，原全局顺序不变 |
| 空类型首次在数组中间或开头 | 位于对应首次出现位置，不强制排序到最后 |
| count>1、显式非连续且乱序 ID | 先按类型内牌名序，再按同名数值 ID 升序；总牌数守恒 |
| type 缺失、空白、null、显式 untyped、大小写差异 | 空值合并为空字符串类型；大小写区分，显式字符串 untyped 属于独立普通类型 |
| 非字符串、超长、控制字符、不同类型同名牌 | 预检/服务器/认证解析一致拒绝，活动房间不变 |
| 模板/完整快照序列化再解析 | type 与两级顺序一致，既有 ID/正反面/正逆位往返一致 |
| 首次开房、更换卡组、一键清场 | 同一类型形成一个中央递增堆，类型布局顺序一致，个人空堆保留规则一致 |
| 换库与清场牌面差异 | 换库保留导入面向；清场全部正面/正位，不被分类辅助覆盖 |
| 持有查看/拖动占用时重建 | 旧对象及 /root 查看器清理，无重名路径冲突、旧权限写入或孤立占用 |
| 清场期间创建/删除/拆堆 | 服务器拒绝，分类重建结束才解锁，无半生成桌面 |
| 普通客户端和晚加入 | type 索引与服务器一致，恢复房间当前各堆栈/位置/名称，保留玩家后续混牌状态 |
| 不同类型数、末行不满、超量布局边界 | 单类原点，多类顺序确定、每行及整体居中；类型多时继续换行并允许超出桌面，保留计数器可与分类堆重叠 |
| 混合堆升降序、普通抽牌、取出到新堆 | 原 JSON 全局优先级继续有效，新字段不改变现有业务行为 |

实现阶段执行 Godot 4.7.2 项目解析和相关脚本 check-only，新增类型专项多进程测试，并运行 deck_change、player_name、pile_lifecycle、pile_extract、name_editor、counter、sfx 等受影响回归。旧无 type fixture 可保留“公共牌堆”兼容断言，多类型 fixture 必须按分组和牌数守恒检查，避免把所有测试改成只检查一个任意堆。GUI/MCP 检查中央布局、类型名、清场确认文案、按钮忙碌状态及 editor/game 日志。上述为原验证计划，实际执行记录见第 10 节。


## 10. 最终实现与验证记录

CardTemplate 增加可选 type 参数及 UNTYPED=""，DeckJson.validate 和直接 CardTemplate 加载共用 validate_type/normalize_type。缺失、null 和去首尾空白后为空的值归为空字符串，非空类型去首尾空白、保留内部空格及大小写，规范值最多 64 字符，拒绝内部换行与控制字符。to_dict 始终输出规范字符串 type，包括空字符串，序列化不输出派生索引。

DeckTemplate 派生 ordered_types、type_to_priority 和 type_to_ordered_card_names，字典值实际为 Array[String]；保留 ordered_card_names/card_name_to_priority 原始全局顺序。DeckInstance 自动编号显式遍历 ordered_card_names，get_ordered_card_IDs_by_type 从实际 ID 映射按同类牌名子序列展开，每种同名副本按数值 ID 排序。CardDatabase 转发分组查询，初始化不重新编号或修改牌面状态。

GameSession.start_server 与 _rebuild_board 共用 _create_initial_type_piles。DeckChange 在破坏性事务前从解析结果准备初始 ID 分组，清场在置全局锁前从当前卡组准备分组；沿原事务删除等待、安装 ack 和解锁链执行分类重建。每行 4 堆，间距 X=1.5/Z=2.0，各行与整体边界居中，末行单独居中，允许越出桌面及与保留计数器重叠。唯一空类型保留公共牌堆节点名，其他布局为 type_pile_N；个人空堆及手工/拆堆仍沿原路径与空名称默认。

Pile.preready/add_pile 增加兼容的可选初始显示名参数，转交 NameEditor.initialize_name 在入树前赋值；后者拒绝在树内调用，不使用编辑 RPC 或新增占用。服务器 _ready 显示初值，客户端与晚加入沿既有名称请求同步补齐。分类堆显示类型名，空类型显示“未分类”，之后可自由改名及混牌。清场确认文案同步改为按类型重建并正面/正位；README 更新 type 格式和真实初始化规则，AGENTS 修正原缺省正反面的历史描述。

新增 tests/fixtures/card_types.json、tests/card_type_test.gd、tests/run_card_type_tests.py。专项验证交错类型与两级索引、空字符串键、null/缺失/空白兼容、显式 untyped 独立类型、首尾空白规范化、非法类型/控制字符/长度边界、非连续乱序 ID 和自动编号、快照往返、1000 类型解析、中央换行及越界布局、默认无类型卡组、新开 typed 房间、查看器占用下清场/换库、客户端请求重建、个人堆与计数器保留、手工堆清理、名称/位置/栈与晚加入同步、换库保持面向和清场重置面向。测试通过 PARSER_OK/CLIENT_OK/HOST_OK/LATE_JOIN_OK，退出码 0，运行器额外拒绝任何 SCRIPT ERROR 日志。

Godot 4.7.2 项目解析和专项脚本 check-only 无脚本/场景解析错误；deck_change、player_name、pile_lifecycle、pile_extract、name_editor、counter、sfx 七套回归均通过。名称回归的初始公共堆断言从空名调整为“未分类”；私人/手工堆与计数器的空名规则保持。初次专项测试遇到测试中三元表达式返回未类型化数组的运行时错误，改用明确 assign 后整套重跑通过，不修改业务行为以迁就测试。

GUI/MCP 在 1473×647 窗口加载分类 fixture 并核对六个完整堆：X=[101,303,9]、Y=[205]、未分类=[401,402]、Z=[501]、untyped=[601]、W=[701]；第一行 X 坐标 -2.25/-0.75/0.75/2.25、Z=-1，第二行 X=-0.75/0.75、Z=1，Y 均为 0，锁已解除。截图确认 4+2 两行，空类型与字面 untyped 显示不同名称。测试游戏已停止，用户编辑器保留，autosave=false 未覆盖编辑器内存场景。

受限 CLI 仍存在本机证书、语言服务器关闭和全局编辑器设置保存错误；部分测试退出保留物体的一帧出现已有 peer 清空后的 Dragger/名册日志。GUI 编辑器曾因热重载缓存报告找不到新方法，独立 CLI、联机各角色与新启动的 GUI 游戏均实际加载执行新方法；一次 eval 缩进错误导致暂停，停止重启后用正确缩进验证通过。未修改第三方插件或为这些工具/历史清理日志扩大业务范围。1000 类型完成解析和越界坐标验证，未实际生成 1000 个 3D 堆进行性能压测；超长类型标签和更小窗口未逐一手工检查。
