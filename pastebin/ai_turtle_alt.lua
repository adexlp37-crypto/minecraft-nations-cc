-- KONFIGURATION
local apiKey = "REPLACE_WITH_GROQ_API_KEY"
local triggerWord = "tt"
local botName = "Jarvis Turtle"
local modelName = "llama-3.3-70b-versatile"
local url = "https://api.groq.com/openai/v1/chat/completions"

-- SYSTEM PROMPT: Explizite Anweisung KEINE Zahlen zu verwenden
local systemPrompt = [[
You are an AI controlling a Minecraft Turtle (CC: Tweaked).
Output ONLY valid, complete Lua code. NO markdown, NO explanations.
CRITICAL RULES:
1. Turtle functions take NO arguments. NEVER write turtle.up(1) or turtle.forward(5).
2. To move multiple times, USE A LOOP: 'for i=1,5 do turtle.up() end'.
3. ALWAYS close loops with 'end'.
4. Available functions: turtle.forward(), turtle.back(), turtle.up(), turtle.down(), turtle.turnLeft(), turtle.turnRight(), turtle.dig(), turtle.digUp(), turtle.digDown(), turtle.place(), turtle.select(slot), turtle.refuel(count).
Example User: "Go up 3 blocks"
Example You: for i=1,3 do turtle.up() end
Example User: "Dig forward"
Example You: turtle.dig()
]]

local conversationHistory = {
    { role = "system", content = systemPrompt }
}

local chat = peripheral.find("chat_box")
if not chat then
    error("No Chat Box found!")
end

print("Jarvis Turtle Online. Listening for '" .. triggerWord .. "'...")

local function askGroq(task)
    table.insert(conversationHistory, { role = "user", content = task })

    local postData = textutils.serializeJSON({
        model = modelName,
        messages = conversationHistory,
        temperature = 0.1,
        max_tokens = 250
    })

    local headers = {
        ["Authorization"] = "Bearer " .. apiKey,
        ["Content-Type"] = "application/json"
    }

    local response, err = http.post(url, postData, headers)
    
    if response then
        local rawResult = response.readAll()
        response.close()
        local success, data = pcall(textutils.unserializeJSON, rawResult)
        
        if success and data.choices and #data.choices > 0 then
            local code = data.choices[1].message.content
            table.insert(conversationHistory, { role = "assistant", content = code })
            return code
        end
    end
    return nil
end

local function cleanCode(str)
    if not str then return "" end
    str = str:gsub("```lua", "\n"):gsub("```", "\n"):gsub("```text", "\n")
    return str:match("^%s*(.-)%s*$")
end

local function executeCode(codeString)
    local clean = cleanCode(codeString)
    if clean == "" then
        chat.sendMessage(botName .. ": No code generated.")
        return
    end

    print("Executing:\n" .. clean)

    local env = {
        turtle = turtle,
        print = print,
        pairs = pairs,
        ipairs = ipairs,
        tonumber = tonumber,
        string = string,
        table = table,
        os = { sleep = os.sleep },
        error = error
    }

    local func, err = load(clean, "AI_Script", "t", env)
    
    if func then
        local success, runErr = pcall(func)
        if success then
            chat.sendMessage(botName .. ": Done.")
        else
            chat.sendMessage(botName .. ": Error: " .. tostring(runErr))
        end
    else
        chat.sendMessage(botName .. ": Syntax Error: " .. tostring(err))
    end
end

while true do
    local event, spieler, nachricht = os.pullEvent("chat")
    
    if string.find(nachricht, triggerWord) then
        local task = string.gsub(nachricht, triggerWord, "")
        local finalPrompt = "Player " .. spieler .. " commands: " .. task
        
        print("Command: " .. task)
        chat.sendMessage(botName .. ": Working...")
        
        local code = askGroq(finalPrompt)
        if code then
            executeCode(code)
        end
    end
end   
