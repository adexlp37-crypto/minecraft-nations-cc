local owner = "adexlp37-crypto"
local repository = "minecraft-nations-cc"
local branch = "main"
local version = "7"

local retiredFiles = {
  "notes.lua", "fieldnav.lua", "hello.lua", "piano.lua", "scanner2.lua",
  "fluid_display.lua", "door_controller.lua", "radar_interface.lua",
  "player_scanner.lua", "fluid_sender.lua", "fluid_tank_monitor.lua",
  "music_stream.lua", "task_manager.lua", "create_stress_monitor.lua",
  "megalovania.lua", "ai_monitor_chatbot.lua", "ai_chatbot.lua",
  "ai_turtle.lua", "ai_turtle_alt.lua", "chat_monitor.lua",
  "discord_player_alert.lua", "hovernav.lua"
}

local packageManifests = {
  all = "manifest.txt",
  alarm = "manifest.txt"
}

local aliases = {
  comparator = "alarm",
  security = "alarm"
}

local cacheBuster = tostring(os.epoch and os.epoch("utc") or os.clock())

local function sortedPackageNames()
  local names = {}
  for name in pairs(packageManifests) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function printHelp()
  print("Minecraft Nations Installer v" .. version)
  print("")
  print("Usage:")
  print("  updater <package>")
  print("  updater <file.lua> [more.lua]")
  print("")
  print("Packages:")
  for _, name in ipairs(sortedPackageNames()) do
    print("  " .. name)
  end
  print("")
  print("Examples:")
  print("  updater alarm")
  print("  updater all")
  print("  updater comparator_alarm.lua")
end

local function download(url, headers)
  local response, err = http.get({
    url = url,
    headers = headers,
    redirect = true
  })
  if not response then
    return nil, err or "Unknown HTTP error"
  end

  local body = response.readAll()
  response.close()
  return body
end

local function latestCommit()
  local apiUrl = ("https://api.github.com/repos/%s/%s/commits/%s?v=%s")
    :format(owner, repository, branch, cacheBuster)
  local body, err = download(apiUrl, {
    ["Accept"] = "application/vnd.github+json",
    ["X-GitHub-Api-Version"] = "2022-11-28",
    ["Cache-Control"] = "no-cache"
  })
  if not body then
    return nil, err
  end

  local data = textutils.unserializeJSON(body)
  if type(data) ~= "table" or type(data.sha) ~= "string" then
    return nil, "Invalid GitHub response"
  end
  return data.sha
end

local function readFile(filename)
  if not fs.exists(filename) or fs.isDir(filename) then
    return nil
  end
  local file = fs.open(filename, "r")
  if not file then
    return nil
  end
  local contents = file.readAll()
  file.close()
  return contents
end

local function install(filename, contents)
  local temporary = filename .. ".download"

  if fs.exists(temporary) then
    fs.delete(temporary)
  end

  local file = assert(fs.open(temporary, "w"))
  file.write(contents)
  file.close()

  if fs.exists(filename) then
    fs.delete(filename)
  end
  fs.move(temporary, filename)
end

local function trim(value)
  return value:match("^%s*(.-)%s*$")
end

local function addUnique(files, seen, filename)
  filename = trim(filename)
  if filename ~= "" and filename:sub(1, 1) ~= "#" and not seen[filename] then
    seen[filename] = true
    files[#files + 1] = filename
  end
end

local function parseManifest(manifest, files, seen)
  for line in manifest:gmatch("[^\r\n]+") do
    addUnique(files, seen, line)
  end
end

local function resolveRequests(args, baseUrl)
  local files = {}
  local seen = {}

  if #args == 0 then
    args = { "alarm" }
  end

  for _, rawRequest in ipairs(args) do
    local request = trim(rawRequest):lower()
    request = aliases[request] or request

    if request == "help" or request == "-h" or request == "--help" then
      printHelp()
      return nil
    end

    local manifestName = packageManifests[request]
    if manifestName then
      print("Loading package: " .. request)
      local manifest, manifestError = download(baseUrl .. manifestName)
      if not manifest then
        error(("Manifest %s could not be loaded: %s"):format(manifestName, manifestError), 0)
      end
      parseManifest(manifest, files, seen)
    else
      addUnique(files, seen, rawRequest)
    end
  end

  if not seen["updater.lua"] then
    table.insert(files, 1, "updater.lua")
  end

  if #files == 0 then
    error("No programs selected.", 0)
  end

  return files
end

print("Minecraft Nations Installer v" .. version)
for _, filename in ipairs(retiredFiles) do
  if fs.exists(filename) then
    fs.delete(filename)
    print("Removed: " .. filename)
  end
end

print("Checking GitHub version...")
local commit, commitError = latestCommit()
if not commit then
  error("Could not check GitHub version: " .. commitError, 0)
end

local baseUrl = ("https://raw.githubusercontent.com/%s/%s/%s/computercraft/")
  :format(owner, repository, commit)

print("Revision: " .. commit:sub(1, 7))
local files = resolveRequests({ ... }, baseUrl)
if not files then
  return
end

local selfUpdated = false
for index, filename in ipairs(files) do
  write(("[%d/%d] %s ... "):format(index, #files, filename))
  local contents, err = download(baseUrl .. filename)
  if not contents then
    print("ERROR")
    error(("Download of %s failed: %s"):format(filename, err), 0)
  end

  if readFile(filename) == contents then
    print("CURRENT")
  else
    install(filename, contents)
    if filename == "updater.lua" then
      selfUpdated = true
    end
    print("OK")
  end
end

print("Install complete.")
if selfUpdated then
  print("Installer was updated. Run your command again to install the selected package.")
end
