-- CONFIGURATION
local url = "https://soundcloud.com/jgcmarins/relaxing-japanese-music-zen-music-with-traditional-flute-koto-shamisen?utm_source=clipboard&utm_medium=text&utm_campaign=social_sharing" 

-- Speaker suchen
local speaker = peripheral.find("speaker")
if not speaker then
    error("Error: Kein Speaker-Block gefunden!")
end

print("Verbinde mit Audio-Stream...")
local response = http.get(url, nil, true) -- 'true' ist wichtig für Binärdaten (Audio)

if not response then
    error("Error: Konnte keine Verbindung zum Audio-Link herstellen.")
end

print("Spiele Song ab... Drücke Strg+T zum Stoppen.")

-- Decoder für das Minecraft-Audioformat laden
local decoder = require("cc.audio.dfpwm").make_decoder()

while true do
    -- Liest Musik-Häppchen (16 Kilobyte) aus dem Internet
    local chunk = response.read(16 * 1024)
    if not chunk then 
        break -- Song zu Ende
    end
    
    local buffer = decoder(chunk)
    -- Warten, bis der Speaker wieder Platz im Puffer hat
    while not speaker.playAudio(buffer) do
        os.pullEvent("speaker_audio_empty")
    end
end

response.close()
print("Song beendet!")
