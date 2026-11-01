extends SceneTree

# Checks the math in scripts/lane_rules.gd without opening the game window.
# The older checks use their own numbers. The newer ones check the road:
# pairs, volleys, small early gates, and the fixed spacing.
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
	# Gate math: add, subtract, multiply.
	_expect("add: 5 + 3", LaneRules.apply_gate(5, LaneRules.Op.ADD, 3, false), 8)
	_expect("sub: 5 - 2", LaneRules.apply_gate(5, LaneRules.Op.SUB, 2, false), 3)
	_expect("mul: 5 x 2", LaneRules.apply_gate(5, LaneRules.Op.MUL, 2, false), 10)
	_expect("mul: 7 x 3", LaneRules.apply_gate(7, LaneRules.Op.MUL, 3, false), 21)

	# The count stops at 0. It does not go negative.
	_expect("sub lands on 0", LaneRules.apply_gate(6, LaneRules.Op.SUB, 6, false), 0)
	_expect("sub clamps at 0", LaneRules.apply_gate(3, LaneRules.Op.SUB, 9, false), 0)
	_expect("mul clamps at 0", LaneRules.apply_gate(4, LaneRules.Op.MUL, -1, false), 0)
	_expect("add still works from 0", LaneRules.apply_gate(0, LaneRules.Op.ADD, 4, false), 4)

	# A locked gate does nothing, even if the label would hurt or help.
	_expect("locked add does nothing", LaneRules.apply_gate(5, LaneRules.Op.ADD, 10, true), 5)
	_expect("locked sub does nothing", LaneRules.apply_gate(1, LaneRules.Op.SUB, 5, true), 1)
	_expect("locked mul does nothing", LaneRules.apply_gate(4, LaneRules.Op.MUL, 2, true), 4)

	# Labels the player reads on the gates.
	_expect("add label", LaneRules.gate_label(LaneRules.Op.ADD, 10), "+10")
	_expect("sub label", LaneRules.gate_label(LaneRules.Op.SUB, 3), "-3")
	_expect("mul label", LaneRules.gate_label(LaneRules.Op.MUL, 2), "x2")

	# Each bullet lowers the lock by 1. At 0 the gate opens.
	# Extra hits stay at 0 and do not go negative.
	var first: Dictionary = LaneRules.hit_lock(3)
	_expect("lock 3 -> 2", int(first["hits_remaining"]), 2)
	_expect("lock 3 still shut", bool(first["unlocked"]), false)

	var second: Dictionary = LaneRules.hit_lock(int(first["hits_remaining"]))
	_expect("lock 2 -> 1", int(second["hits_remaining"]), 1)
	_expect("lock 2 still shut", bool(second["unlocked"]), false)

	var third: Dictionary = LaneRules.hit_lock(1)
	_expect("lock 1 -> 0", int(third["hits_remaining"]), 0)
	_expect("lock 1 opens", bool(third["unlocked"]), true)

	var extra: Dictionary = LaneRules.hit_lock(0)
	_expect("lock stays at 0", int(extra["hits_remaining"]), 0)
	_expect("opened lock stays open", bool(extra["unlocked"]), true)

	# Once the counter hits 0, the same gate can be applied.
	var opened: Dictionary = LaneRules.hit_lock(1)
	var after_open := LaneRules.apply_gate(5, LaneRules.Op.ADD, 10, not bool(opened["unlocked"]))
	_expect("opened gate adds", after_open, 15)

	# Enemies: bullets chip health, and contact removes runners.
	var chip: Dictionary = LaneRules.damage_enemy(3, 1)
	_expect("enemy 3 takes 1", int(chip["hp"]), 2)
	_expect("enemy 3 still up", bool(chip["defeated"]), false)

	var last_hit: Dictionary = LaneRules.damage_enemy(1, 1)
	_expect("enemy 1 takes 1", int(last_hit["hp"]), 0)
	_expect("enemy 1 is defeated", bool(last_hit["defeated"]), true)

	var big_hit: Dictionary = LaneRules.damage_enemy(2, 9)
	_expect("enemy health clamps at 0", int(big_hit["hp"]), 0)
	_expect("overkill still defeats", bool(big_hit["defeated"]), true)

	_expect("contact removes 1", LaneRules.enemy_contact(5, 1), 4)
	_expect("contact can wipe the squad", LaneRules.enemy_contact(2, 5), 0)
	_expect("contact stays at 0", LaneRules.enemy_contact(0, 1), 0)
	_expect("zero squad is game over", LaneRules.is_game_over(0), true)
	_expect("one squad is still playing", LaneRules.is_game_over(1), false)

	_expect("div: 5 / 2", LaneRules.apply_gate(5, LaneRules.Op.DIV, 2, false), 2)
	_expect("div: 1 / 2 wipes", LaneRules.apply_gate(1, LaneRules.Op.DIV, 2, false), 0)
	_expect("div label", LaneRules.gate_label(LaneRules.Op.DIV, 2), "/2")
	_expect("locked div does nothing", LaneRules.apply_gate(5, LaneRules.Op.DIV, 2, true), 5)
	_expect("squad cap stops a big add", LaneRules.apply_gate(20, LaneRules.Op.ADD, 10, false), LaneRules.MAX_SQUAD)

	var heavy: Dictionary = LaneRules.hit_lock(10, 4)
	_expect("merged bullet chips a lock by 4", int(heavy["hits_remaining"]), 6)
	_expect("merged bullet has not opened it", bool(heavy["unlocked"]), false)

	_check_pairs()
	_check_volleys()
	_check_scaling()
	_check_road()


func _check_pairs() -> void:
	var bad_pairs := 0
	var distances: Array = [0, 40, LaneRules.DISTANCE_PER_TIER, LaneRules.DISTANCE_PER_TIER * 3, 5000]
	for distance in distances:
		for side in [true, false]:
			for good_pick in 8:
				for bad_pick in 8:
					var pair: Dictionary = LaneRules.make_pair(int(distance), side, good_pick, bad_pick)
					if not _one_good_one_bad(pair, side):
						bad_pairs += 1
	for i in 40:
		var rolled: Dictionary = LaneRules.roll_pair(i * 25)
		if not _one_good_one_bad(rolled, false) and not _one_good_one_bad(rolled, true):
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
		return left_good and right_bad and not left_bad and not right_good
	return left_bad and right_good and not left_good and not right_bad


func _check_volleys() -> void:
	_expect("1 runner fires 1", LaneRules.volley_size(1), 1)
	_expect("5 runners fire 5", LaneRules.volley_size(5), 5)
	_expect("at the cap", LaneRules.volley_size(LaneRules.MAX_VISIBLE_BULLETS), LaneRules.MAX_VISIBLE_BULLETS)
	var over := LaneRules.MAX_VISIBLE_BULLETS + 7
	_expect("over the cap stays at the cap", LaneRules.volley_size(over), LaneRules.MAX_VISIBLE_BULLETS)
	_expect("0 runners fire 0", LaneRules.volley_size(0), 0)

	var five: Array = LaneRules.volley_damages(5)
	_expect("5 shots drawn", five.size(), 5)
	_expect("5 shots add up to 5", _sum(five), 5)

	var merged: Array = LaneRules.volley_damages(over)
	_expect("merged shot count", merged.size(), LaneRules.MAX_VISIBLE_BULLETS)
	_expect("merged shots add up to the squad", _sum(merged), over)


func _check_scaling() -> void:
	var early_good: Array = LaneRules.good_choices(0)
	var early_bad: Array = LaneRules.bad_choices(0)
	var early_ok := true
	var saw_div := false
	for choice in early_good:
		var good_gate: Dictionary = choice
		if int(good_gate["op"]) != LaneRules.Op.ADD:
			early_ok = false
		var good_amount := int(good_gate["amount"])
		if good_amount < 1 or good_amount > 3:
			early_ok = false
	for choice in early_bad:
		var bad_gate: Dictionary = choice
		var bad_op := int(bad_gate["op"])
		var bad_amount := int(bad_gate["amount"])
		if not LaneRules.is_bad_op(bad_op):
			early_ok = false
		if bad_op == LaneRules.Op.SUB and (bad_amount < 1 or bad_amount > 3):
			early_ok = false
		if bad_op == LaneRules.Op.DIV:
			saw_div = true
			if bad_amount != 2:
				early_ok = false
	if not saw_div:
		early_ok = false
	_expect("early gates stay small", early_ok, true)

	var later_distance := LaneRules.DISTANCE_PER_TIER * 4
	var early_add := _max_amount(early_good, LaneRules.Op.ADD)
	var later_add := _max_amount(LaneRules.good_choices(later_distance), LaneRules.Op.ADD)
	var early_sub := _max_amount(early_bad, LaneRules.Op.SUB)
	var later_sub := _max_amount(LaneRules.bad_choices(later_distance), LaneRules.Op.SUB)
	_expect("adds grow with distance", later_add > early_add, true)
	_expect("subs grow with distance", later_sub > early_sub, true)
	_expect("x2 is not in the opening", _max_amount(early_good, LaneRules.Op.MUL), -1)
	_expect("x2 shows up later", _max_amount(LaneRules.good_choices(later_distance), LaneRules.Op.MUL), LaneRules.MUL_AMOUNT)

	var early_hp := LaneRules.enemy_hp(0, 0)
	var later_hp := LaneRules.enemy_hp(later_distance, 0)
	_expect("enemy health grows", later_hp > early_hp, true)


func _check_road() -> void:
	_expect("enemy gap is half the gate spacing", LaneRules.ENEMY_AFTER_GATE * 2, LaneRules.GATE_PAIR_SPACING)
	_expect("gap is wider than a gate or enemy", LaneRules.ENEMY_AFTER_GATE > LaneRules.ROAD_SHAPE_HEIGHT, true)
	_expect("enemies cover a whole lane", LaneRules.ENEMY_LANE_COVERAGE >= 1.0, true)

	var first := LaneRules.gate_pair_distance(0)
	var second := LaneRules.gate_pair_distance(1)
	var third := LaneRules.gate_pair_distance(2)
	var late := LaneRules.gate_pair_distance(12)
	var late_next := LaneRules.gate_pair_distance(13)
	_expect("first gap is the constant", second - first, LaneRules.GATE_PAIR_SPACING)
	_expect("next gap is the same", third - second, LaneRules.GATE_PAIR_SPACING)
	_expect("late gap is still the same", late_next - late, LaneRules.GATE_PAIR_SPACING)
	_expect("distance does not jitter", LaneRules.gate_pair_distance(4), LaneRules.gate_pair_distance(4))

	var gate_a := int(LaneRules.encounter(0, 0)["distance"])
	var gate_b := int(LaneRules.encounter(2, 1)["distance"])
	var gate_c := int(LaneRules.encounter(4, 0)["distance"])
	_expect("encounter gate spacing", gate_b - gate_a, LaneRules.GATE_PAIR_SPACING)
	_expect("encounter gate spacing again", gate_c - gate_b, LaneRules.GATE_PAIR_SPACING)

	var between := int(LaneRules.encounter(1, 0)["distance"])
	_expect("enemy is after the first pair", between > gate_a, true)
	_expect("enemy is before the next pair", between < gate_b, true)
	_expect("enemy is centered in the gap", between - gate_a, gate_b - between)

	var problems := 0
	for slot in 30:
		var spec: Dictionary = LaneRules.encounter(slot, slot)
		var blocks := _blocked_count(spec)
		if blocks > 1:
			problems += 1
		var kind := int(spec["kind"])
		if kind == LaneRules.EncounterKind.ENEMY:
			if blocks != 1 or not LaneRules.enemy_covers_full_lane(spec):
				problems += 1
			var lane := int(spec["lane"])
			if lane != LaneRules.Lane.LEFT and lane != LaneRules.Lane.RIGHT:
				problems += 1
		elif blocks != 0:
			problems += 1
		# The other pick must still block exactly one lane, not both.
		var other: Dictionary = LaneRules.encounter(slot, slot + 1)
		if _blocked_count(other) > 1:
			problems += 1
		if kind == LaneRules.EncounterKind.ENEMY and _blocked_count(other) != 1:
			problems += 1
	_expect("never both lanes blocked", problems, 0)

	# One real schedule: a single lane choice per enemy, checked by distance.
	var left_at := {}
	var right_at := {}
	for slot in 40:
		var spec: Dictionary = LaneRules.encounter(slot, 0)
		var key := str(int(spec["distance"]))
		if bool(spec["left_blocked"]):
			left_at[key] = true
		if bool(spec["right_blocked"]):
			right_at[key] = true
	var doubled := 0
	for key in left_at.keys():
		if right_at.has(key):
			doubled += 1
	_expect("one schedule never blocks both lanes", doubled, 0)


func _blocked_count(spec: Dictionary) -> int:
	var blocks := 0
	if bool(spec["left_blocked"]):
		blocks += 1
	if bool(spec["right_blocked"]):
		blocks += 1
	return blocks


func _max_amount(choices: Array, op: int) -> int:
	var biggest := -1
	for choice in choices:
		var spec: Dictionary = choice
		if int(spec["op"]) == op and int(spec["amount"]) > biggest:
			biggest = int(spec["amount"])
	return biggest


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
