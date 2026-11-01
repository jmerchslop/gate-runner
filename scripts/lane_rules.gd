extends RefCounted

# This file is the rule book.
# It is not attached to anything you can see. It only does math on plain numbers,
# so the tests in tests/run_tests.gd can check it without opening the game.
#
# Locked-gate rule: a locked gate changes nothing when the squad runs through it.
# No bonus, no penalty. Bullets must bring its hit counter to 0 first.
# After that it is a normal gate. The squad count is never allowed below 0.

# ----------------------------------------------------------------
# Tuning numbers. Change these to make the game easier or harder.
# Speeds are in pixels per second. The window is 540 wide and 960 tall.
# Leave at least one number in each gate list.
# ----------------------------------------------------------------

# Runners you start with. The number drawn on the squad.
const STARTING_SQUAD := 5

# The squad count cannot go under this. 0 ends the run.
const MIN_SQUAD := 0

# Runners removed when an enemy touches the squad.
const ENEMY_CONTACT_LOSS := 1

# Health one bullet removes from an enemy.
const BULLET_DAMAGE := 1

# Bullet hits a new locked gate needs before it opens.
const DEFAULT_LOCK_HITS := 4

# Seconds between shots. Smaller means the squad fires faster.
const FIRE_EVERY_SECONDS := 0.16

# How fast the squad slides left and right.
const SQUAD_SLIDE_SPEED := 460.0

# How fast gates and enemies move down the screen.
# The squad stays at the bottom, so this is the "running forward" speed.
const SCROLL_SPEED := 240.0

# How fast bullets fly up the lane.
const BULLET_SPEED := 720.0

# Seconds between spawns at the start of a run.
const SPAWN_EVERY_SECONDS := 1.55

# The shortest pause the spawner is allowed to shrink to.
const MIN_SPAWN_EVERY_SECONDS := 0.85

# Each spawn, the pause gets shorter by this many seconds.
const SPAWN_RAMP_STEP := 0.04

# Extra random wait added to each spawn, from 0 up to this many seconds.
const SPAWN_JITTER_SECONDS := 0.4

# Chance that a spawn is an enemy instead of a gate pair. 0.0 to 1.0.
const ENEMY_SPAWN_CHANCE := 0.34

# Chance that one gate in a pair starts locked. The other side stays open.
const LOCK_CHANCE := 0.55

# Enemy health is picked inside this range, including both ends.
const ENEMY_HP_MIN := 2
const ENEMY_HP_MAX := 4

# How many pixels of scrolling equal one distance point on the HUD.
# Smaller makes the score climb faster.
const PIXELS_PER_DISTANCE := 12.0

# The three kinds of gate.
# ADD is +N, SUB is -N, MUL is xN (x2 turns 5 into 10).
enum Op { ADD, SUB, MUL }

# Add gates are listed more than once so they show up more often.
const OP_DECK: Array[int] = [Op.ADD, Op.ADD, Op.ADD, Op.SUB, Op.MUL]

const ADD_AMOUNTS: Array[int] = [4, 6, 8, 10]
const SUB_AMOUNTS: Array[int] = [2, 3, 5]
const MUL_AMOUNTS: Array[int] = [2]


# ----------------------------------------------------------------
# Rules. These functions only return new numbers. They change nothing else.
# ----------------------------------------------------------------

# Keep a squad count from going below zero.
static func clamp_squad(count: int) -> int:
	if count < MIN_SQUAD:
		return MIN_SQUAD
	return count


# Apply one gate to the squad count.
# locked = true means the gate is still shut, so the count stays the same.
static func apply_gate(count: int, op: int, amount: int, locked: bool) -> int:
	if locked:
		return count

	var next := count
	if op == Op.ADD:
		next = count + amount
	elif op == Op.SUB:
		next = count - amount
	elif op == Op.MUL:
		next = count * amount

	return clamp_squad(next)


# True when the run should end.
static func is_game_over(count: int) -> bool:
	return count <= MIN_SQUAD


# One bullet hit on a locked gate.
# Returns the hits still left, and whether the gate is now open.
# Keys: "hits_remaining" (int), "unlocked" (bool).
static func hit_lock(hits_remaining: int) -> Dictionary:
	var left := hits_remaining - 1
	if left < 0:
		left = 0
	return {
		"hits_remaining": left,
		"unlocked": left == 0,
	}


# One bullet hitting an enemy.
# Returns the new health, and whether the enemy is defeated.
# Keys: "hp" (int), "defeated" (bool).
static func damage_enemy(hp: int, damage: int) -> Dictionary:
	var left := hp - damage
	if left < 0:
		left = 0
	return {
		"hp": left,
		"defeated": left == 0,
	}


# An enemy reached the squad. `loss` is how many runners it removes.
static func enemy_contact(count: int, loss: int) -> int:
	return clamp_squad(count - loss)


# The words painted on a gate, such as "+10", "-3", or "x2".
static func gate_label(op: int, amount: int) -> String:
	if op == Op.ADD:
		return "+%d" % amount
	if op == Op.SUB:
		return "-%d" % amount
	if op == Op.MUL:
		return "x%d" % amount
	return "?"
