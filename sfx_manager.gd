class_name SfxManager
extends Node

## 全局音效出口（设计文档 docs/sound-effects-design.md）。
## 所有声音经 Sfx.play() 播放：对象池轮转、悬停去抖、同帧合并、headless 下只记录不出声。

enum Snd { HOVER, CONFIRM, PICKUP_CARD, DROP_CARD, PICKUP_OBJECT, DROP_OBJECT,
	SHUFFLE_OK, PILE_IN, SPAWN, FLIP }

static var I: SfxManager   # 运行时单例引用：--check-only 不注册 autoload 全局名，调用方经类名访问

const SEMITONE := 1.0594630943592953  # 2^(1/12)，±1 半音随机音高的区间端点
const POOL_SIZE := 8
const HOVER_MIN_INTERVAL_MSEC := 50   # 悬停最小间隔，鼠标扫过按钮排/牌列时不机关枪
const HISTORY_MAX := 64
const GROUP_NO_CONFIRM := &"sfx_no_confirm"   # 加入此组的按钮按下不响确认音
const HOVER_VOLUME_DB := -6.0                 # 高频触发音比动作音弱一档（Q5）
const BGM_VOLUME_DB := -10.0                  # 背景音乐压在音效之下
const BGM_DELAY_SEC := 10.0                   # 进入房间后先静默片刻再起音乐

const _STREAMS: Dictionary[Snd, AudioStream] = {
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

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_hover_msec := 0
var _last_spawn_frame := -1   # Q10：SPAWN 同帧合并，批量抽牌只响一声
var _history: Array[String] = []      # 测试断言用：记录"枚举名|实际pitch"
var _headless := false
var _bgm: AudioStreamPlayer
var _bgm_delay := 0.0

func _ready() -> void:
	SfxManager.I = self
	_headless = DisplayServer.get_name() == "headless"
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_on_node_added)
	# autoload 的 _ready 晚于主场景入树：启动时已在树内的按钮（大厅/暂停菜单等）补挂钩子，
	# 否则 node_added 早在连接建立前就已发出，这些按钮永远收不到悬停/确认音
	_hook_buttons_under(get_tree().root)
	print("SFXDBG ready headless=", _headless, " streams=", _STREAMS.size(),
		" out_dev=", AudioServer.get_output_device(), " master_vol=", AudioServer.get_bus_volume_db(0))
	_bgm = AudioStreamPlayer.new()
	_bgm.stream = preload("res://sounds/平静的吉他.wav")
	_bgm.volume_db = BGM_VOLUME_DB
	add_child(_bgm)
	_bgm.finished.connect(_bgm.play)   # 播完即续，循环播放

func _process(delta: float) -> void:
	# BGM：session 激活后计时 10 秒起播；离开房间停止并重置，下次进房重新等 10 秒
	var game := get_node_or_null("/root/Game") as GameSession
	if game != null and game.session_active:
		if not _bgm.playing:
			_bgm_delay += delta
			if _bgm_delay >= BGM_DELAY_SEC:
				_bgm.play()
	elif _bgm.playing:
		_bgm.stop()
		_bgm_delay = 0.0

func play(snd: Snd) -> void:
	if snd == Snd.SPAWN:   # 同帧合并（合并发生在记录前，测试也只看到一条）
		var frame := Engine.get_process_frames()
		if _last_spawn_frame == frame:
			return
		_last_spawn_frame = frame
	var pitch := 1.0
	if _varies_pitch(snd):   # 除悬停/确认外全部 ±1 半音随机抖动（Q6/Q11）
		pitch = randf_range(1.0 / SEMITONE, SEMITONE)
	_history.append("%s|%.4f" % [Snd.keys()[snd], pitch])   # headless 也记录，环形裁剪
	if _history.size() > HISTORY_MAX:
		_history = _history.slice(_history.size() - HISTORY_MAX)
	if _headless: return
	if snd == Snd.HOVER:
		if Time.get_ticks_msec() - _last_hover_msec < HOVER_MIN_INTERVAL_MSEC: return
		_last_hover_msec = Time.get_ticks_msec()
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	player.stream = _STREAMS[snd]
	player.volume_db = HOVER_VOLUME_DB if snd == Snd.HOVER else 0.0
	player.pitch_scale = pitch
	player.play()
	print("SFXDBG play ", Snd.keys()[snd], " stream_ok=", player.stream != null, " playing=", player.playing)

func history_contains(tag: String) -> bool:
	return _history.any(func(e: String): return e.begins_with(tag))

func _varies_pitch(snd: Snd) -> bool:
	return snd != Snd.HOVER and snd != Snd.CONFIRM

# R1a/R6：自动为一切 BaseButton 挂悬停音与按下确认音（节点释放时连接自动断开）
func _hook_buttons_under(node: Node) -> void:
	for child in node.get_children():
		var button := child as BaseButton
		if button != null:
			_hook_button(button)
		var window := child as Window
		if window != null:
			_hook_window(window)
		_hook_buttons_under(child)

func _hook_button(button: BaseButton) -> void:
	# 用绑定自身的 Callable 做查重：node_added / 启动扫描 / 弹窗补扫多路挂钩幂等，不会重复出声
	var hover_cb := _on_button_hover.bind(button)
	if button.mouse_entered.is_connected(hover_cb):
		return
	button.mouse_entered.connect(hover_cb)
	button.pressed.connect(_on_button_pressed.bind(button))

func _on_button_hover(button: BaseButton) -> void:
	if not button.disabled:
		play(Snd.HOVER)

func _on_button_pressed(button: BaseButton) -> void:
	if not button.is_in_group(GROUP_NO_CONFIRM):   # 点击时检查（连接早于设组，见 5.5）
		play(Snd.CONFIRM)

# 二次确认窗（ConfirmationDialog/AcceptDialog 等 Window）的 OK/取消按钮是首次弹窗时
# 才惰性创建的，入树时还不存在；弹出时立即并延迟一帧各补扫一遍，覆盖任何创建时机
func _hook_window(window: Window) -> void:
	var popup_cb := _on_window_popup.bind(window)
	if window.about_to_popup.is_connected(popup_cb):
		return
	window.about_to_popup.connect(popup_cb)

func _on_window_popup(window: Window) -> void:
	_hook_buttons_under(window)
	_hook_buttons_under.call_deferred(window)

func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button != null:
		_hook_button(button)
		return
	var window := node as Window
	if window != null:
		_hook_window(window)
