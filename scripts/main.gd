extends Node2D

# The whole game lives in this scene.
# The squad stays near the bottom. Gates, enemies, and lane dashes move
# downward, which looks like the squad is running forward.
# Every score change goes through scripts/lane_rules.gd.

const LaneRules = preload("res://scripts/lane_rules.gd")

# Layout, in pixels. These match the shapes drawn in scenes/main.tscn.
# The lane is split into a left path and a right path at LANE_MID.
const VIEW_H := 960.0
const LANE_LEFT := 30.0
const LANE_RIGHT := 510.0
const LANE_MID := 270.0
const SQUAD_Y := 820.0

# Half the width and height of the squad arrow (the Body polygon).
const SQUAD_HALF := Vector2(34, 24)

const GATE_W := 240.0
const GATE_H := 96.0
const ENEMY_SIZE := 56.0
const BULLET_W := 8.0
const BULLET_H := 22.0

# Where new gates and enemies appear (just above the screen).
const SPAWN_Y := -80.0
# Anything that falls past this is removed.
const DESPAWN_Y := 1040.0

const DASH_GAP := 80.0

const COLOR_ADD := Color(0.22, 0.80, 0.48)
const COLOR_SUB := Color(0.95, 0.34, 0.34)
const COLOR_MUL := Color(1.0, 0.76, 0.22)
const COLOR_LOCKED := Color(0.32, 0.34, 0.42)
const COLOR_ENEMY := Color(0.96, 0.28, 0.40)
const COLOR_BULLET := Color(1.0, 0.96, 0.66)

# $ paths are node names in scenes/main.tscn.
@onready var squad: Node2D = $Squad
@onready var squad_label: Label = $Squad/CountLabel
@onready var score_label: Label = $HUD/ScoreLabel
@onready var game_over_layer: CanvasLayer = $GameOver
@onready var final_score_label: Label = $GameOver/FinalScore
@onready var world: Node2D = $World
@onready var background: Node2D = $Background

var squad_count := 0
var distance_pixels := 0.0
var game_over := false
var dragging := false
var fire_wait := 0.2
var spawn_gap := LaneRules.SPAWN_EVERY_SECONDS
var spawn_wait := 0.6
var dashes: Array[Polygon2D] = []


func _ready() -> void:
	squad.position = Vector2(LANE_MID, SQUAD_Y)
	game_over_layer.visible = false
	_build_lane_dashes()
	_set_squad_count(LaneRules.STARTING_SQUAD)
	_update_hud()


func _process(delta: float) -> void:
	# A finished run stays on the game-over screen until a key restarts it.
	if game_over:
		return

	_slide_squad(delta)
	_shoot(delta)
	_move_world(delta)
	_scroll_dashes(delta)
	_handle_collisions()

	if game_over:
		_update_hud()
		return

	_spawn_tick(delta)
	distance_pixels += LaneRules.SCROLL_SPEED * delta
	_update_hud()


# Keys and the mouse are read here, before the on-screen text can take them.
func _input(event: InputEvent) -> void:
	if game_over:
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and not key.echo:
				# reload_current_scene gives back an error number. A normal restart returns OK.
				var reload_error := get_tree().reload_current_scene()
				if reload_error != OK:
					push_error("Could not restart the run.")
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			dragging = mouse_button.pressed
	elif event is InputEventMouseMotion and dragging:
		var motion := event as InputEventMouseMotion
		_nudge_squad(motion.relative.x)
	elif event is InputEventScreenDrag:
		# Phones send this instead of a mouse drag.
		var drag := event as InputEventScreenDrag
		_nudge_squad(drag.relative.x)


func _steer_direction() -> float:
	var direction := 0.0
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	if left:
		direction -= 1.0
	if right:
		direction += 1.0
	return direction


func _slide_squad(delta: float) -> void:
	var direction := _steer_direction()
	if direction == 0.0:
		return
	squad.position.x += direction * LaneRules.SQUAD_SLIDE_SPEED * delta
	_clamp_squad_x()


func _nudge_squad(dx: float) -> void:
	squad.position.x += dx
	_clamp_squad_x()


func _clamp_squad_x() -> void:
	var min_x := LANE_LEFT + SQUAD_HALF.x
	var max_x := LANE_RIGHT - SQUAD_HALF.x
	if squad.position.x < min_x:
		squad.position.x = min_x
	elif squad.position.x > max_x:
		squad.position.x = max_x


func _shoot(delta: float) -> void:
	fire_wait -= delta
	if fire_wait > 0.0:
		return
	_spawn_bullet()
	fire_wait = LaneRules.FIRE_EVERY_SECONDS


func _spawn_tick(delta: float) -> void:
	spawn_wait -= delta
	if spawn_wait > 0.0:
		return

	if randf() < LaneRules.ENEMY_SPAWN_CHANCE:
		_spawn_enemy()
	else:
		_spawn_gate_pair()

	# The only difficulty change: spawns slowly come a bit faster.
	spawn_gap -= LaneRules.SPAWN_RAMP_STEP
	if spawn_gap < LaneRules.MIN_SPAWN_EVERY_SECONDS:
		spawn_gap = LaneRules.MIN_SPAWN_EVERY_SECONDS
	spawn_wait = spawn_gap + randf() * LaneRules.SPAWN_JITTER_SECONDS


func _spawn_gate_pair() -> void:
	# At most one side is locked, so there is always an open path.
	var lock_left := false
	var lock_right := false
	if randf() < LaneRules.LOCK_CHANCE:
		if randf() < 0.5:
			lock_left = true
		else:
			lock_right = true

	_spawn_gate(LANE_LEFT + GATE_W * 0.5, lock_left)
	_spawn_gate(LANE_MID + GATE_W * 0.5, lock_right)


func _roll_gate() -> Dictionary:
	var op := int(LaneRules.OP_DECK.pick_random())
	var amount := 2
	if op == LaneRules.Op.ADD:
		amount = int(LaneRules.ADD_AMOUNTS.pick_random())
	elif op == LaneRules.Op.SUB:
		amount = int(LaneRules.SUB_AMOUNTS.pick_random())
	else:
		amount = int(LaneRules.MUL_AMOUNTS.pick_random())
	return {"op": op, "amount": amount}


func _spawn_gate(x: float, locked: bool) -> void:
	var rolled := _roll_gate()
	var hits := 0
	if locked:
		hits = LaneRules.DEFAULT_LOCK_HITS

	var gate := Node2D.new()
	gate.name = "Gate"
	gate.position = Vector2(x, SPAWN_Y)
	gate.set_meta("kind", "gate")
	gate.set_meta("op", int(rolled["op"]))
	gate.set_meta("amount", int(rolled["amount"]))
	gate.set_meta("locked", locked)
	gate.set_meta("hits", hits)
	# A gate only counts the first time the squad touches it.
	gate.set_meta("used", false)

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _rectangle(GATE_W, GATE_H)
	gate.add_child(body)

	var text := _make_label(28, Color.WHITE)
	text.name = "Text"
	gate.add_child(text)
	_place_label(text, GATE_W, GATE_H)

	world.add_child(gate)
	_refresh_gate(gate)


func _refresh_gate(gate: Node2D) -> void:
	var body := gate.get_node("Body") as Polygon2D
	var text := gate.get_node("Text") as Label
	var op := int(gate.get_meta("op"))
	var amount := int(gate.get_meta("amount"))
	var locked := bool(gate.get_meta("locked"))
	var bonus := LaneRules.gate_label(op, amount)

	if locked:
		body.color = COLOR_LOCKED
		var hits := int(gate.get_meta("hits"))
		if hits == 1:
			text.text = "%s\n1 hit" % bonus
		else:
			text.text = "%s\n%d hits" % [bonus, hits]
	else:
		body.color = _color_for_op(op)
		text.text = bonus


func _color_for_op(op: int) -> Color:
	if op == LaneRules.Op.ADD:
		return COLOR_ADD
	if op == LaneRules.Op.SUB:
		return COLOR_SUB
	return COLOR_MUL


func _spawn_enemy() -> void:
	var hp := randi_range(LaneRules.ENEMY_HP_MIN, LaneRules.ENEMY_HP_MAX)
	var half := ENEMY_SIZE * 0.5
	var x := randf_range(LANE_LEFT + half, LANE_RIGHT - half)

	var enemy := Node2D.new()
	enemy.name = "Enemy"
	enemy.position = Vector2(x, SPAWN_Y)
	enemy.set_meta("kind", "enemy")
	enemy.set_meta("hp", hp)

	var body := Polygon2D.new()
	body.name = "Body"
	body.color = COLOR_ENEMY
	body.polygon = _rectangle(ENEMY_SIZE, ENEMY_SIZE)
	enemy.add_child(body)

	var text := _make_label(24, Color.WHITE)
	text.name = "Text"
	text.text = str(hp)
	enemy.add_child(text)
	_place_label(text, ENEMY_SIZE, ENEMY_SIZE)

	world.add_child(enemy)


func _spawn_bullet() -> void:
	var bullet := Node2D.new()
	bullet.name = "Bullet"
	# Start just in front of the squad, then fly up.
	bullet.position = squad.position + Vector2(0, -(SQUAD_HALF.y + BULLET_H * 0.5))
	bullet.set_meta("kind", "bullet")

	var body := Polygon2D.new()
	body.name = "Body"
	body.color = COLOR_BULLET
	body.polygon = _rectangle(BULLET_W, BULLET_H)
	bullet.add_child(body)

	# Parent to World, not the squad, so the shot stays straight
	# when the squad slides sideways.
	world.add_child(bullet)


func _move_world(delta: float) -> void:
	var fall := LaneRules.SCROLL_SPEED * delta
	var rise := LaneRules.BULLET_SPEED * delta
	for child in world.get_children():
		var actor := child as Node2D
		var kind := str(actor.get_meta("kind", ""))
		if kind == "bullet":
			actor.position.y -= rise
			if actor.position.y < SPAWN_Y - 40.0:
				actor.queue_free()
		else:
			actor.position.y += fall
			if actor.position.y > DESPAWN_Y:
				actor.queue_free()


func _handle_collisions() -> void:
	var bullets := _actors_of("bullet")
	var gates := _actors_of("gate")
	var enemies := _actors_of("enemy")

	for bullet in bullets:
		var shot := bullet as Node2D
		if shot.is_queued_for_deletion():
			continue
		if _bullet_hits_something(shot, gates, enemies):
			shot.queue_free()

	if game_over:
		return

	for gate in gates:
		var gate_node := gate as Node2D
		if _squad_reaches_gate(gate_node):
			_squad_enters_gate(gate_node)
			if game_over:
				return

	for enemy in enemies:
		var foe := enemy as Node2D
		if foe.is_queued_for_deletion():
			continue
		if _boxes_overlap(squad.position, SQUAD_HALF, foe.position, Vector2(ENEMY_SIZE, ENEMY_SIZE) * 0.5):
			_enemy_touches_squad(foe)
			if game_over:
				return


func _bullet_hits_something(shot: Node2D, gates: Array, enemies: Array) -> bool:
	var bullet_half := Vector2(BULLET_W, BULLET_H) * 0.5
	for gate in gates:
		var gate_node := gate as Node2D
		if gate_node.is_queued_for_deletion():
			continue
		# Open gates let bullets through. Only a locked gate can be shot.
		if not bool(gate_node.get_meta("locked")):
			continue
		if _boxes_overlap(shot.position, bullet_half, gate_node.position, Vector2(GATE_W, GATE_H) * 0.5):
			_bullet_hits_lock(gate_node)
			return true

	for enemy in enemies:
		var foe := enemy as Node2D
		if foe.is_queued_for_deletion():
			continue
		if _boxes_overlap(shot.position, bullet_half, foe.position, Vector2(ENEMY_SIZE, ENEMY_SIZE) * 0.5):
			_bullet_hits_enemy(foe)
			return true

	return false


func _bullet_hits_lock(gate: Node2D) -> void:
	var result: Dictionary = LaneRules.hit_lock(int(gate.get_meta("hits")))
	gate.set_meta("hits", int(result["hits_remaining"]))
	if bool(result["unlocked"]):
		gate.set_meta("locked", false)
	_refresh_gate(gate)


func _bullet_hits_enemy(enemy: Node2D) -> void:
	var result: Dictionary = LaneRules.damage_enemy(int(enemy.get_meta("hp")), LaneRules.BULLET_DAMAGE)
	var hp := int(result["hp"])
	enemy.set_meta("hp", hp)
	if bool(result["defeated"]):
		enemy.queue_free()
		return
	var text := enemy.get_node("Text") as Label
	text.text = str(hp)


func _squad_reaches_gate(gate: Node2D) -> bool:
	if bool(gate.get_meta("used")):
		return false

	var dy := absf(squad.position.y - gate.position.y)
	if dy > SQUAD_HALF.y + GATE_H * 0.5:
		return false

	# The squad's center picks the path. The shared middle edge belongs
	# to the right gate, so one point cannot count for both sides.
	var left := gate.position.x - GATE_W * 0.5
	var right := gate.position.x + GATE_W * 0.5
	return squad.position.x >= left and squad.position.x < right


func _squad_enters_gate(gate: Node2D) -> void:
	# Mark it used before applying, so the same overlap cannot score twice.
	# If the gate is still locked, apply_gate leaves the count unchanged.
	gate.set_meta("used", true)
	var next := LaneRules.apply_gate(
		squad_count,
		int(gate.get_meta("op")),
		int(gate.get_meta("amount")),
		bool(gate.get_meta("locked"))
	)
	_set_squad_count(next)


func _enemy_touches_squad(enemy: Node2D) -> void:
	enemy.queue_free()
	var next := LaneRules.enemy_contact(squad_count, LaneRules.ENEMY_CONTACT_LOSS)
	_set_squad_count(next)


func _set_squad_count(next: int) -> void:
	squad_count = next
	_update_squad_label()
	if LaneRules.is_game_over(squad_count):
		_show_game_over()


func _update_squad_label() -> void:
	squad_label.text = str(squad_count)
	# Shrink the digits a little once the number gets wide.
	var font_size := 34
	if squad_count >= 100:
		font_size = 22
	elif squad_count >= 10:
		font_size = 28
	squad_label.add_theme_font_size_override("font_size", font_size)


func _distance_points() -> int:
	return int(distance_pixels / LaneRules.PIXELS_PER_DISTANCE)


func _update_hud() -> void:
	score_label.text = "Distance %d" % _distance_points()


func _show_game_over() -> void:
	if game_over:
		return
	game_over = true
	final_score_label.text = "Distance %d" % _distance_points()
	game_over_layer.visible = true


func _actors_of(kind_name: String) -> Array:
	var found: Array = []
	for child in world.get_children():
		if child.is_queued_for_deletion():
			continue
		if str(child.get_meta("kind", "")) == kind_name:
			found.append(child)
	return found


func _boxes_overlap(a: Vector2, a_half: Vector2, b: Vector2, b_half: Vector2) -> bool:
	var gap_x := absf(a.x - b.x)
	var gap_y := absf(a.y - b.y)
	return gap_x <= a_half.x + b_half.x and gap_y <= a_half.y + b_half.y


func _rectangle(width: float, height: float) -> PackedVector2Array:
	var half_w := width * 0.5
	var half_h := height * 0.5
	return PackedVector2Array([
		Vector2(-half_w, -half_h),
		Vector2(half_w, -half_h),
		Vector2(half_w, half_h),
		Vector2(-half_w, half_h),
	])


func _make_label(font_size: int, font_color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.z_index = 1
	return label


func _place_label(label: Label, width: float, height: float) -> void:
	label.position = Vector2(-width * 0.5, -height * 0.5)
	label.size = Vector2(width, height)


func _build_lane_dashes() -> void:
	# Short marks on the center line. They scroll down so the lane feels like it is moving.
	var y := 0.0
	var dash_loop := VIEW_H + DASH_GAP
	while y < dash_loop:
		var dash := Polygon2D.new()
		dash.color = Color(1, 1, 1, 0.28)
		dash.polygon = _rectangle(6.0, 36.0)
		dash.position = Vector2(LANE_MID, y)
		background.add_child(dash)
		dashes.append(dash)
		y += DASH_GAP


func _scroll_dashes(delta: float) -> void:
	var dy := LaneRules.SCROLL_SPEED * delta
	var dash_loop := VIEW_H + DASH_GAP
	for dash in dashes:
		dash.position.y += dy
		if dash.position.y > dash_loop:
			dash.position.y -= dash_loop
