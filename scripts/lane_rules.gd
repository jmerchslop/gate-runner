extends RefCounted

# This file is the rule book.
# It is not attached to anything you can see. It only does math on plain numbers,
# so the tests in tests/run_tests.gd can check it without opening the game.
#
# Locked-gate rule: a locked gate changes nothing when the squad runs through it.
# No bonus, no penalty. Bullets must bring its hit counter to 0 first.
# After that it is a normal gate.
#
# Pair rule: every pair is one good gate and one bad gate. Which side is
# which is random. Good gates are +N or x2. Bad gates are -N or /2.
#
# Road rule: gate pairs are a fixed distance apart, measured in pixels the
# squad has traveled. An enemy sits halfway between pairs, filling one whole
# lane. The other lane at that spot is empty, so one lane is always passable.
#
# The squad count is never below 0 and never above MAX_SQUAD.

# ----------------------------------------------------------------
# Tuning numbers. Change these to make the game easier or harder.
# Speeds are in pixels per second. The window is 540 wide and 960 tall.
# ----------------------------------------------------------------

# Runners you start with. The number drawn on the squad.
const STARTING_SQUAD := 5

# The squad count cannot go under this. 0 ends the run.
const MIN_SQUAD := 0

# The squad count cannot go over this. Bigger gates stop here,
# so the number on the squad stays readable.
const MAX_SQUAD := 24

# How much damage one runner contributes in a volley.
const BULLET_DAMAGE := 1

# Most bullets we actually draw in one volley.
# The squad count is how many shots the volley stands for.
# 1 to 8 runners fire that many bullets, each hitting for BULLET_DAMAGE.
# Past 8, we still draw only 8 bullets and merge the extra runners into them.
# Example: 10 runners fire 8 bullets whose damages add up to 10
# (two hit for 2, six hit for 1). A bigger squad still hits harder.
const MAX_VISIBLE_BULLETS := 8

# Pixels between bullet centers in a volley. They fly straight up, side by side.
const VOLLEY_GAP := 16.0

# The row of bullets is never wider than this, even if the cap is raised.
# 8 bullets at 16 pixels apart use 112 pixels, a bit wider than the squad body,
# so you can see every shot without filling the lane.
const VOLLEY_MAX_SPAN := 112.0

# Seconds between volleys. Smaller means the squad fires faster.
const FIRE_EVERY_SECONDS := 0.22

# How fast the squad slides left and right.
const SQUAD_SLIDE_SPEED := 460.0

# How fast gates and enemies move down the screen.
# The squad stays at the bottom, so this is the "running forward" speed.
const SCROLL_SPEED := 240.0

# How fast bullets fly up the lane.
const BULLET_SPEED := 720.0

# Pixels of travel from one gate pair to the next.
# This never changes and it is not random. 560 pixels is a bit over 2 seconds.
const GATE_PAIR_SPACING := 560

# An enemy is placed this far after a gate pair, halfway to the next one.
# Half of GATE_PAIR_SPACING, so the enemy sits in the gap and does not touch either pair.
const ENEMY_AFTER_GATE := 280

# Pixels traveled before the first gate pair.
# Big enough that the pair scrolls in from the top instead of appearing on the squad.
const FIRST_GATE_DISTANCE := 980

# Tallest gate or enemy, in pixels. The gap above is larger than this,
# so a gate and an enemy cannot overlap on the road.
const ROAD_SHAPE_HEIGHT := 96

# An enemy always covers this much of one half of the road. 1.0 means the whole half.
const ENEMY_LANE_COVERAGE := 1.0

# Chance that one gate in a pair starts locked. The other side stays open.
# The pair is still one good gate and one bad gate either way.
const LOCK_CHANCE := 0.5

# Bullet hits a locked gate needs at distance 0.
# Each later tier adds LOCK_HITS_PER_TIER, but slower than the squad's
# firepower grows, so a bigger squad still opens locks faster.
const LOCK_HITS_BASE := 12
const LOCK_HITS_PER_TIER := 1

# How many pixels of scrolling equal one distance point on the HUD.
# Smaller makes the score climb faster.
const PIXELS_PER_DISTANCE := 12.0

# Gate values and enemy strength step up together.
# Every DISTANCE_PER_TIER distance points is one tier, and tiers stop at MAX_TIER.
# At about 20 distance points a second, a new tier is roughly 7 seconds.
const DISTANCE_PER_TIER := 140
const MAX_TIER := 6

# Good gates at the start are only +1, +2, and +3.
# Each tier raises the biggest + by ADD_PER_TIER, up to ADD_MAX.
const EARLY_ADD_MAX := 3
const ADD_PER_TIER := 1
const ADD_MAX := 8

# x2 is not offered until this tier, and then only as one choice in a longer
# list, so it stays uncommon.
const MUL_AMOUNT := 2
const MUL_MIN_TIER := 2

# Bad gates at the start are -1, -2, and /2.
# Each tier raises the biggest - by SUB_PER_TIER, up to SUB_MAX.
# /2 is always available. It keeps half the squad, rounded down.
const EARLY_SUB_MAX := 2
const SUB_PER_TIER := 1
const SUB_MAX := 6
const DIV_AMOUNT := 2

# Enemy health at distance 0 is ENEMY_HP_BASE, plus up to ENEMY_HP_SPREAD.
# Each tier adds ENEMY_HP_PER_TIER to that whole range.
const ENEMY_HP_BASE := 6
const ENEMY_HP_PER_TIER := 2
const ENEMY_HP_SPREAD := 2

# Runners removed when an enemy touches the squad, at distance 0.
# Each tier adds one more, up to the max, so a late hit really hurts.
const ENEMY_CONTACT_LOSS_BASE := 2
const ENEMY_CONTACT_LOSS_PER_TIER := 1
const ENEMY_CONTACT_LOSS_MAX := 6

# ADD is +N, SUB is -N, MUL is xN, DIV is /N (a whole-number split).
enum Op { ADD, SUB, MUL, DIV }

# Which half of the road an enemy fills.
enum Lane { LEFT, RIGHT }

# What the road places along the run. Gates, then an enemy, then gates, and so on.
enum EncounterKind { GATE_PAIR, ENEMY }


# ----------------------------------------------------------------
# Rules. These functions only return new numbers. They change nothing else.
# ----------------------------------------------------------------

# Keep a squad count inside 0 .. MAX_SQUAD.
static func clamp_squad(count: int) -> int:
	if count < MIN_SQUAD:
		return MIN_SQUAD
	if count > MAX_SQUAD:
		return MAX_SQUAD
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
	elif op == Op.DIV:
		next = divide_squad(count, amount)

	return clamp_squad(next)


# Whole-number split used by /N gates.
# /2 keeps one of the two shares: 5 becomes 2, and 1 becomes 0.
static func divide_squad(count: int, parts: int) -> int:
	if parts <= 1:
		return count
	var share := 0
	var left := count
	while left >= parts:
		left -= parts
		share += 1
	return share


# True when the run should end.
static func is_game_over(count: int) -> bool:
	return count <= MIN_SQUAD


# + and x help. - and / hurt.
static func is_good_op(op: int) -> bool:
	return op == Op.ADD or op == Op.MUL


static func is_bad_op(op: int) -> bool:
	return op == Op.SUB or op == Op.DIV


# 0 at the start of a run, then one higher every DISTANCE_PER_TIER points.
static func tier_for_distance(distance: int) -> int:
	var points_left := distance
	if points_left < 0:
		points_left = 0
	var tier := 0
	while tier < MAX_TIER and points_left >= DISTANCE_PER_TIER:
		points_left -= DISTANCE_PER_TIER
		tier += 1
	return tier


# The good gate choices for this distance. Early on this is only +1, +2, +3.
static func good_choices(distance: int) -> Array:
	var tier := tier_for_distance(distance)
	var biggest := EARLY_ADD_MAX + tier * ADD_PER_TIER
	if biggest > ADD_MAX:
		biggest = ADD_MAX
	var choices: Array = []
	var amount := 1
	while amount <= biggest:
		choices.append({"op": Op.ADD, "amount": amount})
		amount += 1
	if tier >= MUL_MIN_TIER:
		choices.append({"op": Op.MUL, "amount": MUL_AMOUNT})
	return choices


# The bad gate choices for this distance. /2 is always one of them.
static func bad_choices(distance: int) -> Array:
	var tier := tier_for_distance(distance)
	var biggest := EARLY_SUB_MAX + tier * SUB_PER_TIER
	if biggest > SUB_MAX:
		biggest = SUB_MAX
	var choices: Array = []
	var amount := 1
	while amount <= biggest:
		choices.append({"op": Op.SUB, "amount": amount})
		amount += 1
	choices.append({"op": Op.DIV, "amount": DIV_AMOUNT})
	return choices


# One pair. good_on_left picks the side.
# good_pick and bad_pick choose from that distance's lists.
# Any whole number works, including big random ones.
# Returns {"left": {op, amount}, "right": {op, amount}}.
static func make_pair(distance: int, good_on_left: bool, good_pick: int, bad_pick: int) -> Dictionary:
	var good := _pick_choice(good_choices(distance), good_pick)
	var bad := _pick_choice(bad_choices(distance), bad_pick)
	if good_on_left:
		return {"left": good, "right": bad}
	return {"left": bad, "right": good}


# The scene calls this. Tests call make_pair so they do not depend on luck.
static func roll_pair(distance: int) -> Dictionary:
	var good_on_left := randf() < 0.5
	return make_pair(distance, good_on_left, randi(), randi())


# Where gate pair number pair_index sits, in pixels traveled.
# Pair 0, pair 1, pair 2, ... are exactly GATE_PAIR_SPACING apart.
static func gate_pair_distance(pair_index: int) -> int:
	var index := pair_index
	if index < 0:
		index = 0
	return FIRST_GATE_DISTANCE + index * GATE_PAIR_SPACING


# Where the enemy after that pair sits. Always halfway to the next pair.
static func enemy_distance(pair_index: int) -> int:
	return gate_pair_distance(pair_index) + ENEMY_AFTER_GATE


# Fold any whole number into the left lane or the right lane. Never both.
static func lane_for_pick(lane_pick: int) -> int:
	if posmod(lane_pick, 2) == 0:
		return Lane.LEFT
	return Lane.RIGHT


# The road is a list of encounters: 0 gate, 1 enemy, 2 gate, 3 enemy, ...
# lane_pick only matters for an enemy. It chooses which single lane is filled.
# Returns distance, kind, and which lanes an enemy blocks.
static func encounter(index: int, lane_pick: int) -> Dictionary:
	var pair_index := _pair_index(index)
	if _is_gate_slot(index):
		return {
			"kind": EncounterKind.GATE_PAIR,
			"distance": gate_pair_distance(pair_index),
			"pair_index": pair_index,
			"lane": -1,
			"full_lane": false,
			"left_blocked": false,
			"right_blocked": false,
		}
	var lane := lane_for_pick(lane_pick)
	return {
		"kind": EncounterKind.ENEMY,
		"distance": enemy_distance(pair_index),
		"pair_index": pair_index,
		"lane": lane,
		"full_lane": true,
		"left_blocked": lane == Lane.LEFT,
		"right_blocked": lane == Lane.RIGHT,
	}


# True when this encounter is an enemy stretched across one whole lane.
static func enemy_covers_full_lane(spec: Dictionary) -> bool:
	if int(spec["kind"]) != EncounterKind.ENEMY:
		return false
	if not bool(spec["full_lane"]):
		return false
	return ENEMY_LANE_COVERAGE >= 1.0


static func _is_gate_slot(index: int) -> bool:
	return posmod(index, 2) == 0


# Encounter 0 and 1 belong to pair 0, encounter 2 and 3 belong to pair 1, and so on.
static func _pair_index(index: int) -> int:
	var steps := index
	if steps < 0:
		steps = 0
	var pair := 0
	while steps >= 2:
		steps -= 2
		pair += 1
	return pair


# How many bullets to draw for this squad count. Never more than the cap.
static func volley_size(count: int) -> int:
	var runners := count
	if runners < 0:
		runners = 0
	if runners > MAX_VISIBLE_BULLETS:
		return MAX_VISIBLE_BULLETS
	return runners


# One damage number per visible bullet. They add up to the squad count,
# then the scene multiplies by BULLET_DAMAGE.
# Under the cap every entry is 1. Over the cap the extras are merged in.
static func volley_damages(count: int) -> Array:
	var visible := volley_size(count)
	var damages: Array = []
	if visible == 0:
		return damages
	var runners := count
	if runners < 0:
		runners = 0
	var fill := 0
	while fill < visible:
		damages.append(0)
		fill += 1
	var index := 0
	while runners > 0:
		damages[index] = int(damages[index]) + 1
		runners -= 1
		index += 1
		if index >= visible:
			index = 0
	return damages


# Width of the bullet row, in pixels. One bullet sits in the middle.
static func volley_span(visible: int) -> float:
	if visible <= 1:
		return 0.0
	var span := float(visible - 1) * VOLLEY_GAP
	if span > VOLLEY_MAX_SPAN:
		return VOLLEY_MAX_SPAN
	return span


# Hits a locked gate needs when it appears at this distance.
static func lock_hits_for_distance(distance: int) -> int:
	return LOCK_HITS_BASE + tier_for_distance(distance) * LOCK_HITS_PER_TIER


# One bullet hitting a locked gate. `hits` is how much to subtract.
# A normal bullet passes 1. A merged bullet passes its damage.
# Returns the hits still left, and whether the gate is now open.
# Keys: "hits_remaining" (int), "unlocked" (bool).
static func hit_lock(hits_remaining: int, hits: int = 1) -> Dictionary:
	var taken := hits
	if taken < 0:
		taken = 0
	var left := hits_remaining - taken
	if left < 0:
		left = 0
	return {
		"hits_remaining": left,
		"unlocked": left == 0,
	}


# Health for an enemy that appears at this distance.
# `pick` chooses inside the tier's range. Any whole number works.
static func enemy_hp(distance: int, pick: int) -> int:
	var tier := tier_for_distance(distance)
	var lowest := ENEMY_HP_BASE + tier * ENEMY_HP_PER_TIER
	var steps := ENEMY_HP_SPREAD + 1
	if steps < 1:
		steps = 1
	return lowest + posmod(pick, steps)


# Runners lost if that enemy reaches the squad.
static func enemy_contact_loss(distance: int) -> int:
	var loss := ENEMY_CONTACT_LOSS_BASE + tier_for_distance(distance) * ENEMY_CONTACT_LOSS_PER_TIER
	if loss > ENEMY_CONTACT_LOSS_MAX:
		return ENEMY_CONTACT_LOSS_MAX
	return loss


# One bullet hitting an enemy.
# Returns the new health, and whether the enemy is defeated.
# Keys: "hp" (int), "defeated" (bool).
static func damage_enemy(hp: int, damage: int) -> Dictionary:
	var taken := damage
	if taken < 0:
		taken = 0
	var left := hp - taken
	if left < 0:
		left = 0
	return {
		"hp": left,
		"defeated": left == 0,
	}


# An enemy reached the squad. `loss` is how many runners it removes.
static func enemy_contact(count: int, loss: int) -> int:
	return clamp_squad(count - loss)


# The words painted on a gate, such as "+2", "-3", "x2", or "/2".
static func gate_label(op: int, amount: int) -> String:
	if op == Op.ADD:
		return "+%d" % amount
	if op == Op.SUB:
		return "-%d" % amount
	if op == Op.MUL:
		return "x%d" % amount
	if op == Op.DIV:
		return "/%d" % amount
	return "?"


static func _pick_choice(choices: Array, pick: int) -> Dictionary:
	var size := choices.size()
	if size <= 0:
		return {"op": Op.ADD, "amount": 1}
	var chosen: Dictionary = choices[posmod(pick, size)]
	return {"op": int(chosen["op"]), "amount": int(chosen["amount"])}
