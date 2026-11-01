extends RefCounted

# The rule book for the crowd run. This is not a scene node.
# It only does math, so tests/run_tests.gd can check it without drawing the game.
#
# Gate pair: one good gate and one bad gate, side by side.
# Good is +N, or rarely x2. Bad is -N or /2.
# The squad count never goes below 0. There is no maximum.
#
# Tire crash: if you touch a stack that still has HP, you lose that many
# soldiers and the stack breaks. Shooting it to 0 first means you pass for free.
#
# Enemy crash: each living enemy takes one soldier with them, once, when you
# touch the group. Soldiers and enemies both lose the same number.

# ----------------------------------------------------------------
# Tuning numbers. Change these to make the run easier or harder.
# Distances are in world units along the bridge. The crowd runs at RUN_SPEED.
# ----------------------------------------------------------------

# Soldiers at the start of a run.
const STARTING_SOLDIERS := 1

# The crowd cannot go under this. 0 ends the run.
const MIN_SOLDIERS := 0

# Damage one soldier adds to each volley.
const BULLET_DAMAGE := 1

# Seconds between volleys. Smaller means the crowd shoots faster.
const FIRE_EVERY_SECONDS := 0.15

# How many bullet streaks we actually draw in one volley.
# 1 to this many soldiers fire one bullet each.
# Above this, we still draw only this many bullets and share the extra
# damage across them. 40 soldiers with a cap of 16 still deal 40 damage
# per volley. That is what keeps a huge crowd from spawning a bullet each.
const MAX_BULLETS_PER_VOLLEY := 16

# Slots in the bullet pool. A volley is 16 bullets and they live about a second,
# so 120 slots is enough that a new volley always finds a free slot.
const BULLET_POOL := 120

# How many soldier bodies we draw. Extra soldiers still count for damage
# and for the number over the crowd. They share the same blob.
const VISIBLE_SOLDIERS := 48

# How fast the crowd runs forward.
const RUN_SPEED := 8.0

# How fast A and D slide the crowd sideways.
const STRAFE_SPEED := 7.0

# Length of one road chunk. Gate pairs sit one of these apart. Never random.
const CHUNK_LENGTH := 28

# Where the hazard and the gate pair sit inside a chunk, measured from the chunk start.
const HAZARD_OFFSET := 10
const GATE_OFFSET := 20

# How far apart soldiers stand in the blob.
const FORMATION_GAP := 0.42

# Gate values step up with distance. One tier is this many units of road.
# At RUN_SPEED 8, a tier is about 5 seconds. Adds climb by 1, then stop.
const TIER_DISTANCE := 40.0
const MAX_TIER := 8

# Opening good gates are only +1 and +2. Later tiers add 1, up to ADD_MAX.
const EARLY_ADD_MAX := 2
const ADD_PER_TIER := 1
const ADD_MAX := 4

# x2 is this many good gates out of 100, and only after X2_MIN_TIER.
# 4 means about 4 percent. It is named so you can change how rare it is.
const X2_CHANCE_PERCENT := 4
const X2_MIN_TIER := 3
const MUL_AMOUNT := 2

# Opening bad gates are -1, -2, and /2. The minus grows so it stays a threat.
const EARLY_SUB_MAX := 2
const SUB_PER_TIER := 1
const SUB_MAX := 5
const DIV_AMOUNT := 2

# Tire HP follows an S-curve from HP_MIN up to HP_MAX.
# CURVE_DISTANCE is how far down the road the curve takes to finish.
# CURVE_STEEPNESS controls how sharp the middle climb is. 8 is a clear S.
const HP_MIN := 4
const HP_MAX := 64
const CURVE_DISTANCE := 280.0
const CURVE_STEEPNESS := 8.0

# Each red soldier takes this many damage to remove.
const ENEMY_HP := 2

# How many red soldiers stand in a group. Grows slowly, then stops.
const ENEMY_GROUP_BASE := 3
const ENEMY_GROUP_PER_TIER := 1
const ENEMY_GROUP_MAX := 12

# ADD is +N, SUB is -N, MUL is xN, DIV is /N.
enum Op { ADD, SUB, MUL, DIV }


# ----------------------------------------------------------------
# Rules.
# ----------------------------------------------------------------

static func clamp_soldiers(count: int) -> int:
	if count < MIN_SOLDIERS:
		return MIN_SOLDIERS
	return count


# Apply a gate whose text the crowd actually walked through.
static func apply_gate(count: int, op: int, amount: int) -> int:
	var next := count
	if op == Op.ADD:
		next = count + amount
	elif op == Op.SUB:
		next = count - amount
	elif op == Op.MUL:
		next = count * amount
	elif op == Op.DIV:
		next = divide_soldiers(count, amount)
	return clamp_soldiers(next)


# /2 keeps one share. 5 becomes 2. 1 becomes 0.
static func divide_soldiers(count: int, parts: int) -> int:
	if parts <= 1:
		return count
	var share := 0
	var left := count
	while left >= parts:
		left -= parts
		share += 1
	return share


static func is_game_over(count: int) -> bool:
	return count <= MIN_SOLDIERS


static func is_good_op(op: int) -> bool:
	return op == Op.ADD or op == Op.MUL


static func is_bad_op(op: int) -> bool:
	return op == Op.SUB or op == Op.DIV


static func tier_for_distance(distance: float) -> int:
	var left := distance
	if left < 0.0:
		left = 0.0
	var tier := 0
	while tier < MAX_TIER and left >= TIER_DISTANCE:
		left -= TIER_DISTANCE
		tier += 1
	return tier


static func biggest_add(distance: float) -> int:
	var biggest := EARLY_ADD_MAX + tier_for_distance(distance) * ADD_PER_TIER
	if biggest > ADD_MAX:
		return ADD_MAX
	if biggest < 1:
		return 1
	return biggest


static func biggest_sub(distance: float) -> int:
	var biggest := EARLY_SUB_MAX + tier_for_distance(distance) * SUB_PER_TIER
	if biggest > SUB_MAX:
		return SUB_MAX
	if biggest < 1:
		return 1
	return biggest


# x2_roll is any whole number. 0 through 99 are the percent table.
static func is_x2_roll(distance: float, x2_roll: int) -> bool:
	if tier_for_distance(distance) < X2_MIN_TIER:
		return false
	return posmod(x2_roll, 100) < X2_CHANCE_PERCENT


static func make_good_gate(distance: float, add_pick: int, x2_roll: int) -> Dictionary:
	if is_x2_roll(distance, x2_roll):
		return {"op": Op.MUL, "amount": MUL_AMOUNT}
	var span := biggest_add(distance)
	return {"op": Op.ADD, "amount": 1 + posmod(add_pick, span)}


static func make_bad_gate(distance: float, bad_pick: int) -> Dictionary:
	# One extra slot past the minuses, so /2 shows up often but not every time.
	var span := biggest_sub(distance) + 1
	var slot := posmod(bad_pick, span)
	if slot == biggest_sub(distance):
		return {"op": Op.DIV, "amount": DIV_AMOUNT}
	return {"op": Op.SUB, "amount": slot + 1}


# good_on_left picks the side. Returns left and right gate dictionaries.
static func make_pair(distance: float, good_on_left: bool, good_pick: int, bad_pick: int, x2_roll: int) -> Dictionary:
	var good := make_good_gate(distance, good_pick, x2_roll)
	var bad := make_bad_gate(distance, bad_pick)
	if good_on_left:
		return {"left": good, "right": bad}
	return {"left": bad, "right": good}


static func roll_pair(distance: float) -> Dictionary:
	var good_on_left := randf() < 0.5
	return make_pair(distance, good_on_left, randi(), randi(), randi())


# World Z where chunk number index begins.
static func chunk_origin(index: int) -> int:
	var n := index
	if n < 0:
		n = 0
	return n * CHUNK_LENGTH


# World Z of that chunk's gate pair. Pairs are exactly CHUNK_LENGTH apart.
static func gate_distance(index: int) -> int:
	return chunk_origin(index) + GATE_OFFSET


static func hazard_distance(index: int) -> int:
	return chunk_origin(index) + HAZARD_OFFSET


# Damage per second if every shot lands.
# soldiers x shots per second x damage per shot.
static func dps(soldiers: int, shot_rate: float, damage_per_shot: int) -> float:
	var crowd := soldiers
	if crowd < 0:
		crowd = 0
	var rate := shot_rate
	if rate < 0.0:
		rate = 0.0
	var hit := damage_per_shot
	if hit < 0:
		hit = 0
	return float(crowd) * rate * float(hit)


static func shots_per_second() -> float:
	if FIRE_EVERY_SECONDS <= 0.0:
		return 0.0
	return 1.0 / FIRE_EVERY_SECONDS


# Smooth S from 0 to 1. Slow, then steep, then flat.
static func s_curve(distance: float) -> float:
	var span := CURVE_DISTANCE
	if span <= 0.0:
		return 1.0
	var t := distance / span
	if t < 0.0:
		t = 0.0
	if t > 1.0:
		t = 1.0
	var raw := _logistic(t)
	var start := _logistic(0.0)
	var finish := _logistic(1.0)
	var width := finish - start
	if width <= 0.001:
		return t
	return (raw - start) / width


static func _logistic(t: float) -> float:
	return 1.0 / (1.0 + exp(-CURVE_STEEPNESS * (t - 0.5)))


# Tire HP at this distance. Starts near HP_MIN, climbs, then sits on HP_MAX.
static func obstacle_hp(distance: float) -> int:
	var mix := s_curve(distance)
	var value := float(HP_MIN) + float(HP_MAX - HP_MIN) * mix
	var hp := int(value)
	if value - float(hp) >= 0.5:
		hp += 1
	if hp < 1:
		return 1
	return hp


# Three tire stacks around the curve: an easy one, the normal one, and a harder one.
static func obstacle_choices(distance: float) -> Array:
	var base := obstacle_hp(distance)
	var easy := int(float(base) * 0.5)
	if easy < 1:
		easy = 1
	var hard := int(float(base) * 1.5)
	if hard < base:
		hard = base
	return [
		{"id": "easy", "hp": easy},
		{"id": "normal", "hp": base},
		{"id": "hard", "hp": hard},
	]


# Pick the toughest stack the crowd can still break before they reach it.
# time_available is seconds until the crowd arrives.
# If one of the options is safe, the result is never an unsafe one.
# If every option is too strong, we pick the weakest so the hit is as fair as it can be.
static func choose_obstacle(options: Array, soldier_dps: float, time_available: float) -> Dictionary:
	var budget := soldier_dps * time_available
	if budget < 0.0:
		budget = 0.0
	var best_hp := -1
	var best := {}
	var worst_hp := -1
	var easiest := {}
	for option in options:
		var spec: Dictionary = option
		var hp := int(spec["hp"])
		if worst_hp < 0 or hp < worst_hp:
			worst_hp = hp
			easiest = spec
		if float(hp) <= budget and hp > best_hp:
			best_hp = hp
			best = spec
	if best_hp >= 0:
		return {"id": best["id"], "hp": int(best["hp"])}
	return {"id": easiest["id"], "hp": int(easiest["hp"])}


# Touching a live tire stack. You lose `hp_left` soldiers and the stack is gone.
static func tire_crash(soldiers: int, hp_left: int) -> Dictionary:
	if hp_left <= 0:
		return {"soldiers": clamp_soldiers(soldiers), "hp_left": 0}
	return {"soldiers": clamp_soldiers(soldiers - hp_left), "hp_left": 0}


# Touching a group of red soldiers. One of yours for one of theirs.
static func enemy_trade(soldiers: int, enemies: int) -> Dictionary:
	var traded := soldiers
	if enemies < traded:
		traded = enemies
	if traded < 0:
		traded = 0
	return {"soldiers": soldiers - traded, "enemies": enemies - traded}


static func enemy_group_size(distance: float) -> int:
	var size := ENEMY_GROUP_BASE + tier_for_distance(distance) * ENEMY_GROUP_PER_TIER
	if size > ENEMY_GROUP_MAX:
		return ENEMY_GROUP_MAX
	if size < 1:
		return 1
	return size


# Where each soldier stands, relative to the crowd center.
# x is sideways, y in the Vector2 is forward (world Z).
# Spot 0 is the center. Then rings of 6, 12, 18... so the blob stays round.
static func formation_offsets(count: int) -> Array:
	var spots: Array = []
	if count <= 0:
		return spots
	spots.append(Vector2.ZERO)
	var placed := 1
	var ring := 1
	while placed < count:
		var around := 6 * ring
		var radius := FORMATION_GAP * float(ring)
		var step := 0
		while step < around and placed < count:
			var angle := TAU * float(step) / float(around)
			spots.append(Vector2(cos(angle), sin(angle)) * radius)
			placed += 1
			step += 1
		ring += 1
	return spots


# Damages for the visible bullets in one volley. They add up to soldiers * BULLET_DAMAGE.
static func volley_damages(soldiers: int) -> Array:
	var crowd := soldiers
	if crowd < 0:
		crowd = 0
	var visible := crowd
	if visible > MAX_BULLETS_PER_VOLLEY:
		visible = MAX_BULLETS_PER_VOLLEY
	var damages: Array = []
	if visible == 0:
		return damages
	var fill := 0
	while fill < visible:
		damages.append(0)
		fill += 1
	var left := crowd * BULLET_DAMAGE
	var index := 0
	while left > 0:
		damages[index] = int(damages[index]) + 1
		left -= 1
		index += 1
		if index >= visible:
			index = 0
	return damages


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
