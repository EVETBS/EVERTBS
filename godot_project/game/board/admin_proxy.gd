extends Node
class_name BoardAdminProxy
## Content-side AdminBus gate. Uses shell Autoload when present; else pass-through.

func request(channel: String, payload: Dictionary) -> Dictionary:
	var bus = get_tree().root.get_node_or_null("AdminBus")
	if bus != null and bus.has_method("request"):
		return bus.request(channel, payload)
	return {"ok": true, "channel": channel, "payload": payload, "passthrough": true}
