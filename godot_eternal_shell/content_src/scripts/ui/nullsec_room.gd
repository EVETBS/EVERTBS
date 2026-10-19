extends Control
class_name NullsecRoomUI
## EVE战棋房间壳占位。完整自走棋房间 UI 见 nullsec_room_eveac_ref.gd.bak；主菜单本批不打开房间。

signal leave_requested
signal start_match_requested

var session: NullsecNetSession


func setup(net: NullsecNetSession) -> void:
	session = net


func refresh() -> void:
	pass
