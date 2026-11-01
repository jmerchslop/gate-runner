# Crowd Run

A tiny Godot 4 game in the style of those fake mobile ads. A blue crowd runs down a straight bridge. You only swerve left and right. Gates, tire stacks, and red soldiers come toward you.

This is the core run only. Weapons, bosses, coins, the shop, quests, and a level menu are the next steps. They are not in this version.

You do not need to know much about Godot. Open the project, press Play, and it starts.

## Play

1. Install [Godot 4.7](https://godotengine.org/download/archive/4.7.2-stable/) or a newer Godot 4. This project was checked with Godot 4.7.2.
2. Open Godot, choose **Import**, and pick the `project.godot` file in this folder.
3. Press **F5**, or the **Play** button at the top right.
4. Click the game window once, so the keyboard controls reach the game.

The window is tall and narrow (540 by 960), like a phone held upright.

### Controls

- **Hold the left mouse button and drag** to swerve. The crowd follows your finger from where you pressed.
- **A / D** or the **arrow keys** also slide the crowd.
- The crowd runs forward and shoots by itself.
- When you lose, **press any key** to start again.

### How a run works

You start as **1** blue soldier. The number floating over the crowd is how many you have. There is no maximum. At 0 the run is over.

The bridge has no lanes. You can stand anywhere between the rails. The camera stays centered so you always see the full width.

Gates come in pairs, always the same distance apart. One is good (blue) and one is bad (red). Your crowd's center picks the side. The exact middle counts as the right-hand gate.

- `+N` adds that many soldiers. Early on this is only +1 or +2, and it climbs slowly.
- `x2` doubles the crowd. About 4 percent of good gates, and only after you have run for a bit.
- `-N` removes that many soldiers. These grow, so they stay a threat.
- `/2` keeps half the crowd, rounded down. 5 becomes 2. 1 becomes 0.

Shooting a gate does nothing. You just drive through it. A green `+N` or a red `-N` pops up when you do.

**Black tire stacks** block part of the road. The red number is their health. Bullets lower it. **Tire rule:** if you touch a stack that still has health, you lose that many soldiers and the stack breaks. Shooting it down to 0 first means you pass for free. You can also swerve around it.

**Red soldiers** stand still in a group. Shoot them before you arrive. **Crash rule:** the moment you touch a group, each living enemy takes one of your soldiers with them. One for one, a single time.

**Distance** at the top is how far you have run. Tire health follows a slow-then-steep-then-flat curve, and the game tries to place a stack your current firepower can actually break before you reach it.

Every soldier adds to the damage, even when the crowd is huge. See the note in `scripts/main.gd` about the soldier and bullet caps.

## Project layout

```
project.godot         window size, and which scene plays first
scenes/main.tscn      the only scene
scripts/run_rules.gd  the math, and the numbers you can tune
scripts/main.gd       the bridge, the crowd, the shooting, and the HUD
tests/run_tests.gd    checks the math without opening a window
```

Godot also keeps a tiny `.uid` file next to each script. Leave those in place.

### Scene tree

What you see in the editor:

```
Main (Node3D) — scripts/main.gd
├── World (Node3D)
├── Camera3D
├── HUD (CanvasLayer)
│   ├── DistanceLabel
│   └── HintLabel
└── GameOver (CanvasLayer) — hidden until the crowd is gone
    ├── Dimmer
    ├── Title
    ├── FinalScore
    └── RestartHint
```

While the game runs, the script also builds:

```
World
├── Water
├── Crowd
│   ├── Bodies (MultiMeshInstance3D)
│   └── Heads (MultiMeshInstance3D)
├── Bullets (MultiMeshInstance3D)
├── CountLabel (Label3D)
└── Chunks
    └── Chunk0, Chunk1, ...
        ├── road, dashes, rails
        ├── Tires or Enemies
        ├── GateLeft
        └── GateRight
```

### Which script does what

- `scripts/run_rules.gd` holds the tuning numbers and the math. Gates, crashes, the S-curve for tire health, damage per second, which tire stack is safe, and where each soldier stands in the blob. It does not draw anything.
- `scripts/main.gd` is the scene. It moves the crowd, builds the bridge, shoots, and shows the words. When a rule matters, it asks `run_rules.gd`.
- `tests/run_tests.gd` calls those rules and prints PASS or FAIL.

## Tweak the game

Open `scripts/run_rules.gd`. The numbers near the top have a short note each. Easy things to try:

- `RUN_SPEED` — how fast the bridge comes at you
- `FIRE_EVERY_SECONDS` — time between shots
- `EARLY_ADD_MAX` — biggest `+` gate at the start
- `X2_CHANCE_PERCENT` — how often a good gate is `x2`
- `HP_MIN` and `HP_MAX` — tire health at the start and at the end of the curve
- `CHUNK_LENGTH` — distance from one gate pair to the next

Save the file and press Play again.

## Run the checks

From this folder, if the `godot` command is Godot 4:

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

The last line should say `ALL TESTS PASSED`.

The first time you open the project, Godot creates a `.godot` folder. That folder is a local cache. It is listed in `.gitignore`.
