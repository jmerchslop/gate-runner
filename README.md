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

The number on the squad is how many runners you have. It starts at 5.

Gates come in pairs. One gate fills the left half of the lane, the other fills the right half. Steer through the one you want:

- `+N` adds that many runners
- `-N` removes that many runners
- `x2` multiplies the squad (x2 turns 5 into 10)

The count never goes below 0. At 0 the run is over.

Some gates are **locked**. They are dull gray and show a hit count under the bonus, like `+10` and `4 hits`. Each bullet that hits the gate lowers that number by 1. At 0 the gate unlocks, turns its real color, and works like a normal gate.

**Locked-gate rule:** running through a gate that is still locked does nothing. You do not get the bonus, you do not take the penalty, and you do not lose a runner just for touching it. Shoot it open first if you want what it says. Bullets pass through gates that are already open.

Red squares are enemies. The number on a square is its health. Bullets lower that health, and at 0 the enemy is gone. If an enemy touches the squad, you lose 1 runner and that enemy disappears. Steer around the ones you do not want to fight.

**Distance** at the top is your score. It climbs the whole time the lane is scrolling.

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

While the game is running, short white dashes are added under **Background** so the center line looks like it is moving. Gates, enemies, and bullets are added under **World**. They are plain shapes made in code. There is no art to import.

### Which script does what

- `scripts/lane_rules.gd` holds the rules and the tuning numbers. It knows how `+`, `-`, and `x` change the squad, how a lock counts down, and what an enemy does to health and to the squad. It does not draw anything, and it does not read the keyboard.
- `scripts/main.gd` is the scene. It moves the squad, scrolls the lane, spawns gates and enemies, checks when shapes touch, and updates the words on screen. When a rule matters, it asks `lane_rules.gd` and uses the answer.
- `tests/run_tests.gd` calls those rules with sample numbers and prints PASS or FAIL.

## Tweak the game

Open `scripts/lane_rules.gd`. The numbers near the top have a short note each. Easy things to try:

- `STARTING_SQUAD` — runners at the start
- `SCROLL_SPEED` — how fast the lane comes at you
- `FIRE_EVERY_SECONDS` — time between shots (smaller is faster)
- `DEFAULT_LOCK_HITS` — bullets needed to open a locked gate
- `ADD_AMOUNTS`, `SUB_AMOUNTS`, `MUL_AMOUNTS` — the gate labels

Save the file and press Play again. You do not need to change `main.gd` to retune the game.

## Run the checks

From this folder, if the `godot` command is Godot 4:

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

The last line should say `ALL TESTS PASSED`.

The first time you open the project, Godot creates a `.godot` folder next to these files. That folder is a local cache. It is listed in `.gitignore`, so it does not need to be committed.
