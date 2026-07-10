local speaker = peripheral.find("speaker")

if not speaker then
    error("Kein Speaker gefunden! Bitte platziere einen Lautsprecher neben den Computer.")
end

-- Das berÃ¼hmte Megalovania-Intro
-- Format: { Note (0-24), Pause danach in Sekunden }
-- Wir nutzen "chime" (Glockenspiel/Xylophon) fÃ¼r den klassischen 8-Bit-Vibe
local intro = {
    -- Takt 1 (D, D, D oben, A)
    {2, 0.13}, {2, 0.13}, {14, 0.26}, {9, 0.39},
    -- (G#, G, F, D, F, G)
    {8, 0.26}, {7, 0.26}, {5, 0.26}, {2, 0.13}, {5, 0.13}, {7, 0.13},

    -- Takt 2 (C, C, D oben, A ...)
    {0, 0.13}, {0, 0.13}, {14, 0.26}, {9, 0.39},
    {8, 0.26}, {7, 0.26}, {5, 0.26}, {2, 0.13}, {5, 0.13}, {7, 0.13},

    -- Takt 3 (B, B, D oben, A ...)
    {-1, 0.13}, {-1, 0.13}, {14, 0.26}, {9, 0.39}, -- -1 simuliert das tiefere B (H)
    {8, 0.26}, {7, 0.26}, {5, 0.26}, {2, 0.13}, {5, 0.13}, {7, 0.13},

    -- Takt 4 (Bb, Bb, D oben, A ...)
    {-2, 0.13}, {-2, 0.13}, {14, 0.26}, {9, 0.39},
    {8, 0.26}, {7, 0.26}, {5, 0.26}, {2, 0.13}, {5, 0.13}, {7, 0.13}
}

print("Spiele MEGALOVANIA auf maximaler Lautstarke (1.0)!")
print("DrÃ¼cke Strg+T zum Abbrechen.")

-- Loop, um das Riff 3 Mal abzuspielen
for loop = 1, 3 do
    for _, step in ipairs(intro) do
        local note = step[1]
        local delay = step[2]
        
        -- Minecraft-Notenbegrenzung abfangen (0 bis 24)
        if note < 0 then note = 0 end 
        
        -- Instrument "chime" klingt sehr nach altem Arcade-Spiel
        -- LautstÃ¤rke ist hier fest auf dem Maximum (1.0)
        speaker.playNote("chime", 1.0, note)
        
        sleep(delay)
    end
end

print("Und abgemetzt!")

