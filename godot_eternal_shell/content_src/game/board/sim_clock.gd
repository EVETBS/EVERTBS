extends RefCounted
class_name BoardSimClock
## Command layer uses wall-clock. Sim dt is wall time unless dilation is on (BOARD_AND_INPUT 6.1).
## Off: stutter frames still advance the full wall delta so the rate stays 1.
## On: spike frames clip, and scale can drop when enough units are fighting.

const TARGET_S := 1.0 / 60.0
const SPIKE_S := 0.050
const SIM_CAP_S := 1.0 / 30.0
const SCALE_MIN := 0.5
const HINT_BELOW := 0.98
const EMA_A := 0.035
const SCALE_LERP := 1.15
const DILATE_START := 1.0 / 24.0
const DILATE_FLOOR := 1.0 / 12.0
const FIGHT_MIN := 75

var ema_frame := TARGET_S
var scale := 1.0
var spiked := false


func step(wall_dt: float, fighting: int = 0, dilate_on: bool = false) -> Dictionary:
	spiked = wall_dt > SPIKE_S
	var clipped := minf(wall_dt, SIM_CAP_S) if dilate_on and spiked else wall_dt
	ema_frame = lerpf(ema_frame, wall_dt, EMA_A)
	var want := 1.0
	if dilate_on and fighting >= FIGHT_MIN and ema_frame > DILATE_START:
		var t := clampf((ema_frame - DILATE_START) / maxf(DILATE_FLOOR - DILATE_START, 0.001), 0.0, 1.0)
		want = lerpf(1.0, SCALE_MIN, t)
	if dilate_on:
		scale = clampf(lerpf(scale, want, clampf(wall_dt * SCALE_LERP, 0.0, 1.0)), SCALE_MIN, 1.0)
	else:
		scale = 1.0
	return {
		"sim_dt": clipped * scale,
		"scale": scale,
		"hint": dilate_on and scale < HINT_BELOW,
		"spike": spiked,
		"fighting": fighting,
	}
