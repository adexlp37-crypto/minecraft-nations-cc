# Minecraft Nations - ComputerCraft

ComputerCraft/CC:Tweaked programs for the Minecraft Nations server.

## Installation on a ComputerCraft computer

The GitHub repository must be public and use the `main` branch.

```text
wget https://raw.githubusercontent.com/adexlp37-crypto/minecraft-nations-cc/main/computercraft/updater.lua updater
updater displays
```

Use the same installer on every computer, then choose what that computer should get:

```text
updater core
updater displays
updater vehicle
updater scanners
updater ai
updater fun
updater all
```

You can also install single programs:

```text
updater hovernav.lua
updater piano.lua create_stress_monitor.lua
```

Run the same command again whenever files on GitHub have changed.

## Packages

- `core`: updater, hello, task manager
- `displays`: monitor/status programs
- `vehicle`: HoverNav and vehicle controls
- `scanners`: radar/player scanner programs
- `ai`: chatbot and turtle AI programs
- `fun`: piano/music programs
- `all`: every ComputerCraft program in this repository

## Adding programs

1. Add the Lua file under `computercraft/`.
2. Add its filename to `computercraft/manifest.txt` and any package manifest that should install it.
3. Push the change to the `main` branch.
4. Run the matching `updater <package>` command in Minecraft.
