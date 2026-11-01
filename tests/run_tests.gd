extends SceneTree

# Checks scripts/run_rules.gd without opening the game window.
#
#   godot --headless --path . --script res://tests/run_tests.gd

const Rules = preload("res://scripts/run_rules.gd")

var failures := 0


func _initialize() -> void:
	print("Running crowd-run tests")
	_run()
	if failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("FAILED %d TEST(S)" % failures)
		quit(1)


func _run() -> void:
	_expect("add", Rules.apply_gate(1, Rules.Op.ADD, 2), 3)
	_expect("sub", Rules.apply_gate(5, Rules.Op.SUB, 2), 3)
	_expect("mul", Rules.apply_gate(4, Rules.Op.MUL, 2), 8)
	_expect("div", Rules.apply_gate(5, Rules.Op.DIV, 2), 2)
	_expect("sub clamps at 0", Rules.apply_gate(2, Rules.Op.SUB, 9), 0)
	_expect("div clamps at 0", Rules.apply_gate(1, Rules.Op.DIV, 2), 0)
	_expect("no crowd cap", Rules.apply_gate(80, Rules.Op.ADD, 40), 120)
	_expect("no cap on x2", Rules.apply_gate(50, Rules.Op.MUL, 2), 100)
	_expect("add label", Rules.gate_label(Rules.Op.ADD, 2), "+2")
	_expect("sub label", Rules.gate_label(Rules.Op.SUB, 1), "-1")
	_expect("x2 label", Rules.gate_label(Rules.Op.MUL, 2), "x2")

	_check_pairs()
	_check_growth()
	_check_x2()
	_check_spacing()
	_check_curve()
	_check_dps()
	_check_spawner()
	_check_crash()
	_check_formation()
	_check_volley()


func _check_pairs() -> void:
	var bad := 0
	var distances: Array = [0.0, 30.0, Rules.TIER_DISTANCE * 4.0, 500.0]
	for distance in distances:
		for side in [true, false]:
			for good_pick in 5:
				for bad_pick in 5:
					for roll in [0, 40, 99]:
						var pair: Dictionary = Rules.make_pair(float(distance), side, good_pick, bad_pick, roll)
						if not _one_good_one_bad(pair, side):
							bad += 1
	_expect("every pair is one good and one bad", bad, 0)


func _one_good_one_bad(pair: Dictionary, good_on_left: bool) -> bool:
	var left: Dictionary = pair["left"]
	var right: Dictionary = pair["right"]
	var left_good := Rules.is_good_op(int(left["op"]))
	var right_good := Rules.is_good_op(int(right["op"]))
	var left_bad := Rules.is_bad_op(int(left["op"]))
	var right_bad := Rules.is_bad_op(int(right["op"]))
	if good_on_left:
		return left_good and right_bad
	return left_bad and right_good


func _check_growth() -> void:
	var early := Rules.biggest_add(0.0)
	var later := Rules.biggest_add(Rules.TIER_DISTANCE * 3.0)
	_expect("opening adds are +1 or +2", early >= 1 and early <= 2, true)
	_expect("adds climb slowly", later > early and later <= early + 3, true)
	_expect("late adds stay small", later <= 5, true)
	_expect("subs grow", Rules.biggest_sub(Rules.TIER_DISTANCE * 3.0) > Rules.biggest_sub(0.0), true)
	var early_gate: Dictionary = Rules.make_good_gate(0.0, 0, 0)
	_expect("opening gate is not x2", int(early_gate["op"]), Rules.Op.ADD)


func _check_x2() -> void:
	_expect("x2 is only a few percent", Rules.X2_CHANCE_PERCENT >= 1 and Rules.X2_CHANCE_PERCENT <= 8, true)
	var late := Rules.TIER_DISTANCE * float(Rules.X2_MIN_TIER)
	var early_hits := 0
	var late_hits := 0
	for roll in 100:
		var early: Dictionary = Rules.make_good_gate(0.0, 1, roll)
		if int(early["op"]) == Rules.Op.MUL:
			early_hits += 1
		var gate: Dictionary = Rules.make_good_gate(late, 1, roll)
		if int(gate["op"]) == Rules.Op.MUL:
			late_hits += 1
	_expect("no x2 before the later tiers", early_hits, 0)
	_expect("later table matches the x2 percent", late_hits, Rules.X2_CHANCE_PERCENT)

	seed(12345)
	var rolls := 4000
	var seen := 0
	var step := 0
	while step < rolls:
		var pair: Dictionary = Rules.roll_pair(late + 5.0)
		var left: Dictionary = pair["left"]
		var good: Dictionary = left
		if Rules.is_bad_op(int(left["op"])):
			good = pair["right"]
		if int(good["op"]) == Rules.Op.MUL:
			seen += 1
		step += 1
	var scaled := seen * 100
	var low := Rules.X2_CHANCE_PERCENT - 3
	if low < 0:
		low = 0
	var high := Rules.X2_CHANCE_PERCENT + 3
	_expect("many rolls stay near the x2 percent", scaled >= rolls * low and scaled <= rolls * high, true)


func _check_spacing() -> void:
	var first := Rules.gate_distance(0)
	var second := Rules.gate_distance(1)
	var third := Rules.gate_distance(2)
	var late := Rules.gate_distance(11)
	var late_next := Rules.gate_distance(12)
	_expect("first gate gap", second - first, Rules.CHUNK_LENGTH)
	_expect("next gate gap", third - second, Rules.CHUNK_LENGTH)
	_expect("late gate gap", late_next - late, Rules.CHUNK_LENGTH)
	_expect("gate distance is stable", Rules.gate_distance(4), Rules.gate_distance(4))
	_expect("hazard sits before its gate", Rules.hazard_distance(3) < Rules.gate_distance(3), true)
	_expect("hazard gap matches the chunk", Rules.hazard_distance(6) - Rules.hazard_distance(5), Rules.CHUNK_LENGTH)


func _check_curve() -> void:
	var samples: Array = []
	var step := 0.0
	while step <= Rules.CURVE_DISTANCE * 1.4:
		samples.append(Rules.obstacle_hp(step))
		step += Rules.CURVE_DISTANCE / 10.0
	var monotone := true
	var index := 1
	while index < samples.size():
		if int(samples[index]) < int(samples[index - 1]):
			monotone = false
		index += 1
	_expect("tire HP never falls as distance grows", monotone, true)
	_expect("curve starts at the low HP", Rules.obstacle_hp(0.0), Rules.HP_MIN)
	_expect("curve ends on the plateau", Rules.obstacle_hp(Rules.CURVE_DISTANCE), Rules.HP_MAX)
	_expect("plateau stays flat", Rules.obstacle_hp(Rules.CURVE_DISTANCE * 2.0), Rules.HP_MAX)

	var early_rise := Rules.obstacle_hp(Rules.CURVE_DISTANCE * 0.2) - Rules.obstacle_hp(0.0)
	var mid_rise := Rules.obstacle_hp(Rules.CURVE_DISTANCE * 0.6) - Rules.obstacle_hp(Rules.CURVE_DISTANCE * 0.4)
	var late_rise := Rules.obstacle_hp(Rules.CURVE_DISTANCE) - Rules.obstacle_hp(Rules.CURVE_DISTANCE * 0.8)
	_expect("S-curve is steepest in the middle", mid_rise > early_rise and mid_rise > late_rise, true)


func _check_dps() -> void:
	_expect("dps is soldiers times rate times damage", Rules.dps(10, 4.0, 2), 80.0)
	_expect("one soldier dps", Rules.dps(1, Rules.shots_per_second(), Rules.BULLET_DAMAGE), Rules.shots_per_second())
	_expect("zero soldiers deal nothing", Rules.dps(0, 5.0, 1), 0.0)


func _check_spawner() -> void:
	# Budget is 30. 10 and 20 are safe. 50 is not. The toughest safe stack is 20.
	var options: Array = [
		{"id": "small", "hp": 10},
		{"id": "mid", "hp": 20},
		{"id": "huge", "hp": 50},
	]
	var picked: Dictionary = Rules.choose_obstacle(options, 10.0, 3.0)
	_expect("spawner picks the strongest safe stack", int(picked["hp"]), 20)

	var too_weak: Dictionary = Rules.choose_obstacle(options, 1.0, 1.0)
	_expect("if nothing is safe, pick the weakest", int(too_weak["hp"]), 10)

	var misses := 0
	var distances: Array = [0.0, 40.0, 140.0, 280.0]
	var crowds: Array = [1, 4, 15]
	var times: Array = [0.8, 2.0, 6.0]
	for distance in distances:
		var choices: Array = Rules.obstacle_choices(float(distance))
		for crowd in crowds:
			for time in times:
				var rate := Rules.shots_per_second()
				var power := Rules.dps(int(crowd), rate, Rules.BULLET_DAMAGE)
				var choice: Dictionary = Rules.choose_obstacle(choices, power, float(time))
				var budget := power * float(time)
				var safe_exists := false
				for option in choices:
					var spec: Dictionary = option
					if float(int(spec["hp"])) <= budget:
						safe_exists = true
				if safe_exists and float(int(choice["hp"])) > budget:
					misses += 1
	_expect("spawner never picks an unbreakable stack when a safe one exists", misses, 0)


func _check_crash() -> void:
	var tire: Dictionary = Rules.tire_crash(6, 4)
	_expect("tire crash costs the HP left", int(tire["soldiers"]), 2)
	_expect("tire stack breaks on impact", int(tire["hp_left"]), 0)
	var wiped: Dictionary = Rules.tire_crash(3, 9)
	_expect("tire crash stops at 0", int(wiped["soldiers"]), 0)
	var open: Dictionary = Rules.tire_crash(5, 0)
	_expect("a broken stack is free", int(open["soldiers"]), 5)

	var trade: Dictionary = Rules.enemy_trade(5, 3)
	_expect("trade keeps the extra soldiers", int(trade["soldiers"]), 2)
	_expect("trade removes the enemies", int(trade["enemies"]), 0)
	var lost: Dictionary = Rules.enemy_trade(2, 5)
	_expect("trade can wipe the crowd", int(lost["soldiers"]), 0)
	_expect("leftover enemies stay", int(lost["enemies"]), 3)


func _check_formation() -> void:
	_expect("no soldiers, no spots", Rules.formation_offsets(0).size(), 0)
	var one: Array = Rules.formation_offsets(1)
	_expect("one soldier stands in the middle", one.size(), 1)
	_expect("seven distinct spots", _distinct(Rules.formation_offsets(7)), 7)
	_expect("twenty distinct spots", _distinct(Rules.formation_offsets(20)), 20)


func _check_volley() -> void:
	var five: Array = Rules.volley_damages(5)
	_expect("5 soldiers draw 5 bullets", five.size(), 5)
	_expect("5 bullets add up to 5", _sum(five), 5)
	var crowd := Rules.MAX_BULLETS_PER_VOLLEY + 24
	var merged: Array = Rules.volley_damages(crowd)
	_expect("a big crowd still draws the bullet cap", merged.size(), Rules.MAX_BULLETS_PER_VOLLEY)
	_expect("merged bullets still add up to the crowd", _sum(merged), crowd)


func _distinct(points: Array) -> int:
	var unique := 0
	var index := 0
	while index < points.size():
		var spot: Vector2 = points[index]
		var copy := false
		var other := 0
		while other < index:
			var previous: Vector2 = points[other]
			if spot.distance_to(previous) < 0.01:
				copy = true
			other += 1
		if not copy:
			unique += 1
		index += 1
	return unique


func _sum(values: Array) -> int:
	var total := 0
	for value in values:
		total += int(value)
	return total


func _expect(label: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("PASS  ", label)
		return
	failures += 1
	print("FAIL  ", label, " | got ", got, " | want ", want)
