extends RefCounted

# This file is the rule book.
# It is not attached to anything you can see. It only does math on plain numbers,
# so the tests in tests/run_tests.gd can check it without opening the game.
#
# Pair rule: every pair is one good gate and one bad gate. Which side is
# which is random. Good gates are +N, or very rarely x2. Bad gates are -N or /2.
#
# Wall rule: every gate has a wall in front of it. The number on the wall is
# how many hits are left. Bullets lower that number. You only get the gate's
# effect when the wall is already at 0.
# If you run into a wall that still has hits left, you do not get the gate.
# You lose one runner for each hit still showing. Shooting the wall first
# makes that crash cheaper. Breaking it all the way (0) lets the gate through
# and costs nothing extra. The squad count never goes below 0. There is no cap.
#
# Road rule: gate pairs are a fixed distance apart, measured in pixels the
# squad has traveled. That gap never changes and it is not random.

# ----------------------------------------------------------------
# Tuning numbers. Change these to make the game easier or harder.
# Speeds are in pixels per second. The window is 540 wide and 960 tall.
# ----------------------------------------------------------------

# Runners you start with. The number drawn on the squad.
const STARTING_SQUAD := 5

# The squad count cannot go under this. 0 ends the run.
# There is no maximum. The squad can keep growing.
const MIN_SQUAD := 0

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

# How fast gates move down the screen.
# The squad stays at the bottom, so this is the "running forward" speed.
const SCROLL_SPEED := 240.0

# How fast bullets fly up the lane.
const BULLET_SPEED := 720.0

# Pixels of travel from one gate pair to the next.
# This never changes and it is not random. 560 pixels is a bit over 2 seconds.
const GATE_PAIR_SPACING := 560

# Pixels traveled before the first gate pair.
# Big enough that the pair scrolls in from the top instead of appearing on the squad.
const FIRST_GATE_DISTANCE := 980

# How many pixels of scrolling equal one distance point on the HUD.
# Smaller makes the score climb faster.
const PIXELS_PER_DISTANCE := 12.0

# Gate values and wall strength step up together.
# Every DISTANCE_PER_TIER distance points is one tier, and tiers stop at MAX_TIER.
# At about 20 distance points a second, a new tier is about 10 seconds.
const DISTANCE_PER_TIER := 200
const MAX_TIER := 8

# Good gates at the start are only +1 and +2.
# Each tier raises the biggest + by ADD_PER_TIER, and it stops at ADD_MAX.
# The steps are small on purpose, so the squad climbs instead of ballooning.
const EARLY_ADD_MAX := 2
const ADD_PER_TIER := 1
const ADD_MAX := 4

# x2 is this many good gates out of 100, and only once the tier reaches X2_MIN_TIER.
# 4 means about 4 percent. Rolls of 0, 1, 2, and 3 are x2. The rest are plain adds.
const X2_CHANCE_PERCENT := 4
const X2_MIN_TIER := 3
const MUL_AMOUNT := 2

# Bad gates at the start are -1, -2, and /2.
# Each tier raises the biggest - by SUB_PER_TIER, up to SUB_MAX.
# /2 is always available. It keeps half the squad, rounded down.
const EARLY_SUB_MAX := 2
const SUB_PER_TIER := 1
const SUB_MAX := 5
const DIV_AMOUNT := 2

# Hits on a new wall at distance 0.
# Each later tier adds WALL_HITS_PER_TIER, so later walls take longer to break
# and cost more runners if you crash into them.
const WALL_HITS_BASE := 4
const WALL_HITS_PER_TIER := 2

# ADD is +N, SUB is -N, MUL is xN, DIV is /N (a whole-number split).
enum Op { ADD, SUB, MUL, DIV }


# ----------------------------------------------------------------
# Rules. These functions only return new numbers. They change nothing else.
# ----------------------------------------------------------------

# The squad count cannot go below zero. It can grow without a ceiling.
static func clamp_squad(count: int) -> int:
	if count < MIN_SQUAD:
		return MIN_SQUAD
	return count


# Apply one gate whose wall is already broken.
static func apply_gate(count: int, op: int, amount: int) -> int:
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


# What happens when the squad reaches a gate.
# hits_left > 0 means the wall is still up: lose that many runners, skip the gate.
# hits_left == 0 means the wall is broken: apply the gate and lose nobody extra.
static func take_gate(count: int, op: int, amount: int, hits_left: int) -> int:
	if hits_left > 0:
		return clamp_squad(count - hits_left)
	return apply_gate(count, op, amount)


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


# Hits a wall needs when it appears at this distance. Later distance means more hits.
static func wall_hits_for_distance(distance: int) -> int:
	return WALL_HITS_BASE + tier_for_distance(distance) * WALL_HITS_PER_TIER


# One bullet hitting a wall. `damage` is how many hits to knock off.
# A normal bullet passes 1. A merged bullet passes its damage.
# Returns the hits still left, and whether the wall is now broken.
# Keys: "hits_remaining" (int), "broken" (bool).
static func hit_wall(hits_remaining: int, damage: int = 1) -> Dictionary:
	var taken := damage
	if taken < 0:
		taken = 0
	var left := hits_remaining - taken
	if left < 0:
		left = 0
	return {
		"hits_remaining": left,
		"broken": left == 0,
	}


# The biggest + offered at this distance. Grows by 1 per tier, then stops.
static func biggest_add(distance: int) -> int:
	var biggest := EARLY_ADD_MAX + tier_for_distance(distance) * ADD_PER_TIER
	if biggest > ADD_MAX:
		return ADD_MAX
	if biggest < 1:
		return 1
	return biggest


# The biggest - offered at this distance.
static func biggest_sub(distance: int) -> int:
	var biggest := EARLY_SUB_MAX + tier_for_distance(distance) * SUB_PER_TIER
	if biggest > SUB_MAX:
		return SUB_MAX
	if biggest < 1:
		return 1
	return biggest


# True only for a rare roll, and only after X2_MIN_TIER.
# x2_roll is any whole number. 0 through 99 are the percent table.
static func is_x2_roll(distance: int, x2_roll: int) -> bool:
	if tier_for_distance(distance) < X2_MIN_TIER:
		return false
	return posmod(x2_roll, 100) < X2_CHANCE_PERCENT


# One good gate. add_pick chooses +1, +2, ... and x2_roll sometimes upgrades it to x2.
static func make_good_gate(distance: int, add_pick: int, x2_roll: int) -> Dictionary:
	if is_x2_roll(distance, x2_roll):
		return {"op": Op.MUL, "amount": MUL_AMOUNT}
	var span := biggest_add(distance)
	var amount := 1 + posmod(add_pick, span)
	return {"op": Op.ADD, "amount": amount}


# One bad gate. Most picks are -N. The /2 result is always one of the choices.
static func make_bad_gate(distance: int, bad_pick: int) -> Dictionary:
	# One extra slot past the subtracts, so /2 shows up regularly but not always.
	var span := biggest_sub(distance) + 1
	var slot := posmod(bad_pick, span)
	if slot == biggest_sub(distance):
		return {"op": Op.DIV, "amount": DIV_AMOUNT}
	return {"op": Op.SUB, "amount": slot + 1}


# One pair. good_on_left picks the side.
# Returns {"left": {op, amount}, "right": {op, amount}}.
static func make_pair(distance: int, good_on_left: bool, good_pick: int, bad_pick: int, x2_roll: int) -> Dictionary:
	var good := make_good_gate(distance, good_pick, x2_roll)
	var bad := make_bad_gate(distance, bad_pick)
	if good_on_left:
		return {"left": good, "right": bad}
	return {"left": bad, "right": good}


# The scene calls this. Tests that need an exact gate call make_pair instead.
static func roll_pair(distance: int) -> Dictionary:
	var good_on_left := randf() < 0.5
	return make_pair(distance, good_on_left, randi(), randi(), randi())


# Where gate pair number pair_index sits, in pixels traveled.
# Pair 0, pair 1, pair 2, ... are exactly GATE_PAIR_SPACING apart.
static func gate_pair_distance(pair_index: int) -> int:
	var index := pair_index
	if index < 0:
		index = 0
	return FIRST_GATE_DISTANCE + index * GATE_PAIR_SPACING


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
