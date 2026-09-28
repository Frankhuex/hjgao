# Godot 4.7.2 与 Godot AI MCP 使用说明

本文记录本项目的 Godot 4.7.2 命令行用法和 Godot AI MCP 的常用操作。路径和命令以当前机器为准，其他机器需要先替换 Godot 可执行文件路径。

## Godot 4.7.2 CLI

### 可执行文件

当前机器上的 Godot 4.7.2 编辑器应用名为 `Godot 4.7.2.app`，实际可执行文件为：

```bash
/Applications/Godot\ 4.7.2.app/Contents/MacOS/Godot
```

在 shell 中建议始终给路径加引号：

```bash
'/Applications/Godot 4.7.2.app/Contents/MacOS/Godot' --version
```

期望输出包含：

```text
4.7.2.stable.official.ed1daf0bf
```

### 打开与检查项目

在项目根目录 `/Users/apple/Programming/Godot/hjgao` 下执行：

```bash
'/Applications/Godot 4.7.2.app/Contents/MacOS/Godot' --path . --editor
```

只加载项目、扫描资源并退出的解析检查：

```bash
'/Applications/Godot 4.7.2.app/Contents/MacOS/Godot' \
  --headless \
  --path . \
  --editor \
  --quit \
  --no-header \
  --log-file /private/tmp/hjgao_parse.log
```

这个命令适合在修改脚本或场景后快速确认 GDScript 语法、全局类名和场景资源引用。项目把多数 GDScript unsafe 警告当作错误，因此解析结果比普通编辑器保存更严格。

### 只检查脚本

`--check-only` 只做脚本解析，不执行测试逻辑：

```bash
'/Applications/Godot 4.7.2.app/Contents/MacOS/Godot' \
  --headless \
  --path . \
  --check-only \
  --script res://tests/chat_test.gd
```

当前常用脚本检查对象：

```bash
'/Applications/Godot 4.7.2.app/Contents/MacOS/Godot' \
  --headless --path . --check-only \
  --script res://tests/chat_test.gd

'/Applications/Godot 4.7.2.app/Contents/MacOS/Godot' \
  --headless --path . --check-only \
  --script res://tests/player_name_test.gd

'/Applications/Godot 4.7.2.app/Contents/MacOS/Godot' \
  --headless --path . --check-only \
  --script res://tests/deck_change_test.gd
```

Python 测试运行器本身可以用 `py_compile` 做静态语法检查：

```bash
python3 -m py_compile \
  tests/run_chat_tests.py \
  tests/run_player_name_tests.py \
  tests/run_deck_change_tests.py
```

该命令会生成 `tests/__pycache__`，检查完可以删除。

### 运行测试脚本

测试脚本使用 Godot 的用户参数区分角色。单个 parser 角色示例：

```bash
'/Applications/Godot 4.7.2.app/Contents/MacOS/Godot' \
  --headless \
  --path . \
  --script res://tests/chat_test.gd \
  -- parser
```

本项目推荐直接使用 Python 运行器，因为它们会按顺序启动主机、客户端和后加入客户端：

```bash
python3 tests/run_chat_tests.py
python3 tests/run_player_name_tests.py
python3 tests/run_deck_change_tests.py
```

这些联机测试会绑定本机 TCP 端口。执行环境必须允许 localhost ENet 监听和连接。测试前后应确认相关端口没有残留进程。

### 无头服务器

项目主场景在 headless 模式下会自动进入无头服务器流程。默认端口来自 `game.gd` 的 `PORT` 常量；也可以按项目当前解析方式传入端口：

```bash
'/Applications/Godot 4.7.2.app/Contents/MacOS/Godot' \
  --headless \
  --path . \
  --port=7777
```

如果需要传给 `OS.get_cmdline_user_args()` 的参数，应放在引擎参数分隔符 `--` 之后，例如现有测试的 `-- parser`。

## Godot AI MCP

### 启用前提

本项目已经启用 Godot AI 插件：

- 插件目录：`addons/godot_ai`
- 插件配置：`addons/godot_ai/plugin.cfg`
- 项目自动加载：`_mcp_game_helper` 指向 `addons/godot_ai/runtime/game_helper.gd`
- Godot 版本要求：4.5 以上，当前项目使用 4.7.2

Godot AI MCP 需要 GUI 编辑器保持打开。headless 模式下插件会显示 `MCP | plugin disabled in headless mode`，因此 headless CLI 适合解析和测试，不适合调用 MCP。

首次在其他环境启用时：

1. 用 Godot 4.7.2 打开本项目。
2. 在 `Project Settings > Plugins` 中启用 Godot AI。
3. 打开 Godot AI 停靠面板。
4. 选择 MCP 客户端并点击 Configure。
5. 如果 MCP 客户端已经运行，按提示重启客户端或重新连接。

当前 Codex 环境已经配置好该 MCP，可以直接调用 `godot_ai` 工具。

### 常用操作

| 目的 | MCP 工具 | 操作 |
| --- | --- | --- |
| 确认编辑器和当前场景 | `editor_manage` | `state` |
| 查看当前选中节点 | `editor_manage` | `selection_get` |
| 获取性能指标 | `editor_manage` | `monitors_get` |
| 运行项目 | `project_run` | `mode = main/current/custom` |
| 停止项目 | `project_manage` | `stop` |
| 查看运行中场景树 | `game_manage` | `get_scene_tree` |
| 查看运行中 UI | `game_manage` | `get_ui_elements` |
| 查看单个运行中节点 | `game_manage` | `get_node_info` |
| 模拟键盘、鼠标和动作 | `game_manage` | `input_key/input_mouse/input_action/input_sequence` |
| 读取编辑器、插件或游戏日志 | `logs_read` | `source = editor/plugin/game` |
| 截图编辑器或游戏画面 | `editor_screenshot` | `source = viewport/viewport_2d/cinematic/game` |
| 运行 GDScript 测试套件 | `test_run` | 按 suite 或 test name 过滤 |
| 在运行中游戏执行 GDScript | `editor_manage` | `game_eval` |
| 批量编辑当前场景 | `batch_execute` | 顺序执行底层编辑命令 |
| 退出编辑器 | `editor_manage` | `quit` |

大多数 MCP 调用可以省略 `session_id`，默认使用当前活动编辑器。多个 Godot 编辑器同时打开时，应使用对应 session，避免把命令发给错误项目。

### 推荐检查流程

修改代码后推荐按以下顺序：

1. 运行 Godot 4.7.2 headless editor 解析检查，确认无脚本错误。
2. 对新增或修改的测试脚本执行 `--check-only`。
3. 用 `project_run` 启动项目。
4. 用 `game_manage.get_scene_tree` 或 `get_ui_elements` 确认运行时节点。
5. 用 `editor_screenshot` 检查画面。
6. 用 `logs_read` 检查运行期错误。
7. 停止项目，再运行本地联机测试。

如果只是检查脚本语法，不需要启动 MCP。如果需要检查真实布局、焦点、鼠标模式或多人同步，优先使用 MCP 的运行中项目检查。

### 项目运行与运行中检查

启动主场景：

```json
{
  "mode": "main",
  "autosave": true
}
```

`project_run` 返回 `game_status`、`helper_live`、`session_active` 和启动期错误。只有 helper live 后，`game_manage` 和 game 截图才可靠。

查看 UI：

```json
{
  "root_path": "",
  "include_hidden": false,
  "max_depth": 10
}
```

`get_ui_elements` 会返回可见 Control 的路径、类型、文本、禁用状态和矩形。适合检查聊天面板、暂停菜单和通知区域是否重叠。

查看场景树：

```json
{
  "depth": 10,
  "root_path": ""
}
```

运行中节点路径使用 `/root/Game/...` 形式。`Game.tscn` 内的编辑器相对路径和运行时路径不同，检查节点时要区分。

### 日志读取

`logs_read` 有三个常用来源：

| 来源 | 适用内容 |
| --- | --- |
| `plugin` | MCP 插件通信和内部事件 |
| `editor` | 编辑器进程的 GDScript 错误、解析错误和 Debugger Errors |
| `game` | 运行中游戏的 stdout、stderr、push_error 和 push_warning |

编辑器日志使用 cursor 续读：

1. 第一次读取 `source = editor`。
2. 保存返回的 `next_cursor`。
3. 后续读取传 `since_cursor`。

游戏日志使用 `run_id` 和 `offset` 续读。启动前发生的解析错误不会进入 game 日志，需要读 editor 日志。

### 截图

常用截图来源：

- `viewport`：编辑器 3D 视口，需要当前场景有 Node3D。
- `viewport_2d`：编辑器 2D 视口。
- `cinematic`：通过当前场景的 Camera3D 渲染。
- `game`：运行中游戏画面。

游戏窗口最小化或失去焦点时可能返回 stale frame。遇到这种情况应先让游戏窗口获得焦点，再重试截图。

### 运行测试

`test_run` 会发现 `res://tests/` 下的 `test_*.gd` 并执行 `test_*` 方法。常用参数：

- `suite`：只运行某个测试套件。
- `test_name`：按测试名过滤。
- `exclude_test_name`：排除匹配项。
- `verbose`：输出每条测试结果。

整轮测试预算约 300 秒。单个测试长时间阻塞主线程可能影响 MCP 会话，联机和动画类测试更适合继续使用现有 Python 多进程运行器。

### 在运行中游戏执行 GDScript

`game_eval` 可以在运行中的游戏里执行 GDScript，并返回字典、数组等结果。示例用途：

- 主动创建房间。
- 打开聊天面板。
- 注入测试消息。
- 检查节点数量和 UI 状态。

当前项目把 unsafe 类型警告当作错误。编写 eval 代码时应使用明确类型，例如：

```gdscript
var game: GameSession = get_node("/root/Game") as GameSession
```

`game_eval` 的编译错误无法返回完整源码位置，通常需要读取编辑器 Output 或 Debugger Errors。运行中游戏不存在、helper 未连接或主循环未推进时，应先检查 `project_run` 的 `game_status`。

### 批量场景编辑

`batch_execute` 按顺序执行底层编辑命令，例如 `create_node`、`set_property`、`delete_node`、`attach_script`。默认在后续命令失败时回滚已成功的场景修改。

适合连续编辑：

1. 创建节点。
2. 设置父子和布局属性。
3. 绑定脚本。
4. 连接信号。

不适合执行 `test_run`、运行项目或嵌套批量命令。复杂 UI 布局优先手工或脚本生成 `.tscn` 后再用 MCP 截图检查。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| headless 输出 `MCP | plugin disabled in headless mode` | 属于预期行为，headless 下不能使用 Godot AI MCP |
| MCP 返回 `EDITOR_NOT_READY` | 确认 Godot 编辑器已打开、项目已加载、目标操作适用的场景已打开 |
| MCP 返回 `EVAL_GAME_NOT_READY` | 先用 `project_run` 启动游戏，并等待 helper live |
| 游戏截图返回 stale frame | 恢复游戏窗口焦点后重试 |
| `game_eval` 编译失败 | 读取 editor 日志，并为节点使用显式类型转换 |
| 解析检查报 unsafe 警告 | 按项目设置把警告当错误处理，补充显式类型或安全转换 |
| 测试无法创建 ENet host | 检查端口占用，并确认环境允许 localhost 监听 |
| 测试进程残留 | 停止对应测试进程，再更换端口或重新运行 |
| 编辑器日志没有启动错误 | 启动前错误需要看 editor source，game 日志从 helper 注册后开始 |

## 使用约定

- 修改脚本或场景后先跑 headless editor 解析检查。
- 涉及联机流程的测试使用项目自带 Python 运行器。
- MCP 修改场景前确认当前打开的是 `res://Game.tscn` 或目标场景。
- 只做临时内存验证时，`project_run` 可传 `autosave=false`。
- 需要保留场景修改时使用 `autosave=true`，并在修改后重新解析项目。
- 同一时间避免两个测试运行器使用相同端口。
- 不需要编辑器时用 `project_manage.stop` 停止游戏；只有明确要关闭编辑器时才调用 `quit`。
