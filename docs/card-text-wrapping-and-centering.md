# 卡面文字自动换行与居中设计

## 目标

卡牌名称超过卡面可用宽度时自动换到下一行；换行后的整个文本区域仍以卡面中心为对称中心。该需求只影响卡面显示，不改卡组 JSON、卡牌 ID、正反面状态、联机同步和拖拽逻辑。

当前项目有两套卡牌外观：桌面 3D 卡牌由 `Card.tscn` 与 `card.gd` 负责，牌堆查看界面由 `UICard.tscn` 与 `ui_card.gd` 负责。两处都从 `CardDatabase.get_card_name()` 取得同一段文本，因此应在两个场景中分别配置文本区域，脚本继续保持只写入 `text` 的职责。

## 现有架构

卡组数据从 JSON 进入 `DeckJson.parse()`，生成 `DeckInstance` 后由 `CardDatabase` 提供查询。`PileCardSpawner` 实例化 `Card.tscn` 生成桌面卡牌，`DeckViewerUI` 实例化 `UICard.tscn` 生成查看界面卡牌。`card.gd` 的 `_ready()` 把卡名写入 `Label3D`，`ui_card.gd` 的 `update_ui()` 把卡名写入普通 `Label`。

当前 3D 卡牌的卡面尺寸为 `Vector3(0.62, 0.001, 1.1)`，`Label3D` 位于 `Pivot` 的原点，已经对应卡面中心。普通 `UICard` 的最小尺寸为 `Vector2(100, 140)`，当前内部 `Label` 使用固定 40×23 的中心锚点，只能容纳很短的名称。

Godot 4.7.2 的 `Label3D` 支持 `width`、`autowrap_mode`、`horizontal_alignment`、`vertical_alignment` 和 `offset`。其中 `width` 是像素宽度，最终物理宽度由 `width * pixel_size` 得出。项目当前默认 `pixel_size = 0.005`，因此 `width = 100` 对应 0.5 个世界单位，比 0.62 的卡面宽度留出约 0.06 的两侧边距。

## 3D 卡牌方案

`Card.tscn` 的 `Pivot/Label3D` 保持现有位置和旋转，新增固定文本宽度和居中对齐：

```text
width = 100.0
autowrap_mode = 3
horizontal_alignment = 1
vertical_alignment = 1
```

`autowrap_mode = 3` 对应 `TextServer.AUTOWRAP_WORD_SMART`，适合当前卡名里可能出现的中文、英文、数字、符号和 Emoji。`horizontal_alignment = 1` 与 `vertical_alignment = 1` 都是居中对齐。`offset` 保持 `Vector2.ZERO`，节点本身已经在卡面中心。

这样处理后，短文本和长文本都围绕同一个节点原点对称分布。已用 Godot 4.7.2 验证：`width = 100`、`pixel_size = 0.005` 时，文本区域宽度约 0.5；启用居中对齐后，单行和多行文本的网格边界都相对原点左右、上下对称。

如果未来修改卡牌物理宽度，应同步调整：

```gdscript
const CARD_FACE_WIDTH := 0.62
const LABEL_PIXEL_SIZE := 0.005
const TEXT_MARGIN := 0.06
```

计算方式为 `label_width = (CARD_FACE_WIDTH - TEXT_MARGIN * 2.0) / LABEL_PIXEL_SIZE`。当前数值即 `(0.62 - 0.12) / 0.005 = 100`。把常量放在 `card.gd` 并在 `_ready()` 中赋值，可以避免场景尺寸和脚本配置漂移；如果卡牌尺寸长期固定，直接写在场景里更简单。

## 牌堆查看界面方案

`UICard.tscn` 的 `Label` 应从固定小锚点改为占满卡面内部区域，并保留少量边距：

```text
anchors_preset = 15
anchor_left = 0.0
anchor_top = 0.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 6.0
offset_top = 6.0
offset_right = -6.0
offset_bottom = -6.0
grow_horizontal = 2
grow_vertical = 2
autowrap_mode = 3
horizontal_alignment = 1
vertical_alignment = 1
```

这样普通 `Label` 的可用宽度来自整个卡面，文本超过约 88 像素时自动换行；文本块在水平和垂直方向都居中。卡面尺寸变化时，锚点会自动跟随，不需要按文本长度手写偏移。

也可以在 `UICard` 下加一层 `MarginContainer`，把 6 像素边距交给容器管理，`Label` 作为子节点填满容器。当前卡牌结构很简单，直接修改锚点和偏移即可，增加容器属于可选的结构整理。

## 高度边界

当前需求的核心是横向换行和整体居中。`DeckJson` 允许卡名最多 64 个字符，若 64 个字符都是宽字形，固定 25 号字体可能产生很多行，导致文本块在垂直方向超出卡面。此时文本仍会居中，但会越过卡面上下边缘。

若要求所有合法卡名都完整留在卡面内，需要在换行和居中之上增加高度适配。3D 卡牌可在写入文本后读取 `Label3D.generate_triangle_mesh().get_faces()` 的顶点范围，得到当前文本块的物理高度；超过卡面可用高度时按比例调低 `pixel_size`。这样可以保持像素断行结果不变，只整体缩小渲染尺寸，文本块继续居中。

牌堆查看界面可在 `update_ui()` 后按字号从 25 逐级降低，直到 `Label` 的最小高度不超过卡面可用高度；同时给一个最低字号，避免极端卡名缩到不可读。若达到最低字号仍放不下，可保持居中并裁剪，完整内容仍可通过现有卡牌说明提示查看。

首轮实现可以只做固定宽度和自动换行；高度适配应作为第二阶段，并在测试中明确验收口径。

## 边界情况

| 场景 | 预期结果 |
| --- | --- |
| 短卡名 | 单行显示，文本块中心与卡面中心重合 |
| 超宽卡名 | 到达文本区域宽度后换行，整体仍居中 |
| 包含空格的英文卡名 | 优先在词间换行 |
| 连续中文或无空格文本 | 由智能换行模式处理 |
| 包含手动换行符 | 保留手动分行，并继续参与自动换行 |
| 背面卡牌 | 文本为空，布局属性不影响现有翻面逻辑 |
| 牌堆查看拖拽预览 | 复制出的 `UICard` 带同样锚点和对齐配置 |
| 64 个宽字形卡名 | 先完成换行与居中；若要求不出卡面，启用高度适配 |

`AUTOWRAP_WORD_SMART` 能覆盖常规卡名。若未来明确要求无空格的超长英文标识也必须在任意字符处断行，可改为 `TextServer.AUTOWRAP_ARBITRARY`，代价是普通英文单词也可能被拆开。

## 修改范围

| 文件 | 计划修改 |
| --- | --- |
| `Card.tscn` | 设置 `Label3D.width`、自动换行和居中对齐 |
| `card.gd` | 可选：集中维护卡面宽度、边距和 `pixel_size` 常量 |
| `UICard.tscn` | 将 `Label` 改为全卡面锚点，设置自动换行和居中对齐 |
| `ui_card.gd` | 可选：第二阶段增加高度适配 |
| `CardDatabase`、`DeckJson`、联机 RPC | 不修改 |

## 测试与验收

准备一份测试卡组，包含短名称、中文长名称、英文词组、无空格长串、Emoji、手动换行符和 64 字符上限名称。分别在桌面 3D 卡牌和牌堆查看界面中检查。

3D 卡牌验收：超宽名称在约 0.5 世界单位文本宽度内换行；单行和多行文本的中心都位于卡面中心；翻面、拖拽、入牌堆和说明提示保持现有行为。

牌堆查看验收：超宽名称在卡内约 88 像素文本宽度内换行；卡牌被 `duplicate()` 成拖拽预览后仍保持同样布局；排序、翻面、拖动和确认取牌流程保持现有行为。

视觉测试建议覆盖默认窗口、较小窗口和牌堆横向滚动状态。若实现高度适配，另加 64 个宽字形名称用例，确认文本不越过卡面上下边缘，且低于最低字号时才允许裁剪或由说明提示承载完整内容。
