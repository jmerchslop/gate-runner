extends SceneTree

# Checks the math in scripts/lane_rules.gd without opening the game window.
# These tests use their own numbers, so you can change the tuning constants
# in lane_rules.gd without breaking them.
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


func _expect(label: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("PASS  ", label)
		return
	failures += 1
	print("FAIL  ", label, " | got ", got, " | want ", want)
