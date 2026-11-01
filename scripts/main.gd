extends Node3D

# The 3D crowd run. The crowd stays in a blob and runs forward.
# The camera sits behind and above the bridge and does not slide sideways,
# so you always see the whole road.
#
# Drawing lots of soldiers one node at a time gets slow. Instead:
# - Bodies and heads are two MultiMeshes. One mesh, drawn many times.
# - We only draw VISIBLE_SOLDIERS of them. The number over the crowd is the real count.
# - Bullets come from a pool of BULLET_POOL slots. One volley draws at most
#   MAX_BULLETS_PER_VOLLEY streaks. Their damages add up to
#   soldiers x BULLET_DAMAGE, so a crowd of 100 still hits that hard.
#
# Rules and tuning numbers live in scripts/run_rules.gd.

const Rules = preload("res://scripts/run_rules.gd")

# Layout. The bridge runs along +Z. X is left and right. Y is up.
const ROAD_HALF := 3.7
const ROAD_WIDTH := 8.2
const RAIL_X := 4.35
const CAM_HEIGHT := 8.2
const CAM_BACK := 11.0
const CAM_LOOK := 6.5
const CAM_FOV := 56.0
const SOLDIER_Y := 0.4
const HEAD_Y := 0.95
const BULLET_Y := 0.7
const SPAWN_AHEAD := 80.0
const DESPAWN_BEHIND := 24.0
const SWERVE_PER_PIXEL := 0.016
const BULLET_SPEED := 32.0
const BULLET_RANGE := 26.0

const COLOR_BLUE := Color(0.18, 0.55, 1.0)
const COLOR_RED := Color(0.92, 0.18, 0.22)
const COLOR_GOOD := Color(0.2, 0.55, 1.0, 0.45)
const COLOR_BAD := Color(0.95, 0.16, 0.2, 0.45)
const COLOR_ROAD := Color(0.78, 0.82, 0.86)
const COLOR_TIRE := Color(0.08, 0.08, 0.1)
const COLOR_WATER := Color(0.2, 0.62, 0.95)
const COLOR_YELLOW := Color(1.0, 0.86, 0.15)

@onready var world: Node3D = $World
@onready var camera: Camera3D = $Camera3D
@onready var distance_label: Label = $HUD/DistanceLabel
@onready var game_over_layer: CanvasLayer = $GameOver

var soldiers := 0
var crowd_x := 0.6
var crowd_z := 0.0
var last_z := 0.0
var game_over := false
var dragging := false
var drag_anchor_x := 0.0
var drag_anchor_crowd := 0.0
var fire_wait := 0.2
var next_chunk := 0

var body_mesh: MultiMeshInstance3D
var head_mesh: MultiMeshInstance3D
var bullet_mesh: MultiMeshInstance3D
var count_label: Label3D
var crowd_root: Node3D
var water: MeshInstance3D
var chunks: Node3D
var popups: Array = []

var bullet_x: Array = []
var bullet_z: Array = []
var bullet_damage: Array = []
var bullet_alive: Array = []

var body_multimesh: MultiMesh
var head_multimesh: MultiMesh
var bullet_multimesh: MultiMesh
var blue_body: CapsuleMesh
var blue_head: SphereMesh
var red_body: CapsuleMesh
var red_head: SphereMesh


func _ready() -> void:
	_build_look()
	_build_water()
	_build_crowd()
	_build_bullet_pool()
	chunks = Node3D.new()
	chunks.name = "Chunks"
	world.add_child(chunks)
	_set_soldiers(Rules.STARTING_SOLDIERS)
	game_over_layer.visible = false
	_spawn_chunks()
	_place_camera()
	_refresh_crowd_visual()


func _process(delta: float) -> void:
	if game_over:
		_float_popups(delta)
		return

	_steer(delta)
	last_z = crowd_z
	crowd_z += Rules.RUN_SPEED * delta
	_clamp_crowd()
	_spawn_chunks()
	_fire(delta)
	_move_bullets(delta)
	_bullets_hit()
	_crowd_hits()
	_float_popups(delta)
	_place_camera()
	_refresh_crowd_visual()
	distance_label.text = "Distance %d" % int(crowd_z)


func _input(event: InputEvent) -> void:
	if game_over:
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and not key.echo:
				var reload_error := get_tree().reload_current_scene()
				if reload_error != OK:
					push_error("Could not restart the run.")
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			dragging = button.pressed
			if button.pressed:
				# Remember where the finger went down, and where the crowd was.
				# The drag then moves the crowd by the same slide.
				drag_anchor_x = button.position.x
				drag_anchor_crowd = crowd_x
	elif event is InputEventMouseMotion and dragging:
		var motion := event as InputEventMouseMotion
		crowd_x = drag_anchor_crowd + (motion.position.x - drag_anchor_x) * SWERVE_PER_PIXEL
		_clamp_crowd()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		dragging = touch.pressed
		if touch.pressed:
			drag_anchor_x = touch.position.x
			drag_anchor_crowd = crowd_x
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		crowd_x = drag_anchor_crowd + (drag.position.x - drag_anchor_x) * SWERVE_PER_PIXEL
		_clamp_crowd()


func _steer(delta: float) -> void:
	var direction := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction += 1.0
	if direction != 0.0:
		crowd_x += direction * Rules.STRAFE_SPEED * delta


func _clamp_crowd() -> void:
	var limit := ROAD_HALF - _blob_radius() - 0.2
	if limit < 0.15:
		limit = 0.15
	if crowd_x < -limit:
		crowd_x = -limit
	elif crowd_x > limit:
		crowd_x = limit


func _blob_radius() -> float:
	var shown := soldiers
	if shown > Rules.VISIBLE_SOLDIERS:
		shown = Rules.VISIBLE_SOLDIERS
	if shown <= 1:
		return 0.35
	var ring := 1
	var filled := 1
	while filled < shown:
		filled += 6 * ring
		ring += 1
	return Rules.FORMATION_GAP * float(ring - 1) + 0.25


func _fire(delta: float) -> void:
	if soldiers <= 0:
		return
	fire_wait -= delta
	if fire_wait > 0.0:
		return
	fire_wait = Rules.FIRE_EVERY_SECONDS
	var damages: Array = Rules.volley_damages(soldiers)
	var spots: Array = Rules.formation_offsets(damages.size())
	var index := 0
	while index < damages.size():
		var spot: Vector2 = spots[index]
		_launch_bullet(crowd_x + spot.x, crowd_z + spot.y, int(damages[index]))
		index += 1


func _launch_bullet(x: float, z: float, damage: int) -> void:
	var slot := 0
	while slot < bullet_alive.size():
		if not bullet_alive[slot]:
			bullet_alive[slot] = true
			bullet_x[slot] = x
			bullet_z[slot] = z
			bullet_damage[slot] = damage
			return
		slot += 1
	# The pool is sized so this should not happen. If it does, drop the streak
	# rather than creating a new node.


func _move_bullets(delta: float) -> void:
	var step := BULLET_SPEED * delta
	var slot := 0
	while slot < bullet_alive.size():
		if bullet_alive[slot]:
			bullet_z[slot] = float(bullet_z[slot]) + step
			if float(bullet_z[slot]) > crowd_z + BULLET_RANGE:
				bullet_alive[slot] = false
		slot += 1
	_paint_bullets()


func _bullets_hit() -> void:
	for chunk in chunks.get_children():
		if game_over:
			return
		for child in chunk.get_children():
			var kind := str(child.get_meta("kind", ""))
			if kind == "tire":
				_bullets_vs_tire(child)
			elif kind == "enemies":
				_bullets_vs_enemies(child)


func _bullets_vs_tire(tire: Node3D) -> void:
	if int(tire.get_meta("hp")) <= 0:
		return
	var center: Vector3 = tire.global_position
	var half_x := float(tire.get_meta("half_x"))
	var half_z := float(tire.get_meta("half_z"))
	var slot := 0
	while slot < bullet_alive.size():
		if bullet_alive[slot] and int(tire.get_meta("hp")) > 0:
			var dx := absf(float(bullet_x[slot]) - center.x)
			var dz := absf(float(bullet_z[slot]) - center.z)
			if dx <= half_x + 0.25 and dz <= half_z + 0.35:
				var hp := int(tire.get_meta("hp")) - int(bullet_damage[slot])
				if hp < 0:
					hp = 0
				tire.set_meta("hp", hp)
				bullet_alive[slot] = false
				_refresh_tire_label(tire)
				if hp == 0:
					tire.visible = false
		slot += 1


func _bullets_vs_enemies(group: Node3D) -> void:
	var hps: Array = group.get_meta("hps")
	var spots: Array = group.get_meta("spots")
	var changed := false
	var slot := 0
	while slot < bullet_alive.size():
		if bullet_alive[slot]:
			var left := int(bullet_damage[slot])
			var index := 0
			while index < hps.size() and left > 0:
				var hp := int(hps[index])
				if hp > 0:
					var spot: Vector3 = group.global_position + spots[index]
					var dx := absf(float(bullet_x[slot]) - spot.x)
					var dz := absf(float(bullet_z[slot]) - spot.z)
					if dx <= 0.55 and dz <= 0.55:
						if left >= hp:
							left -= hp
							hps[index] = 0
						else:
							hps[index] = hp - left
							left = 0
						changed = true
				index += 1
			if left != int(bullet_damage[slot]):
				bullet_damage[slot] = left
				if left <= 0:
					bullet_alive[slot] = false
		slot += 1
	if changed:
		group.set_meta("hps", hps)
		_refresh_enemy_group(group)


func _crowd_hits() -> void:
	for chunk in chunks.get_children():
		if game_over:
			return
		for child in chunk.get_children():
			if game_over:
				return
			var kind := str(child.get_meta("kind", ""))
			if kind == "gate":
				_maybe_take_gate(child)
			elif kind == "tire":
				_maybe_hit_tire(child)
			elif kind == "enemies":
				_maybe_hit_enemies(child)


func _maybe_take_gate(gate: Node3D) -> void:
	if bool(gate.get_meta("used")):
		return
	var gate_z := gate.global_position.z
	# The crowd center picks the side. The right gate owns the exact middle.
	if last_z >= gate_z or crowd_z < gate_z:
		return
	var side := str(gate.get_meta("side"))
	var on_right := crowd_x >= 0.0
	if side == "right" and not on_right:
		return
	if side == "left" and on_right:
		return
	gate.set_meta("used", true)
	var before := soldiers
	var op := int(gate.get_meta("op"))
	var amount := int(gate.get_meta("amount"))
	_set_soldiers(Rules.apply_gate(soldiers, op, amount))
	_popup(Rules.gate_label(op, amount), Rules.is_good_op(op), gate.global_position)
	if soldiers == before and Rules.is_bad_op(op):
		pass


func _maybe_hit_tire(tire: Node3D) -> void:
	if bool(tire.get_meta("resolved")) or int(tire.get_meta("hp")) <= 0:
		return
	if not _crowd_overlaps(tire.global_position, float(tire.get_meta("half_x")), float(tire.get_meta("half_z"))):
		return
	var result: Dictionary = Rules.tire_crash(soldiers, int(tire.get_meta("hp")))
	var lost := soldiers - int(result["soldiers"])
	tire.set_meta("hp", 0)
	tire.set_meta("resolved", true)
	tire.visible = false
	_set_soldiers(int(result["soldiers"]))
	if lost > 0:
		_popup("-%d" % lost, false, tire.global_position)


func _maybe_hit_enemies(group: Node3D) -> void:
	if bool(group.get_meta("resolved")):
		return
	if not _crowd_overlaps(group.global_position, 1.4, 1.4):
		return
	var living := _living_enemies(group)
	if living <= 0:
		group.set_meta("resolved", true)
		return
	var result: Dictionary = Rules.enemy_trade(soldiers, living)
	var lost := soldiers - int(result["soldiers"])
	_remove_enemies(group, lost)
	group.set_meta("resolved", true)
	_set_soldiers(int(result["soldiers"]))
	if lost > 0:
		_popup("-%d" % lost, false, group.global_position)


func _crowd_overlaps(center: Vector3, half_x: float, half_z: float) -> bool:
	var radius := _blob_radius()
	var dx := absf(crowd_x - center.x)
	var dz := absf(crowd_z - center.z)
	return dx <= half_x + radius and dz <= half_z + radius


func _living_enemies(group: Node3D) -> int:
	var hps: Array = group.get_meta("hps")
	var living := 0
	for hp in hps:
		if int(hp) > 0:
			living += 1
	return living


func _remove_enemies(group: Node3D, count: int) -> void:
	var hps: Array = group.get_meta("hps")
	var left := count
	var index := 0
	while index < hps.size() and left > 0:
		if int(hps[index]) > 0:
			hps[index] = 0
			left -= 1
		index += 1
	group.set_meta("hps", hps)
	_refresh_enemy_group(group)


func _set_soldiers(count: int) -> void:
	soldiers = Rules.clamp_soldiers(count)
	if count_label != null:
		count_label.text = str(soldiers)
	if Rules.is_game_over(soldiers):
		_show_game_over()


func _show_game_over() -> void:
	if game_over:
		return
	game_over = true
	game_over_layer.visible = true
	var line := game_over_layer.get_node("FinalScore") as Label
	line.text = "Distance %d" % int(crowd_z)


func _spawn_chunks() -> void:
	var ahead := crowd_z + SPAWN_AHEAD
	while float(Rules.chunk_origin(next_chunk)) < ahead:
		_build_chunk(next_chunk)
		next_chunk += 1
	for chunk in chunks.get_children():
		if chunk.position.z + float(Rules.CHUNK_LENGTH) < crowd_z - DESPAWN_BEHIND:
			chunk.queue_free()


func _build_chunk(index: int) -> void:
	var origin := float(Rules.chunk_origin(index))
	var chunk := Node3D.new()
	chunk.name = "Chunk%d" % index
	chunk.position = Vector3(0, 0, origin)
	chunks.add_child(chunk)
	_add_road(chunk)
	if index % 2 == 0:
		_add_tires(chunk, origin)
	else:
		_add_enemies(chunk, origin)
	_add_gates(chunk, origin)


func _add_road(chunk: Node3D) -> void:
	var length := float(Rules.CHUNK_LENGTH)
	var road := _box(Vector3(ROAD_WIDTH, 0.35, length), COLOR_ROAD)
	road.position = Vector3(0, -0.18, length * 0.5)
	chunk.add_child(road)

	var dash_z := 2.0
	while dash_z < length - 1.0:
		var dash := _box(Vector3(0.16, 0.04, 1.4), Color.WHITE)
		dash.position = Vector3(0, 0.02, dash_z)
		chunk.add_child(dash)
		dash_z += 4.2

	var post := 1.5
	var post_index := 0
	while post < length:
		var color := COLOR_RED if post_index % 2 == 0 else Color.WHITE
		var left := _box(Vector3(0.22, 1.15, 0.22), color)
		left.position = Vector3(-RAIL_X, 0.55, post)
		var right := _box(Vector3(0.22, 1.15, 0.22), color)
		right.position = Vector3(RAIL_X, 0.55, post)
		chunk.add_child(left)
		chunk.add_child(right)
		post += 3.5
		post_index += 1

	var rail_mat := Color(0.25, 0.28, 0.32)
	var left_rail := _box(Vector3(0.12, 0.08, length), rail_mat)
	left_rail.position = Vector3(-RAIL_X, 1.15, length * 0.5)
	var right_rail := _box(Vector3(0.12, 0.08, length), rail_mat)
	right_rail.position = Vector3(RAIL_X, 1.15, length * 0.5)
	chunk.add_child(left_rail)
	chunk.add_child(right_rail)


func _add_tires(chunk: Node3D, origin: float) -> void:
	var hazard_z := origin + float(Rules.HAZARD_OFFSET)
	var time_left := (hazard_z - crowd_z) / Rules.RUN_SPEED
	if time_left < 0.25:
		time_left = 0.25
	var power := Rules.dps(soldiers, Rules.shots_per_second(), Rules.BULLET_DAMAGE)
	var picked: Dictionary = Rules.choose_obstacle(Rules.obstacle_choices(hazard_z), power, time_left)

	var tire := Node3D.new()
	tire.name = "Tires"
	tire.position = Vector3(0, 0, hazard_z - origin)
	tire.set_meta("kind", "tire")
	tire.set_meta("hp", int(picked["hp"]))
	tire.set_meta("resolved", false)
	tire.set_meta("half_x", 1.35)
	tire.set_meta("half_z", 0.7)
	chunk.add_child(tire)

	var stack := 0
	while stack < 4:
		var ring := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.62
		cyl.bottom_radius = 0.62
		cyl.height = 0.22
		ring.mesh = cyl
		ring.material_override = _mat(COLOR_TIRE)
		ring.position = Vector3(0, 0.16 + float(stack) * 0.24, 0)
		tire.add_child(ring)
		stack += 1

	var label := _make_label(str(int(picked["hp"])), COLOR_RED, 72)
	label.name = "Hp"
	label.position = Vector3(0, 1.7, 0)
	tire.add_child(label)


func _refresh_tire_label(tire: Node3D) -> void:
	var label := tire.get_node_or_null("Hp") as Label3D
	if label == null:
		return
	var hp := int(tire.get_meta("hp"))
	if hp <= 0:
		label.visible = false
	else:
		label.text = str(hp)


func _add_enemies(chunk: Node3D, origin: float) -> void:
	var hazard_z := origin + float(Rules.HAZARD_OFFSET)
	var count := Rules.enemy_group_size(hazard_z)
	var group := Node3D.new()
	group.name = "Enemies"
	group.position = Vector3(0, 0, hazard_z - origin)
	group.set_meta("kind", "enemies")
	group.set_meta("resolved", false)
	var hps: Array = []
	var spots: Array = []
	var offsets: Array = Rules.formation_offsets(count)
	var index := 0
	while index < count:
		hps.append(Rules.ENEMY_HP)
		var spot: Vector2 = offsets[index]
		spots.append(Vector3(spot.x, 0, spot.y))
		index += 1
	group.set_meta("hps", hps)
	group.set_meta("spots", spots)

	var bodies := MultiMeshInstance3D.new()
	bodies.name = "Bodies"
	var heads := MultiMeshInstance3D.new()
	heads.name = "Heads"
	group.add_child(bodies)
	group.add_child(heads)
	var body_mm := MultiMesh.new()
	body_mm.transform_format = MultiMesh.TRANSFORM_3D
	body_mm.mesh = red_body
	body_mm.instance_count = count
	var head_mm := MultiMesh.new()
	head_mm.transform_format = MultiMesh.TRANSFORM_3D
	head_mm.mesh = red_head
	head_mm.instance_count = count
	bodies.multimesh = body_mm
	heads.multimesh = head_mm
	chunk.add_child(group)
	_refresh_enemy_group(group)

	var label := _make_label(str(count * Rules.ENEMY_HP), COLOR_RED, 64)
	label.name = "Hp"
	label.position = Vector3(0, 1.8, 0)
	group.add_child(label)


func _refresh_enemy_group(group: Node3D) -> void:
	var hps: Array = group.get_meta("hps")
	var spots: Array = group.get_meta("spots")
	var bodies := group.get_node("Bodies") as MultiMeshInstance3D
	var heads := group.get_node("Heads") as MultiMeshInstance3D
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -20, 0))
	var total := 0
	var index := 0
	while index < hps.size():
		var alive := int(hps[index]) > 0
		var spot: Vector3 = spots[index]
		var body_at := hidden
		var head_at := hidden
		if alive:
			total += int(hps[index])
			body_at = Transform3D(Basis.IDENTITY, Vector3(spot.x, SOLDIER_Y, spot.z))
			head_at = Transform3D(Basis.IDENTITY, Vector3(spot.x, HEAD_Y, spot.z))
		bodies.multimesh.set_instance_transform(index, body_at)
		heads.multimesh.set_instance_transform(index, head_at)
		index += 1
	var label := group.get_node_or_null("Hp") as Label3D
	if label != null:
		label.visible = total > 0
		label.text = str(total)
	if total <= 0:
		group.visible = false


func _add_gates(chunk: Node3D, origin: float) -> void:
	var gate_z := origin + float(Rules.GATE_OFFSET)
	var pair: Dictionary = Rules.roll_pair(gate_z)
	_add_one_gate(chunk, origin, "left", pair["left"], -1.85, COLOR_GOOD)
	_add_one_gate(chunk, origin, "right", pair["right"], 1.85, COLOR_BAD)
	# Colors follow the gate, not the side. Rebuild with the real op.
	_paint_gate(chunk.get_node("GateLeft"), pair["left"])
	_paint_gate(chunk.get_node("GateRight"), pair["right"])


func _add_one_gate(chunk: Node3D, origin: float, side: String, spec: Dictionary, x: float, color: Color) -> void:
	var gate := Node3D.new()
	gate.name = "GateLeft" if side == "left" else "GateRight"
	gate.position = Vector3(x, 0, origin + float(Rules.GATE_OFFSET) - origin)
	gate.set_meta("kind", "gate")
	gate.set_meta("side", side)
	gate.set_meta("op", int(spec["op"]))
	gate.set_meta("amount", int(spec["amount"]))
	gate.set_meta("used", false)
	var panel := _box(Vector3(3.55, 2.3, 0.12), color)
	panel.position = Vector3(0, 1.35, 0)
	panel.name = "Panel"
	gate.add_child(panel)
	var label := _make_label(Rules.gate_label(int(spec["op"]), int(spec["amount"])), Color.WHITE, 110)
	# Sit the words on the camera side of the glass, so the blue or red panel does not cover them.
	label.position = Vector3(0, 1.4, -0.28)
	gate.add_child(label)
	chunk.add_child(gate)


func _paint_gate(gate: Node3D, spec: Dictionary) -> void:
	var panel := gate.get_node("Panel") as MeshInstance3D
	var good := Rules.is_good_op(int(spec["op"]))
	panel.material_override = _mat(COLOR_GOOD if good else COLOR_BAD, true)


func _popup(text: String, good: bool, at: Vector3) -> void:
	var label := _make_label(text, Color(0.25, 0.95, 0.4) if good else COLOR_RED, 96)
	# Pop the text up over the crowd, at the spot where the gate or crash happened.
	label.position = Vector3(at.x, 1.8, at.z)
	world.add_child(label)
	popups.append({"label": label, "life": 0.7})


func _float_popups(delta: float) -> void:
	var index := popups.size() - 1
	while index >= 0:
		var item: Dictionary = popups[index]
		var label := item["label"] as Label3D
		var life := float(item["life"]) - delta
		item["life"] = life
		if label != null:
			label.position.y += delta * 1.8
			label.modulate.a = clampf(life / 0.7, 0.0, 1.0)
		if life <= 0.0:
			if label != null:
				label.queue_free()
			popups.remove_at(index)
		index -= 1


func _place_camera() -> void:
	# X stays on the road center, so the whole bridge stays in frame.
	camera.position = Vector3(0, CAM_HEIGHT, crowd_z - CAM_BACK)
	camera.look_at(Vector3(0, 1.0, crowd_z + CAM_LOOK))
	if water != null:
		water.position = Vector3(0, -1.4, crowd_z + 40.0)


func _refresh_crowd_visual() -> void:
	var shown := soldiers
	if shown > Rules.VISIBLE_SOLDIERS:
		shown = Rules.VISIBLE_SOLDIERS
	var spots: Array = Rules.formation_offsets(shown)
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -20, 0))
	var index := 0
	while index < Rules.VISIBLE_SOLDIERS:
		var body_at := hidden
		var head_at := hidden
		if index < spots.size():
			var spot: Vector2 = spots[index]
			body_at = Transform3D(Basis.IDENTITY, Vector3(spot.x, 0, spot.y))
			head_at = Transform3D(Basis.IDENTITY, Vector3(spot.x, HEAD_Y - SOLDIER_Y, spot.y))
		body_multimesh.set_instance_transform(index, body_at)
		head_multimesh.set_instance_transform(index, head_at)
		index += 1
	if crowd_root != null:
		crowd_root.position = Vector3(crowd_x, SOLDIER_Y, crowd_z)
	if count_label != null:
		count_label.position = Vector3(crowd_x, 2.3, crowd_z)
		count_label.text = str(soldiers)


func _paint_bullets() -> void:
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -20, 0))
	var slot := 0
	while slot < bullet_alive.size():
		var at := hidden
		if bullet_alive[slot]:
			at = Transform3D(Basis.IDENTITY, Vector3(float(bullet_x[slot]), BULLET_Y, float(bullet_z[slot])))
		bullet_multimesh.set_instance_transform(slot, at)
		slot += 1


func _build_look() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.62, 0.95)
	sky_mat.sky_horizon_color = Color(0.62, 0.82, 0.95)
	sky_mat.ground_bottom_color = Color(0.15, 0.45, 0.75)
	sky_mat.ground_horizon_color = Color(0.45, 0.72, 0.9)
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.94, 1.0)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 25, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = false
	add_child(sun)
	camera.fov = CAM_FOV


func _build_water() -> void:
	water = _box(Vector3(60, 1.2, 220), COLOR_WATER)
	water.name = "Water"
	water.position = Vector3(0, -1.4, 80)
	world.add_child(water)


func _build_crowd() -> void:
	blue_body = CapsuleMesh.new()
	blue_body.radius = 0.16
	blue_body.height = 0.72
	blue_head = SphereMesh.new()
	blue_head.radius = 0.15
	blue_head.height = 0.3
	red_body = CapsuleMesh.new()
	red_body.radius = 0.16
	red_body.height = 0.72
	red_head = SphereMesh.new()
	red_head.radius = 0.15
	red_head.height = 0.3
	var blue_mat := _mat(COLOR_BLUE)
	var red_mat := _mat(COLOR_RED)
	blue_body.material = blue_mat
	blue_head.material = blue_mat
	red_body.material = red_mat
	red_head.material = red_mat

	crowd_root = Node3D.new()
	crowd_root.name = "Crowd"
	crowd_root.position = Vector3(crowd_x, SOLDIER_Y, crowd_z)
	world.add_child(crowd_root)

	body_multimesh = _multi(blue_body, Rules.VISIBLE_SOLDIERS)
	head_multimesh = _multi(blue_head, Rules.VISIBLE_SOLDIERS)
	body_mesh = MultiMeshInstance3D.new()
	body_mesh.name = "Bodies"
	body_mesh.multimesh = body_multimesh
	head_mesh = MultiMeshInstance3D.new()
	head_mesh.name = "Heads"
	head_mesh.multimesh = head_multimesh
	crowd_root.add_child(body_mesh)
	crowd_root.add_child(head_mesh)

	count_label = _make_label(str(Rules.STARTING_SOLDIERS), Color.WHITE, 80)
	count_label.outline_modulate = Color(0.05, 0.12, 0.28)
	count_label.position = Vector3(crowd_x, 2.3, crowd_z)
	world.add_child(count_label)


func _build_bullet_pool() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var mat := _mat(COLOR_YELLOW)
	mat.emission_enabled = true
	mat.emission = COLOR_YELLOW
	mat.emission_energy_multiplier = 1.6
	mesh.material = mat
	bullet_multimesh = _multi(mesh, Rules.BULLET_POOL)
	bullet_mesh = MultiMeshInstance3D.new()
	bullet_mesh.name = "Bullets"
	bullet_mesh.multimesh = bullet_multimesh
	world.add_child(bullet_mesh)
	var slot := 0
	while slot < Rules.BULLET_POOL:
		bullet_alive.append(false)
		bullet_x.append(0.0)
		bullet_z.append(0.0)
		bullet_damage.append(0)
		slot += 1
	_paint_bullets()


func _multi(mesh: Mesh, count: int) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -20, 0))
	var index := 0
	while index < count:
		multi.set_instance_transform(index, hidden)
		index += 1
	return multi


func _box(size: Vector3, color: Color, transparent: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color, transparent)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _mat(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.72
	if transparent or color.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _make_label(text: String, color: Color, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.012
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label
