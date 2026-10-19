extends RefCounted
class_name BoardKinds

## Mirrors EVERTBS BoardTypes cell / relation colors (preview-only).

enum CellKind { EMPTY, GATE, RESOURCE, STATION, SOV }

const WORK_MAX := 1000.0

static func relation_color(rel: String) -> Color:
	match rel:
		"self":
			return Color(0.25, 0.85, 0.35, 1.0)
		"ally":
			return Color(0.3, 0.55, 1.0, 1.0)
		"hostile":
			return Color(0.95, 0.25, 0.25, 1.0)
		_:
			return Color(0.95, 0.25, 0.25, 1.0)
