extends Node2D

# The whole game lives in this scene.
# The squad stays near the bottom. Gates and lane dashes move downward,
# which looks like the squad is running forward.
# Every score change goes through scripts/lane_rules.gd.
#
# Each gate has a gray wall on the side facing the squad. The number on the
# wall is the hits left. Bullets are checked before the squad, so a wall that
# breaks as you arrive still lets the gate through.

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
const GATE_H := 64.0
# The wall sits on the squad's side of the gate. This is its height.
const WALL_H := 40.0
const BULLET_W := 8.0
const BULLET_H := 22.0

# Where new gates appear (just above the screen).
const SPAWN_Y := -80.0
# Anything that falls past this is removed.
const DESPAWN_Y := 1040.0

const DASH_GAP := 80.0

const COLOR_ADD := Color(0.22, 0.80, 0.48)
const COLOR_SUB := Color(0.95, 0.34, 0.34)
const COLOR_MUL := Color(1.0, 0.76, 0.22)
const COLOR_WALL := Color(0.55, 0.57, 0.64)
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
# Which gate pair along the road we will spawn next. 0 is the first pair.
var next_pair := 0
var dashes: Array[Polygon2D] = []


func _ready() -> void:
	# Start in the right lane, so the other gate is a real choice.
	squad.position = Vector2(LANE_MID + GATE_W * 0.5, SQUAD_Y)
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

	# Distance traveled is the clock. Spawns use that, not a random timer.
	distance_pixels += LaneRules.SCROLL_SPEED * delta
	_spawn_due()
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
	_spawn_volley()
	fire_wait = LaneRules.FIRE_EVERY_SECONDS


# Pixels a shape travels from the spawn line down to the squad.
func _spawn_lead() -> int:
	return int(SQUAD_Y - SPAWN_Y)


func _spawn_due() -> void:
	var reached := int(distance_pixels) + _spawn_lead()
	# A long frame can make two pairs due at once. Place the later one
	# higher up so the fixed gap between them stays put.
	while true:
		var road_distance := LaneRules.gate_pair_distance(next_pair)
		if road_distance > reached:
			return
		var y := SPAWN_Y - float(reached - road_distance)
		_spawn_gate_pair(y, road_distance)
		next_pair += 1


func _spawn_gate_pair(y: float, road_distance: int) -> void:
	var points := _points_at(road_distance)
	var pair: Dictionary = LaneRules.roll_pair(points)
	var left: Dictionary = pair["left"]
	var right: Dictionary = pair["right"]
	_spawn_gate(LANE_LEFT + GATE_W * 0.5, y, left, points)
	_spawn_gate(LANE_MID + GATE_W * 0.5, y, right, points)


func _spawn_gate(x: float, y: float, spec: Dictionary, points: int) -> void:
	var gate := Node2D.new()
	gate.name = "Gate"
	gate.position = Vector2(x, y)
	gate.set_meta("kind", "gate")
	gate.set_meta("op", int(spec["op"]))
	gate.set_meta("amount", int(spec["amount"]))
	gate.set_meta("hits", LaneRules.wall_hits_for_distance(points))
	# A gate only counts the first time the squad touches it.
	gate.set_meta("used", false)

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _rectangle(GATE_W, GATE_H)
	gate.add_child(body)

	var text := _make_label(26, Color.WHITE)
	text.name = "Text"
	gate.add_child(text)
	_place_label(text, GATE_W, GATE_H)

	# The wall hangs off the bottom of the gate, which is the side the squad meets first.
	var wall := Polygon2D.new()
	wall.name = "Wall"
	wall.color = COLOR_WALL
	wall.polygon = _rectangle(GATE_W, WALL_H)
	wall.position = _wall_offset()
	gate.add_child(wall)

	var hits_label := _make_label(22, Color(0.08, 0.09, 0.12))
	hits_label.name = "Hits"
	gate.add_child(hits_label)
	_place_label_at(hits_label, _wall_offset(), GATE_W, WALL_H)

	world.add_child(gate)
	_refresh_gate(gate)


func _wall_offset() -> Vector2:
	return Vector2(0, GATE_H * 0.5 + WALL_H * 0.5)


func _refresh_gate(gate: Node2D) -> void:
	var body := gate.get_node("Body") as Polygon2D
	var text := gate.get_node("Text") as Label
	var wall := gate.get_node("Wall") as Polygon2D
	var hits_label := gate.get_node("Hits") as Label
	var op := int(gate.get_meta("op"))
	var amount := int(gate.get_meta("amount"))
	var hits := int(gate.get_meta("hits"))
	body.color = _color_for_op(op)
	text.text = LaneRules.gate_label(op, amount)
	if hits <= 0:
		wall.visible = false
		hits_label.visible = false
	else:
		wall.visible = true
		hits_label.visible = true
		hits_label.text = str(hits)


func _color_for_op(op: int) -> Color:
	if op == LaneRules.Op.ADD:
		return COLOR_ADD
	if op == LaneRules.Op.MUL:
		return COLOR_MUL
	# Subtract and divide are both bad, so they share the red color.
	return COLOR_SUB


func _points_at(road_pixels: int) -> int:
	return int(float(road_pixels) / LaneRules.PIXELS_PER_DISTANCE)


# One row of bullets. The count and the damages come from lane_rules.gd.
# They are spread in a straight row, a bit wider than the squad, and fly up in parallel.
func _spawn_volley() -> void:
	var damages: Array = LaneRules.volley_damages(squad_count)
	var count := damages.size()
	var span := LaneRules.volley_span(count)
	for i in count:
		var offset := 0.0
		if count > 1:
			var step := span / float(count - 1)
			offset = -span * 0.5 + step * float(i)
		var damage := int(damages[i]) * LaneRules.BULLET_DAMAGE
		_spawn_bullet(offset, damage)


func _spawn_bullet(x_offset: float, damage: int) -> void:
	var width := _bullet_width(damage)
	var bullet := Node2D.new()
	bullet.name = "Bullet"
	# Start just in front of the squad, then fly straight up.
	bullet.position = squad.position + Vector2(x_offset, -(SQUAD_HALF.y + BULLET_H * 0.5))
	bullet.set_meta("kind", "bullet")
	bullet.set_meta("damage", damage)
	bullet.set_meta("half_w", width * 0.5)

	var body := Polygon2D.new()
	body.name = "Body"
	body.color = COLOR_BULLET
	body.polygon = _rectangle(width, BULLET_H)
	bullet.add_child(body)

	# Parent to World, not the squad, so the shot stays straight
	# when the squad slides sideways.
	world.add_child(bullet)


func _bullet_width(damage: int) -> float:
	# A merged bullet (more than one runner) is a little thicker, so you can see it.
	var extra := damage - LaneRules.BULLET_DAMAGE
	if extra < 0:
		extra = 0
	return BULLET_W + float(extra) * 4.0


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

	for bullet in bullets:
		var shot := bullet as Node2D
		if shot.is_queued_for_deletion():
			continue
		if _bullet_hits_wall(shot, gates):
			shot.queue_free()

	if game_over:
		return

	for gate in gates:
		var gate_node := gate as Node2D
		if _squad_reaches_gate(gate_node):
			_squad_enters_gate(gate_node)
			if game_over:
				return


func _bullet_hits_wall(shot: Node2D, gates: Array) -> bool:
	var bullet_half := Vector2(float(shot.get_meta("half_w")), BULLET_H * 0.5)
	var damage := int(shot.get_meta("damage"))
	for gate in gates:
		var gate_node := gate as Node2D
		if gate_node.is_queued_for_deletion():
			continue
		if int(gate_node.get_meta("hits")) <= 0:
			continue
		var wall_center := gate_node.position + _wall_offset()
		var wall_half := Vector2(GATE_W * 0.5, WALL_H * 0.5)
		if _boxes_overlap(shot.position, bullet_half, wall_center, wall_half):
			_damage_wall(gate_node, damage)
			return true
	return false


func _damage_wall(gate: Node2D, damage: int) -> void:
	var result: Dictionary = LaneRules.hit_wall(int(gate.get_meta("hits")), damage)
	gate.set_meta("hits", int(result["hits_remaining"]))
	_refresh_gate(gate)


func _squad_reaches_gate(gate: Node2D) -> bool:
	if bool(gate.get_meta("used")):
		return false

	# The wall hangs below the gate, so the whole shape is taller on that side.
	var center_y := gate.position.y + WALL_H * 0.5
	var half_h := (GATE_H + WALL_H) * 0.5
	if absf(squad.position.y - center_y) > SQUAD_HALF.y + half_h:
		return false

	# The squad's center picks the path. The shared middle edge belongs
	# to the right gate, so one point cannot count for both sides.
	var left := gate.position.x - GATE_W * 0.5
	var right := gate.position.x + GATE_W * 0.5
	return squad.position.x >= left and squad.position.x < right


func _squad_enters_gate(gate: Node2D) -> void:
	# Mark it used before applying, so the same overlap cannot score twice.
	gate.set_meta("used", true)
	var next := LaneRules.take_gate(
		squad_count,
		int(gate.get_meta("op")),
		int(gate.get_meta("amount")),
		int(gate.get_meta("hits"))
	)
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
	if squad_count >= 1000:
		font_size = 18
	elif squad_count >= 100:
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
	_place_label_at(label, Vector2.ZERO, width, height)


func _place_label_at(label: Label, center: Vector2, width: float, height: float) -> void:
	label.position = center - Vector2(width, height) * 0.5
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
