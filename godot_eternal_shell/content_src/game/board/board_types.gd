extends Object
class_name BoardTypes

enum CellKind { EMPTY, GATE, RESOURCE, STATION, SOV }
enum MovePhase { IDLE, PREP, INVULN, LANDING }
enum Relation { SELF, ALLY, HOSTILE, NEUTRAL }

const UNIT_Y := 1.6
## Visual hull bounding-sphere after the authored 2π×26/24 diameter (SHIPS.md).
const HULL_DIAMETER := (TAU * 26.0 / 24.0) * 0.55 * 1.5
const METERS_PER_CELL := 2000.0
const TRACKING_METERS_PER_CELL := 2000.0
## Movement mapping only. Missile damage keeps meters and does not use this.
const SPEED_METERS_PER_CELL := 750.0
const KIT_METERS_PER_CELL := 500.0
const MIN_SAME_CELL_FRAC := 0.25
const SECTOR_MIN_DEG := 8.0
const SECTOR_MAX_DEG := 120.0
const FIGURE8_CYCLE_K := 5.3
const INVULN_ALPHA := 0.62
const BUBBLE_BREATH_S := 1.2
const WORK_MAX := 1000.0
const BOX_DRAG_PX := 8.0

static func tonnage_weight(t: String) -> int:
	match t:
		"frigate":
			return 1
		"destroyer":
			return 2
		"cruiser":
			return 4
		"battlecruiser":
			return 7
		"battleship":
			return 14
		_:
			return 1

static func work_rate(t: String) -> float:
	match t:
		"frigate":
			return 100.0
		"destroyer":
			return 25.0
		"cruiser":
			return 17.5
		"battlecruiser":
			return 12.5
		"battleship":
			return 7.25
		_:
			return 25.0

static func relation_color(rel: String) -> Color:
	match rel:
		"self":
			return Color(0.25, 0.85, 0.35, 1.0)
		"ally":
			return Color(0.3, 0.55, 1.0, 1.0)
		"hostile":
			return Color(0.95, 0.25, 0.25, 1.0)
		_:
			return Color(1, 1, 1, 1)

static func align_prep_s(inertia: float, mass: float) -> float:
	var tau: float = inertia * mass / 1_000_000.0
	return -log(0.25) * tau

static func shorter_arc_steps(a: int, b: int, n: int) -> int:
	var d: int = absi(a - b)
	return mini(d, n - d)