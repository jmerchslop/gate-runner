extends SceneTree

# Checks the math in scripts/lane_rules.gd without opening the game window.
#
# Run from the project folder:
#   godot --headless --path . --script res://tests/run_tests.gd

const LaneRules = preload("res://scripts/lane_rules.gd")

var failures := 0


func _initialize() -> void:
	print("Running lane rule tests")
	_run()
	if failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("FAILED %d TEST(S)" % failures)
		quit(1)


func _run() -> void:
	# Gate math: add, subtract, multiply, divide. No ceiling on the squad.
	_expect("add: 5 + 3", LaneRules.apply_gate(5, LaneRules.Op.ADD, 3), 8)
	_expect("sub: 5 - 2", LaneRules.apply_gate(5, LaneRules.Op.SUB, 2), 3)
	_expect("mul: 5 x 2", LaneRules.apply_gate(5, LaneRules.Op.MUL, 2), 10)
	_expect("mul: 7 x 3", LaneRules.apply_gate(7, LaneRules.Op.MUL, 3), 21)
	_expect("div: 5 / 2", LaneRules.apply_gate(5, LaneRules.Op.DIV, 2), 2)
	_expect("div: 1 / 2 wipes", LaneRules.apply_gate(1, LaneRules.Op.DIV, 2), 0)
	_expect("no cap on a big add", LaneRules.apply_gate(50, LaneRules.Op.ADD, 50), 100)
	_expect("no cap on x2", LaneRules.apply_gate(80, LaneRules.Op.MUL, 2), 160)

	# The count stops at 0. It does not go negative.
	_expect("sub lands on 0", LaneRules.apply_gate(6, LaneRules.Op.SUB, 6), 0)
	_expect("sub clamps at 0", LaneRules.apply_gate(3, LaneRules.Op.SUB, 9), 0)
	_expect("mul clamps at 0", LaneRules.apply_gate(4, LaneRules.Op.MUL, -1), 0)
	_expect("add still works from 0", LaneRules.apply_gate(0, LaneRules.Op.ADD, 4), 4)

	_expect("add label", LaneRules.gate_label(LaneRules.Op.ADD, 2), "+2")
	_expect("sub label", LaneRules.gate_label(LaneRules.Op.SUB, 3), "-3")
	_expect("mul label", LaneRules.gate_label(LaneRules.Op.MUL, 2), "x2")
	_expect("div label", LaneRules.gate_label(LaneRules.Op.DIV, 2), "/2")

	# Walls: bullets knock the counter down. At 0 the wall is broken.
	var chip: Dictionary = LaneRules.hit_wall(4, 1)
	_expect("wall 4 takes 1", int(chip["hits_remaining"]), 3)
	_expect("wall 4 still up", bool(chip["broken"]), false)

	var almost: Dictionary = LaneRules.hit_wall(1, 1)
	_expect("wall 1 breaks", int(almost["hits_remaining"]), 0)
	_expect("wall 1 is broken", bool(almost["broken"]), true)

	var smashed: Dictionary = LaneRules.hit_wall(3, 5)
	_expect("merged bullet breaks a wall", int(smashed["hits_remaining"]), 0)
	_expect("overkill still breaks", bool(smashed["broken"]), true)

	var spent: Dictionary = LaneRules.hit_wall(0, 1)
	_expect("broken wall stays at 0", int(spent["hits_remaining"]), 0)

	# Running into a standing wall costs the remaining hits and skips the gate.
	# A broken wall applies the gate and costs nothing extra.
	_expect("crash skips +3 and costs 4", LaneRules.take_gate(5, LaneRules.Op.ADD, 3, 4), 1)
	_expect("crash skips a nasty -9", LaneRules.take_gate(5, LaneRules.Op.SUB, 9, 2), 3)
	_expect("crash can end the run", LaneRules.take_gate(3, LaneRules.Op.ADD, 10, 9), 0)
	_expect("broken wall adds", LaneRules.take_gate(5, LaneRules.Op.ADD, 3, 0), 8)
	_expect("broken wall divides", LaneRules.take_gate(5, LaneRules.Op.DIV, 2, 0), 2)
	_expect("zero squad is game over", LaneRules.is_game_over(0), true)
	_expect("one squad is still playing", LaneRules.is_game_over(1), false)

	_check_wall_scaling()
	_check_pairs()
	_check_growth()
	_check_x2()
	_check_volleys()
	_check_spacing()


func _check_wall_scaling() -> void:
	var early := LaneRules.wall_hits_for_distance(0)
	var same_tier := LaneRules.wall_hits_for_distance(LaneRules.DISTANCE_PER_TIER - 1)
	var next_tier := LaneRules.wall_hits_for_distance(LaneRules.DISTANCE_PER_TIER)
	var later := LaneRules.wall_hits_for_distance(LaneRules.DISTANCE_PER_TIER * 4)
	_expect("opening wall hits", early, LaneRules.WALL_HITS_BASE)
	_expect("wall hits hold inside a tier", same_tier, early)
	_expect("next tier has a thicker wall", next_tier > early, true)
	_expect("walls keep thickening", later > next_tier, true)


func _check_pairs() -> void:
	var bad_pairs := 0
	var distances: Array = [0, 40, LaneRules.DISTANCE_PER_TIER, LaneRules.DISTANCE_PER_TIER * 4, 5000]
	for distance in distances:
		for side in [true, false]:
			for good_pick in 6:
				for bad_pick in 6:
					for x2_roll in [0, 50, 99]:
						var pair: Dictionary = LaneRules.make_pair(int(distance), side, good_pick, bad_pick, x2_roll)
						if not _one_good_one_bad(pair, side):
							bad_pairs += 1
	_expect("every pair is one good and one bad", bad_pairs, 0)


func _one_good_one_bad(pair: Dictionary, good_on_left: bool) -> bool:
	var left: Dictionary = pair["left"]
	var right: Dictionary = pair["right"]
	var left_good := LaneRules.is_good_op(int(left["op"]))
	var right_good := LaneRules.is_good_op(int(right["op"]))
	var left_bad := LaneRules.is_bad_op(int(left["op"]))
	var right_bad := LaneRules.is_bad_op(int(right["op"]))
	if good_on_left:
		return left_good and right_bad
	return left_bad and right_good


func _check_growth() -> void:
	var early_add := LaneRules.biggest_add(0)
	var later_add := LaneRules.biggest_add(LaneRules.DISTANCE_PER_TIER * 3)
	var early_sub := LaneRules.biggest_sub(0)
	var later_sub := LaneRules.biggest_sub(LaneRules.DISTANCE_PER_TIER * 3)
	_expect("opening adds are +1 or +2", early_add >= 1 and early_add <= 2, true)
	_expect("adds climb slowly", later_add > early_add and later_add <= early_add + 3, true)
	_expect("late adds stay small", later_add <= 5, true)
	_expect("opening subs stay small", early_sub >= 1 and early_sub <= 2, true)
	_expect("subs grow with distance", later_sub > early_sub, true)

	var early_gate: Dictionary = LaneRules.make_good_gate(0, 0, 0)
	_expect("distance 0 is not x2", int(early_gate["op"]), LaneRules.Op.ADD)
	var bad_gate: Dictionary = LaneRules.make_bad_gate(0, LaneRules.biggest_sub(0))
	_expect("bad gates include /2", int(bad_gate["op"]), LaneRules.Op.DIV)


func _check_x2() -> void:
	_expect("x2 chance is only a few percent", LaneRules.X2_CHANCE_PERCENT >= 1 and LaneRules.X2_CHANCE_PERCENT <= 8, true)

	var early_hits := 0
	var late_hits := 0
	var late_distance := LaneRules.DISTANCE_PER_TIER * LaneRules.X2_MIN_TIER
	for roll in 100:
		var early: Dictionary = LaneRules.make_good_gate(0, 0, roll)
		if int(early["op"]) == LaneRules.Op.MUL:
			early_hits += 1
		var late: Dictionary = LaneRules.make_good_gate(late_distance, 0, roll)
		if int(late["op"]) == LaneRules.Op.MUL:
			late_hits += 1
	_expect("no x2 in the opening table", early_hits, 0)
	_expect("late table matches the x2 percent", late_hits, LaneRules.X2_CHANCE_PERCENT)

	# Many real rolls, so the random path stays near that same percent.
	seed(12345)
	var rolls := 4000
	var x2s := 0
	for _i in rolls:
		var pair: Dictionary = LaneRules.roll_pair(late_distance)
		var left: Dictionary = pair["left"]
		var right: Dictionary = pair["right"]
		var good: Dictionary = left
		if LaneRules.is_bad_op(int(left["op"])):
			good = right
		if int(good["op"]) == LaneRules.Op.MUL:
			x2s += 1
	var scaled := x2s * 100
	var low := LaneRules.X2_CHANCE_PERCENT - 3
	if low < 0:
		low = 0
	var high := LaneRules.X2_CHANCE_PERCENT + 3
	_expect("many rolls stay near the x2 percent", scaled >= rolls * low and scaled <= rolls * high, true)


func _check_volleys() -> void:
	_expect("1 runner fires 1", LaneRules.volley_size(1), 1)
	_expect("5 runners fire 5", LaneRules.volley_size(5), 5)
	_expect("at the bullet cap", LaneRules.volley_size(LaneRules.MAX_VISIBLE_BULLETS), LaneRules.MAX_VISIBLE_BULLETS)
	var over := LaneRules.MAX_VISIBLE_BULLETS + 7
	_expect("over the cap stays at the cap", LaneRules.volley_size(over), LaneRules.MAX_VISIBLE_BULLETS)
	_expect("0 runners fire 0", LaneRules.volley_size(0), 0)

	var five: Array = LaneRules.volley_damages(5)
	_expect("5 shots drawn", five.size(), 5)
	_expect("5 shots add up to 5", _sum(five), 5)

	var merged: Array = LaneRules.volley_damages(over)
	_expect("merged shot count", merged.size(), LaneRules.MAX_VISIBLE_BULLETS)
	_expect("merged shots add up to the squad", _sum(merged), over)

	var big: Array = LaneRules.volley_damages(100)
	_expect("a huge squad still draws the cap", big.size(), LaneRules.MAX_VISIBLE_BULLETS)
	_expect("a huge squad's damage still adds up", _sum(big), 100)


func _check_spacing() -> void:
	var first := LaneRules.gate_pair_distance(0)
	var second := LaneRules.gate_pair_distance(1)
	var third := LaneRules.gate_pair_distance(2)
	var late := LaneRules.gate_pair_distance(12)
	var late_next := LaneRules.gate_pair_distance(13)
	_expect("first gap is the constant", second - first, LaneRules.GATE_PAIR_SPACING)
	_expect("next gap is the same", third - second, LaneRules.GATE_PAIR_SPACING)
	_expect("late gap is still the same", late_next - late, LaneRules.GATE_PAIR_SPACING)
	_expect("distance does not jitter", LaneRules.gate_pair_distance(4), LaneRules.gate_pair_distance(4))


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
