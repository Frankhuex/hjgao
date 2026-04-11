class_name OwnerMux
extends Node

signal on_owner_change

var _owner := 0 #必须保留owner变量，因为authority没有0
var purpose := Const.Purpose.NIL


func is_owned() -> bool:
	return _owner != 0
	
func i_am_owner() -> bool:
	return _owner == Util.my_id(self)
	
func request_own(purpose: Const.Purpose) -> bool:
	if is_owned(): return false
	_server_set_owner.rpc_id(1, purpose)
	return true

func request_release() -> bool:
	if not i_am_owner(): return false
	_server_reset_owner.rpc_id(1)
	return true

@rpc("any_peer", "call_remote", "reliable")
func _server_set_owner(purpose: Const.Purpose):
	if Util.not_server(self): return
	if is_owned():          return
	_set_owner.rpc(Util.sender_id(self), purpose)

@rpc("any_peer", "call_remote", "reliable")
func _server_reset_owner():
	if Util.not_server(self): return
	if not is_owned():          return
	_set_owner.rpc(0, Const.Purpose.NIL)
	
@rpc("any_peer", "call_local", "reliable")
func _set_owner(new_owner: int, _purpose: Const.Purpose):
	_owner = new_owner
	purpose = _purpose
	if new_owner == 0:
		set_multiplayer_authority(1)
	else:
		set_multiplayer_authority(new_owner)
	on_owner_change.emit() #发信号，新owner收到信号判断自己是新owner再统一升起
