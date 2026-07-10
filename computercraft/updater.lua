local owner = "adexlp37-crypto"
local repository = "minecraft-nations-cc"
local branch = "main"

local baseUrl = ("https://raw.githubusercontent.com/%s/%s/%s/computercraft/")
  :format(owner, repository, branch)

local function download(url)
  local response, err = http.get(url)
  if not response then
    return nil, err or "Unbekannter HTTP-Fehler"
  end

  local body = response.readAll()
  response.close()
  return body
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

for index, filename in ipairs(files) do
  write(("[%d/%d] %s ... "):format(index, #files, filename))
  local contents, err = download(baseUrl .. filename)
  if not contents then
    print("FEHLER")
    error(("Download von %s fehlgeschlagen: %s"):format(filename, err), 0)
  end

  install(filename, contents)
  print("OK")
end

print("Update abgeschlossen.")

