# Gate Runner

A tiny Godot 4 game in the style of those fake mobile ads. Your squad runs forward on its own. You only steer left and right. Gates and enemies come down the lane toward you.

You do not need to know much about Godot. Open the project, press Play, and it starts.

## Play

1. Install [Godot 4.7](https://godotengine.org/download/archive/4.7.2-stable/) or a newer Godot 4. This project was checked with Godot 4.7.2.
2. Open Godot, choose **Import**, and pick the `project.godot` file in this folder.
3. Press **F5**, or the **Play** button at the top right.
4. Click the game window once, so the keyboard controls reach the game.

The window is tall and narrow (540 by 960) on purpose, like a phone held upright.

### Controls

- **A / D** or the **left and right arrow keys** steer the squad.
- **Hold the left mouse button and drag** to steer. A finger drag does the same thing on a phone.
- The squad shoots upward by itself. You do not press a fire button.
- When you lose, **press any key** to start again.

### How a run works

The number on the squad is how many runners you have. It starts at 5, in the right lane, and never goes above 24.

Gates come in pairs, always the same distance apart. One gate fills the left half of the lane, the other fills the right half. One side is always good and the other is always bad. Which side is which changes every pair.

- `+N` adds that many runners. Early on this is only +1, +2, or +3.
- `x2` doubles the squad. It does not show up at the start.
- `-N` removes that many runners.
- `/2` keeps half the squad, rounded down. 5 becomes 2. 1 becomes 0.

The count never goes below 0. At 0 the run is over.

Some gates are **locked**. They are dull gray and show a hit count under the label, like `+2` and `12 hits`. Bullets lower that number. A bigger squad lowers it faster, because more runners means more shots. At 0 the gate unlocks, turns its real color, and works like a normal gate.

**Locked-gate rule:** running through a gate that is still locked does nothing. You do not get the bonus, you do not take the penalty, and you do not lose a runner just for touching it. Shoot it open first if you want what it says. Bullets pass through gates that are already open.

The squad shoots a row of bullets by itself. One runner is one bullet. With 8 or fewer runners you see that many bullets, side by side. With more than 8, you still see 8 bullets, but the extra runners are merged into them, so some bullets are thicker and hit harder. The damages in one volley add up to the squad count.

Red bars are enemies. Each bar fills one whole half of the road, and it sits in the gap between gate pairs so it does not cover a gate. The number on the bar is its health. Health and the hit they deal both climb as the distance goes up. The other half of the road is empty, so you can always change lanes to go around. If you stay in the enemy's lane, shoot it down before it reaches you. Touching it removes several runners.

**Distance** at the top is your score. It climbs the whole time the lane is scrolling. Gate bonuses, enemy health, and how hard a touch hurts all grow slowly with that distance.

Your squad's center decides which gate you took, and which lane an enemy can hit you in. The exact middle line counts as the right-hand lane.

## Project layout

```
project.godot          window size, game name, and which scene plays first
scenes/main.tscn       the only scene
scripts/lane_rules.gd  the math, and the numbers you can tune
scripts/main.gd        keys, movement, spawning, and the score display
tests/run_tests.gd     checks the math without opening a window
```

Godot also keeps a tiny `.uid` file next to each script. Leave those in place. They are just ids so the editor can find the file if it moves.

### Scene tree

```
Main (Node2D) — scripts/main.gd
├── Background (Node2D)
│   ├── Road (Polygon2D)
│   ├── LeftEdge (Polygon2D)
│   └── RightEdge (Polygon2D)
├── World (Node2D)
├── Squad (Node2D)
│   ├── Body (Polygon2D)
│   └── CountLabel (Label)
├── HUD (CanvasLayer)
│   ├── ScoreLabel (Label)
│   └── HintLabel (Label)
└── GameOver (CanvasLayer) — hidden until the squad count hits 0
    ├── Dimmer (ColorRect)
    ├── Title (Label)
    ├── FinalScore (Label)
    └── RestartHint (Label)
```

While the game is running, short white dashes are added under **Background** so the center line looks like it is moving. Gates, enemies, and bullets are added under **World**. They are plain shapes made in code. There is no art to import.

### Which script does what

- `scripts/lane_rules.gd` holds the rules and the tuning numbers. It knows how `+`, `-`, `x`, and `/` change the squad, how a lock counts down, how many bullets a squad fires, how gate values and enemy strength grow with distance, and where each gate pair and enemy sits on the road. It does not draw anything, and it does not read the keyboard.
- `scripts/main.gd` is the scene. It moves the squad, scrolls the lane, spawns gates and enemies, checks when shapes touch, and updates the words on screen. When a rule matters, it asks `lane_rules.gd` and uses the answer.
- `tests/run_tests.gd` calls those rules with sample numbers and prints PASS or FAIL.

## Tweak the game

Open `scripts/lane_rules.gd`. The numbers near the top have a short note each. Easy things to try:

- `STARTING_SQUAD` — runners at the start
- `MAX_SQUAD` — the biggest the squad number can get
- `GATE_PAIR_SPACING` — pixels of travel between gate pairs
- `SCROLL_SPEED` — how fast the lane comes at you
- `FIRE_EVERY_SECONDS` — time between volleys (smaller is faster)
- `MAX_VISIBLE_BULLETS` — most bullets drawn in one volley
- `LOCK_HITS_BASE` — hits a locked gate needs at the start
- `EARLY_ADD_MAX` — biggest `+` gate at the start

Save the file and press Play again. You do not need to change `main.gd` to retune the game.

## Run the checks

From this folder, if the `godot` command is Godot 4:

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

The last line should say `ALL TESTS PASSED`.

The first time you open the project, Godot creates a `.godot` folder next to these files. That folder is a local cache. It is listed in `.gitignore`, so it does not need to be committed.
