-- === CONFIGURATION ===
local modemSide = "top"         -- Where is the Wireless Modem?
local redstoneSide = "right"     -- Which side outputs the signal to the door?

-- SIGNAL LOGIC:
-- Set to false: Outputs Redstone when base is EMPTY (No one is home -> Close)
-- Set to true:  Outputs Redstone when SOMEONE IS HOME (Open)
local invertRedstone = false

-- === BASE MEMBERS WHITELIST ===
local baseMembers = {
    ["DeformedRac"] = true,
    ["ShayCass382"] = true,
    ["Kekdex"] = true,
    ["arseniymuromov"] = true
}

-- === YOUR BASE BOUNDARIES ===
local base = {
    minX = 7110, maxX = 7156,
    minY = 50,   maxY = 120,
    minZ = -6459, maxZ = -6395

}

-- === INITIALIZATION ===
if peripheral.isPresent(modemSide) and peripheral.getType(modemSide) == "modem" then
    rednet.open(modemSide)
    print("=== Create Door Controller Active ===")
    print("Listening for radar data...")
else
    error("ERROR: No modem found on side: " .. modemSide)
end

-- Ensure redstone starts in a defined state
redstone.setOutput(redstoneSide, invertRedstone)

-- === MAIN LOOP ===
while true do
    -- Listen to the broadcast from Computer 1
    local senderId, message, protocol = rednet.receive("bluemap_alarm_system")
    
    if message then
        local jsonSuccess, data = pcall(textutils.unserializeJSON, message)
        
        if jsonSuccess and data and data.players then
            local baseMembersHome = 0
            
            -- Scan all online players
            for _, player in ipairs(data.players) do
                if player.name and player.position then
                    
                    -- Check if the player is a whitelisted base member
                    if baseMembers[player.name] then
                        local x = math.floor(player.position.x + 0.5)
                        local y = math.floor(player.position.y + 0.5)
                        local z = math.floor(player.position.z + 0.5)
                        
                        -- Check if they are inside the base coordinates
                        if x >= base.minX and x <= base.maxX and
                           y >= base.minY and y <= base.maxY and
                           z >= base.minZ and z <= base.maxZ then
                            
                            baseMembersHome = baseMembersHome + 1
                        end
                    end
                    
                end
            end
            
            -- === DOOR CONTROL LOGIC ===
            if baseMembersHome > 0 then
                -- Someone is home!
                print(string.format("[STATUS] %d member(s) inside. Keeping doors open.", baseMembersHome))
                redstone.setOutput(redstoneSide, invertRedstone)
            else
                -- Base is completely empty
                print("[STATUS] Base is EMPTY. Closing doors!")
                redstone.setOutput(redstoneSide, not invertRedstone)
            end
            
        end
    end
end

