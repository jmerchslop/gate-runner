# Gate Runner

A tiny Godot 4 game in the style of those fake mobile ads. Your squad runs forward on its own. You only steer left and right. Gates come down the lane toward you, each one behind a wall you have to shoot open.

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

The number on the squad is how many runners you have. It starts at 5, in the right lane. There is no maximum. The count never goes below 0, and at 0 the run is over.

Gates come in pairs, always the same distance apart. One gate fills the left half of the lane, the other fills the right half. One side is always good and the other is always bad. Which side is which changes every pair.

- `+N` adds that many runners. Early on this is only +1 or +2, and it climbs slowly from there.
- `x2` doubles the squad. It is rare (about 4 percent of good gates) and it does not show up at the start.
- `-N` removes that many runners. These grow as the run goes on, so they stay a threat.
- `/2` keeps half the squad, rounded down. 5 becomes 2. 1 becomes 0.

Every gate has a gray **wall** on the side facing you. The number on the wall is how many hits are left. Bullets lower that number. A bigger squad lowers it faster, because more runners means more shots. At 0 the wall disappears and the gate behind it can affect you. Later walls start with more hits.

**Wall rule:** if you run into a wall that still has hits left, you do not get the gate. You lose one runner for each hit still showing. Shooting the wall first makes that cheaper. Breaking it all the way to 0 lets the gate through and costs nothing extra. Bullets are counted before you touch the wall, so a wall that breaks as you arrive still counts as open.

The squad shoots a row of bullets by itself. One runner is one bullet. With 8 or fewer runners you see that many bullets, side by side. With more than 8, you still see 8 bullets, but the extra runners are merged into them, so some bullets are thicker and hit harder. The damages in one volley add up to the squad count.

**Distance** at the top is your score. It climbs the whole time the lane is scrolling. Gate values and wall hits grow slowly with that distance.

Your squad's center decides which gate you took. The exact middle line counts as the right-hand gate, so you cannot score both gates of a pair at the same point.

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

While the game is running, short white dashes are added under **Background** so the center line looks like it is moving. Gates, their walls, and bullets are added under **World**. They are plain shapes made in code. There is no art to import.

### Which script does what

- `scripts/lane_rules.gd` holds the rules and the tuning numbers. It knows how `+`, `-`, `x`, and `/` change the squad, what a wall crash costs, how many bullets a squad fires, how gate values and wall hits grow with distance, and where each gate pair sits. It does not draw anything, and it does not read the keyboard.
- `scripts/main.gd` is the scene. It moves the squad, scrolls the lane, spawns gates and walls, checks when shapes touch, and updates the words on screen. When a rule matters, it asks `lane_rules.gd` and uses the answer.
- `tests/run_tests.gd` calls those rules with sample numbers and prints PASS or FAIL.

## Tweak the game

Open `scripts/lane_rules.gd`. The numbers near the top have a short note each. Easy things to try:

- `STARTING_SQUAD` — runners at the start
- `GATE_PAIR_SPACING` — pixels of travel between gate pairs
- `SCROLL_SPEED` — how fast the lane comes at you
- `FIRE_EVERY_SECONDS` — time between volleys (smaller is faster)
- `MAX_VISIBLE_BULLETS` — most bullets drawn in one volley
- `WALL_HITS_BASE` — hits a wall needs at the start
- `EARLY_ADD_MAX` — biggest `+` gate at the start
- `X2_CHANCE_PERCENT` — how often a good gate is `x2`, out of 100

Save the file and press Play again. You do not need to change `main.gd` to retune the game.

## Run the checks

From this folder, if the `godot` command is Godot 4:

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

The last line should say `ALL TESTS PASSED`.

The first time you open the project, Godot creates a `.godot` folder next to these files. That folder is a local cache. It is listed in `.gitignore`, so it does not need to be committed.
