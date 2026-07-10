local dataFile = ".notes.db"

local function clear()
  term.clear()
  term.setCursorPos(1, 1)
end

local function pause()
  print()
  write("Enter zum Fortfahren...")
  read()
end

local function loadNotes()
  if not fs.exists(dataFile) then
    return {}
  end

  local file = fs.open(dataFile, "r")
  if not file then
    return {}
  end

  local contents = file.readAll()
  file.close()

  local notes = textutils.unserialize(contents)
  if type(notes) ~= "table" then
    return {}
  end
  return notes
end

local function saveNotes(notes)
  local temporary = dataFile .. ".tmp"
  local file = assert(fs.open(temporary, "w"))
  file.write(textutils.serialize(notes))
  file.close()

  if fs.exists(dataFile) then
    fs.delete(dataFile)
  end
  fs.move(temporary, dataFile)
end

local function printSummary(notes)
  if #notes == 0 then
    print("Noch keine Notizen vorhanden.")
    return
  end

  for index, note in ipairs(notes) do
    print(("%d. %s"):format(index, note.title))
  end
end

local function addNote(notes)
  clear()
  print("Neue Notiz")
  print("----------")
  write("Titel: ")
  local title = read()
  if title == "" then
    print("Abgebrochen: Titel darf nicht leer sein.")
    pause()
    return
  end

  print("Text eingeben. Eine einzelne Zeile mit . beendet die Eingabe.")
  local lines = {}
  while true do
    write("> ")
    local line = read()
    if line == "." then
      break
    end
    lines[#lines + 1] = line
  end

  notes[#notes + 1] = {
    title = title,
    body = table.concat(lines, "\n"),
    created = os.epoch and os.epoch("utc") or os.clock()
  }
  saveNotes(notes)
  print("Notiz gespeichert.")
  pause()
end

local function viewNote(notes)
  clear()
  print("Notizen")
  print("-------")
  printSummary(notes)
  if #notes == 0 then
    pause()
    return
  end

  write("\nNummer: ")
  local index = tonumber(read())
  local note = index and notes[index]
  if not note then
    print("Ungueltige Nummer.")
    pause()
    return
  end

  clear()
  print(note.title)
  print(string.rep("-", math.min(#note.title, 30)))
  print(note.body ~= "" and note.body or "(Kein Text)")
  pause()
end

local function searchNotes(notes)
  clear()
  write("Suchbegriff: ")
  local query = read():lower()
  print()

  local found = 0
  for index, note in ipairs(notes) do
    if note.title:lower():find(query, 1, true)
      or note.body:lower():find(query, 1, true) then
      print(("%d. %s"):format(index, note.title))
      found = found + 1
    end
  end

  if found == 0 then
    print("Keine Treffer.")
  end
  pause()
end

local function deleteNote(notes)
  clear()
  print("Notiz loeschen")
  print("--------------")
  printSummary(notes)
  if #notes == 0 then
    pause()
    return
  end

  write("\nNummer: ")
  local index = tonumber(read())
  local note = index and notes[index]
  if not note then
    print("Ungueltige Nummer.")
    pause()
    return
  end

  write(('"%s" wirklich loeschen? (j/N): '):format(note.title))
  if read():lower() == "j" then
    table.remove(notes, index)
    saveNotes(notes)
    print("Notiz geloescht.")
  else
    print("Abgebrochen.")
  end
  pause()
end

local notes = loadNotes()

while true do
  clear()
  print("Notizen")
  print("=======")
  print(("Gespeichert: %d\n"):format(#notes))
  print("1 - Neue Notiz")
  print("2 - Notizen anzeigen")
  print("3 - Suchen")
  print("4 - Notiz loeschen")
  print("5 - Beenden")
  write("\nAuswahl: ")

  local choice = read()
  if choice == "1" then
    addNote(notes)
  elseif choice == "2" then
    viewNote(notes)
  elseif choice == "3" then
    searchNotes(notes)
  elseif choice == "4" then
    deleteNote(notes)
  elseif choice == "5" then
    clear()
    print("Bis bald.")
    return
  end
end
