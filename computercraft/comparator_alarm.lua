local sides = { "left", "right", "front", "back", "top", "bottom" }
local alarmLevel = 15
local alarmSound = "minecraft:entity.ender_dragon.growl"
local alarmVolume = 3
local alarmPitch = 1
local repeatDelay = 1.5

local speaker = peripheral.find("speaker")
if not speaker then
  error("No speaker found. Attach a speaker directly or through a wired modem.", 0)
end

local function findTriggeredSides()
  local triggered = {}
  for _, side in ipairs(sides) do
    if redstone.getAnalogInput(side) == alarmLevel then
      triggered[#triggered + 1] = side
    end
  end
  return triggered
end

local function clearScreen()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
end

local function showStatus(active, triggered)
  clearScreen()
  term.setTextColor(active and colors.red or colors.green)
  print(active and "!!! COMPARATOR ALARM !!!" or "COMPARATOR ALARM ARMED")
  term.setTextColor(colors.white)
  print("")
  print("Trigger level: 15")
  print("Watching all six sides")
  print("Speaker: connected")
  print("")
  if active then
    term.setTextColor(colors.yellow)
    print("Signal 15 on: " .. table.concat(triggered, ", "))
    print("Alarm remains active until signal drops.")
  else
    term.setTextColor(colors.lightGray)
    print("Waiting for redstone level 15...")
  end
end

local alarmActive = false
showStatus(false, {})

while true do
  local triggered = findTriggeredSides()
  local active = #triggered > 0

  if active then
    if not alarmActive then
      alarmActive = true
      showStatus(true, triggered)
    end
    speaker.playSound(alarmSound, alarmVolume, alarmPitch)
    os.sleep(repeatDelay)
  else
    if alarmActive then
      alarmActive = false
      speaker.stop()
      showStatus(false, {})
    end
    os.pullEvent("redstone")
  end
end
