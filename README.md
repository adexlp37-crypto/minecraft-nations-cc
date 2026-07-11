# Minecraft Nations - Comparator Alarm

A single CC:Tweaked security alarm. It watches all six redstone inputs and plays
a loud repeating speaker alarm whenever any input reaches analog level 15.

## Installation on a ComputerCraft computer

The GitHub repository must be public and use the `main` branch.

```text
wget https://raw.githubusercontent.com/adexlp37-crypto/minecraft-nations-cc/main/computercraft/updater.lua updater
updater
```

You can also install it explicitly:

```text
updater alarm
```

Run the alarm:

```text
comparator_alarm
```

Place a comparator so its redstone output enters any side of the computer. Attach
a speaker directly to another side or through a wired modem. The alarm stops when
the analog input drops below 15.
