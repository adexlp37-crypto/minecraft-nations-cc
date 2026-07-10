local owner = "adexlp37-crypto"
local repository = "minecraft-nations-cc"
local branch = "main"
local version = "5"
local retiredFiles = { "notes.lua", "fieldnav.lua" }

local cacheBuster = tostring(os.epoch and os.epoch("utc") or os.clock())

local function download(url, headers)
  local response, err = http.get({
    url = url,
    headers = headers,
    redirect = true
  })
  if not response then
    return nil, err or "Unbekannter HTTP-Fehler"
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
    return nil, "Ungueltige Antwort von GitHub"
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

print("Minecraft Nations Updater v" .. version)
for _, filename in ipairs(retiredFiles) do
  if fs.exists(filename) then
    fs.delete(filename)
    print("Entfernt: " .. filename)
  end
end
print("Pruefe GitHub-Version...")
local commit, commitError = latestCommit()
if not commit then
  error("GitHub-Version konnte nicht ermittelt werden: " .. commitError, 0)
end

local baseUrl = ("https://raw.githubusercontent.com/%s/%s/%s/computercraft/")
  :format(owner, repository, commit)

print("Stand: " .. commit:sub(1, 7))
print("Lade Manifest...")
local manifest, manifestError = download(baseUrl .. "manifest.txt")
if not manifest then
  error("Manifest konnte nicht geladen werden: " .. manifestError, 0)
end

local files = {}
for line in manifest:gmatch("[^\r\n]+") do
  local filename = line:match("^%s*(.-)%s*$")
  if filename ~= "" and filename:sub(1, 1) ~= "#" then
    files[#files + 1] = filename
  end
end

if #files == 0 then
  error("Das Manifest enthaelt keine Programme.", 0)
end

local selfUpdated = false
for index, filename in ipairs(files) do
  write(("[%d/%d] %s ... "):format(index, #files, filename))
  local contents, err = download(baseUrl .. filename)
  if not contents then
    print("FEHLER")
    error(("Download von %s fehlgeschlagen: %s"):format(filename, err), 0)
  end

  if readFile(filename) == contents then
    print("AKTUELL")
  else
    install(filename, contents)
    if filename == "updater.lua" then
      selfUpdated = true
    end
    print("OK")
  end
end

print("Update abgeschlossen.")
if selfUpdated then
  print("Updater wurde erneuert - starte automatisch neu.")
  sleep(0.5)
  shell.run("updater")
end
