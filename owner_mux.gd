class_name OwnerMux
extends Node

signal on_owner_change

@onready var _parent := get_parent()
var _owner := 0 #必须保留owner变量，因为authority没有0
var purpose := Const.Purpose.NIL


func is_owned() -> bool:
	return _owner != 0
	
func i_am_owner() -> bool:
	return _owner == Util.my_id(self) and is_multiplayer_authority()
	
func request_own(purpose: Const.Purpose) -> bool:
	if is_owned(): return false
	if Util.is_server(self): 
		server_set_owner(purpose, 1)
	else: 
		server_set_owner.rpc_id(1, purpose, Util.my_id(self))
	return true

func request_release() -> bool:
	if not i_am_owner(): return false
	if Util.is_server(self):
		server_reset_owner()
	else:
		server_reset_owner.rpc_id(1)
	return true

@rpc("any_peer", "call_remote", "reliable")
func server_set_owner(purpose: Const.Purpose, new_owner: int):
	if Util.not_server(self): return
	if is_owned():          return
	_set_owner.rpc(new_owner, purpose)

@rpc("any_peer", "call_remote", "reliable")
func server_reset_owner():
	if Util.not_server(self): return
	if not is_owned():          return
	_set_owner.rpc(0, Const.Purpose.NIL)
	
@rpc("any_peer", "call_local", "reliable")
func _set_owner(new_owner: int, _purpose: Const.Purpose):
	if new_owner == 0:
		_parent.set_multiplayer_authority(1)
	else:
		_parent.set_multiplayer_authority(new_owner)
	_owner = new_owner
	purpose = _purpose
	print("user: ", Util.my_id(self), " node: ", _parent.name, " owner: ", _owner, " purpose: ", Const.PURPOSE_STR[purpose])
	on_owner_change.emit() #发信号，新owner收到信号判断自己是新owner再统一升起
