-- SAPIS AI
-- Idea by Liammy_01
-- Most of the code written by XanderCreates

local chatBox = peripheral.find("chatBox")
local detector = peripheral.find("playerDetector")
local username, message, uuid, isHidden

local BOT_NAME = "SAPIS"
local REPLY_NAME = "\167eSAPIS"
local REPLY_JSON_PREFIX = '{"text":"SAPIS","color":"yellow"}'
local CONFIG_NAME = "sapis.json"
local DEBUG = false

local DEFAULT_MESSAGES = {
    startup = "\167eSAPIS\167r online. Try 'SAPIS, help'.",
    hello = "Hello {user}! Try 'SAPIS, help'.",
    unknown = "Unknown command '\167e{command}\167r'. Try 'SAPIS, help'.",
    help = "Commands: \167elocate <player>\167r, \167eonline\167r, \167ehelp\167r, \167ereload\167r, \167enuke\167r",
    locateUsage = "Usage: SAPIS, locate <player>",
    notOnline = "\167e{user}\167r is not online.",
    locateUndetected = "Could not locate \167e{user}\167r (other dimension or out of range).",
    locateFailed = "Could not locate \167e{user}\167r.",
    locateOk = "\167e{user}\167r is at \167a{x}, {y}, {z}\167r",
    online = "Online ({count}): {players}",
    noPlayers = "No players online.",
    detectorUnavailable = "Player detector unavailable.",
    reloaded = "Reloaded sapis.json.",
    reloadFailed = "Could not reload sapis.json.",
    error = "Error: {error}",
    nuke = "Kaboom!",
    credits = "The creation of SAPIS is credited towards Liammy_01 for some of the coding and the idea of SAPIS, and to XanderCreates for programming ALOT of SAPIS, and finally Lemon for inspiration,",
    rps = "{choice}"
}

local messages = {}

local function fixColors(s)
    return (s:gsub("\194\167", "\167"))
end

local function fixTree(value)
    if type(value) == "string" then
        return fixColors(value)
    elseif type(value) == "table" then
        local out = {}
        for k, v in pairs(value) do out[k] = fixTree(v) end
        return out
    end
    return value
end

local function configPath()
    if type(shell) == "table" and type(shell.getRunningProgram) == "function" then
        local ok, prog = pcall(shell.getRunningProgram)
        if ok and type(prog) == "string" and prog ~= "" then
            return fs.combine(fs.getDir(prog), CONFIG_NAME)
        end
    end
    return CONFIG_NAME
end

local function loadConfig()
    local path = configPath()
    local handle = fs.open(path, "r")
    if not handle then return nil, "missing " .. path end
    local raw = handle.readAll()
    handle.close()
    local ok, data, err = pcall(textutils.unserializeJSON, raw)
    if not ok then return nil, tostring(data) end
    if type(data) ~= "table" then return nil, err or "invalid JSON" end
    return data
end

local function applyConfig(data)
    if type(data) ~= "table" or type(data.messages) ~= "table" then
        return false
    end
    if type(data.debug) == "boolean" then DEBUG = data.debug end
    for key, value in pairs(DEFAULT_MESSAGES) do
        messages[key] = value
    end
    for key, value in pairs(data.messages) do
        if type(value) == "string" or type(value) == "table" then
            messages[key] = fixTree(value)
        end
    end
    return true
end

local function fill(template, vars)
    if not vars then return template end
    return (template:gsub("{(%w+)}", function(key)
        local value = vars[key]
        if value == nil then return "{" .. key .. "}" end
        return tostring(value)
    end))
end

local function resolve(value, vars)
    if type(value) == "string" then
        return fill(value, vars)
    elseif type(value) == "table" then
        local out = {}
        for k, v in pairs(value) do out[k] = resolve(v, vars) end
        return out
    end
    return value
end

local function msg(key, vars)
    local template = messages[key]
    if template == nil then return key end
    return resolve(template, vars)
end

local function stripColors(s)
    return (tostring(s):gsub("\167.", ""))
end

local function plainFrom(value)
    if type(value) == "string" then return value end
    local parts = {}
    local function walk(v)
        if type(v) == "string" then
            parts[#parts + 1] = v
        elseif type(v) == "table" then
            if type(v.text) == "string" then parts[#parts + 1] = v.text end
            if type(v.extra) == "table" then
                for _, child in ipairs(v.extra) do walk(child) end
            end
            for i = 1, #v do walk(v[i]) end
        end
    end
    walk(value)
    return table.concat(parts)
end

local function reply(payload)
    print("REPLY_CALLED: " .. tostring(type(payload)))
    if not chatBox then print("REPLY: no chatBox") return end
    if type(payload) == "table" then
        local ok, json = pcall(textutils.serializeJSON, payload)
        print("REPLY_JSON: ok=" .. tostring(ok) .. " json=" .. tostring(type(json)))
        if ok and type(json) == "string" and type(chatBox.sendFormattedMessage) == "function" then
            local sent = pcall(chatBox.sendFormattedMessage, json, REPLY_JSON_PREFIX)
            print("REPLY_SENT: " .. tostring(sent))
            if sent then return end
        end
        payload = plainFrom(payload)
        print("REPLY_PLAIN: " .. tostring(payload))
    end
    local sent2 = pcall(chatBox.sendMessage, tostring(payload), REPLY_NAME)
    print("REPLY_SENT2: " .. tostring(sent2))
end

local function message(string)
    chatBox.sendMessage(string)
end

local function parse(text)
    local body
    if text:sub(1, 6) == "$SAPIS" then
        body = text:sub(7)
    elseif text:sub(1, 5) == "SAPIS" then
        local sep = text:sub(6, 6)
        if sep == "," or sep == ":" or sep == " " or sep == "" then
            body = text:sub(6)
        else
            return nil
        end
    else
        return nil
    end
    body = body:match("^[%s,:]*(.-)%s*$")
    if body == "" then return "", "" end
    local cmd, rest = body:match("^(%S+)%s*(.*)$")
    if not cmd then return "", "" end
    return cmd:lower(), rest
end

local function isUuid(s)
    return type(s) == "string" and s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-") ~= nil
end

local function parseChat(e)
    local username, message, uuid, isHidden
    if DEBUG then
        local parts = {}
        for i = 2, #e do parts[#parts + 1] = tostring(e[i]) .. "(" .. type(e[i]) .. ")" end
        print("PARSECHAT: " .. table.concat(parts, " | "))
    end
    for i = 2, #e do
        local v = e[i]
        if type(v) == "string" then
            if isUuid(v) and not uuid then
                uuid = v
            else
                local cmd = parse(v)
                print("PARSEV: v=" .. tostring(v) .. " cmd=" .. tostring(cmd))
                if not message and cmd ~= nil then
                    message = v
                elseif not username and v ~= BOT_NAME and not isUuid(v) and not cmd and not v:match("^w") then
                    username = v
                elseif not username and not isUuid(v) and not cmd and v:lower() ~= BOT_NAME:lower() then
                    username = v
                end
            end
        elseif type(v) == "boolean" and isHidden == nil then
            isHidden = v
        end
    end
    if message and not username then
        for i = 2, #e do
            local v = e[i]
            if type(v) == "string" and v ~= message and not isUuid(v) and stripColors(v):lower() ~= BOT_NAME:lower() then
                username = v
                break
            end
        end
    end
    print("PARSECHAT_RES: user=" .. tostring(username) .. " msg=" .. tostring(message) .. " uuid=" .. tostring(uuid))
    return username, message, uuid, isHidden
end

local function onlinePlayers()
    if not detector then return nil end
    local ok, players = pcall(detector.getOnlinePlayers)
    if ok and type(players) == "table" then return players end
    return nil
end

local function resolveName(name)
    local players = onlinePlayers()
    if not players then return nil end
    local lname = name:lower()
    for _, p in ipairs(players) do
        if type(p) == "string" and p:lower() == lname then
            return p
        end
    end
    return nil
end

local commands = {}

commands.help = function()
    return msg("help")
end

commands.online = function()
    local players = onlinePlayers()
    if not players then return msg("detectorUnavailable") end
    local names = {}
    for _, p in ipairs(players) do
        if type(p) == "string" then names[#names + 1] = p end
    end
    if #names == 0 then return msg("noPlayers") end
    table.sort(names)
    return msg("online", { count = #names, players = table.concat(names, ", ") })
end

commands.locate = function(rest)
    local requested = rest:match("^(%S+)")
    if not requested then
        return msg("locateUsage")
    end
    local name = resolveName(requested)
    if not name then
        return msg("notOnline", { user = requested })
    end
    local ok, a, b, c = pcall(detector.getPlayerPos, name)
    if not ok or a == nil then
        return msg("locateUndetected", { user = name })
    end
    local x, y, z
    if type(a) == "table" then
        x, y, z = a.x, a.y, a.z
    else
        x, y, z = a, b, c
    end
    if type(x) ~= "number" then
        return msg("locateFailed", { user = name })
    end
    return msg("locateOk", {
        user = name,
        x = math.floor(x),
        y = math.floor(y),
        z = math.floor(z),
    })
end

commands.loc = commands.locate
commands.find = commands.locate

-- RPS State & Logic
local rps_state = {
    last_move = nil,
    last_result = nil,
    force_change = false
}

local choice_list = {"rock", "paper", "scissors"}
local beats = {
    rock = "scissors",
    paper = "rock",
    scissors = "paper"
}

local function get_rps_move(s)
    if type(s) ~= "string" then return nil end
    s = stripColors(s):lower()
    if s:find("rock") then return "rock" end
    if s:find("paper") then return "paper" end
    if s:find("scissors") then return "scissors" end
    if s:find("random") then return "random" end
    if s:find("gun") then return "invalid_gun" end
    if s:find("rifle") or s:find("cannon") then return "invalid_bullshitweapon" end
    if s:find("nuclear") or s:find("nuke") then return "invalid_whatthefuck" end
    return nil
end

commands.rps = function(rest)
    local move = get_rps_move(rest)

    if move == nil or move == "random" or move:find("invalid_") then
        if move == nil then
            reply(msg("rps"))
            sleep(0.05)
            reply(msg("rps_invalid"))
        elseif move == "random" then
            reply(msg("rps_random"))
        elseif move == "invalid_bullshitweapon" then
            reply(msg("rps_unamused"))
        elseif move == "invalid_gun" then
            reply(msg("rps_gun", {randomage = math.random(7,15)}))
        elseif move == "invalid_whatthefuck" then
            reply(msg("rps_nuke"))
        end
        sleep(0.75)
        
        move = choice_list[math.random(#choice_list)]
        reply(msg("rps_choice_random", { choice = move }))
        sleep(0.1)
    else
        reply(msg("rps_choice", { choice = move }))
        sleep(0.1)
    end

    local bot
    if rps_state.force_change or rps_state.last_result == "lose" then
        bot = choice_list[math.random(#choice_list)]
        rps_state.force_change = false
    elseif rps_state.last_result == "win" and rps_state.last_move and math.random() < 0.6 then
        bot = rps_state.last_move
    else
        bot = choice_list[math.random(#choice_list)]
    end


    rps_state.last_move = bot
    if move == bot then
        rps_state.last_result = "draw"
        return msg("rps_player_draw", { choice = bot })
    elseif beats[bot] == move then
        rps_state.last_result = "win"
        return msg("rps_player_lost", { choice = bot })
    else
        rps_state.last_result = "lose"
        rps_state.force_change = true
        return msg("rps_player_win", { choice = bot })
    end
end

commands.nemesis = function()
    return msg("NEMESIS")
end

commands.nuke = function()
    return msg("nuke")
end

commands.credits = function()
    return msg("credits")
end

commands.reload = function()
    local data, err = loadConfig()
    if not data or not applyConfig(data) then
        print("reload: " .. tostring(err or "invalid config"))
        return msg("reloadFailed")
    end
    return msg("reloaded")
end

commands.ping = function()
    return msg("ping")
end

commands.pull = function()
    if username == "Liammy_01" then
        return msg("NEMESIS")
    else
        return msg("nuke")
    end
end


-- Config Initialization
do
    local data, err = loadConfig()
    if data then
        applyConfig(data)
    else
        for key, value in pairs(DEFAULT_MESSAGES) do
            messages[key] = value
        end
        print(CONFIG_NAME .. ": " .. tostring(err) .. "; using built-in replies.")
    end
end

if not chatBox then
    error("No chatBox peripheral attached.")
end
if not detector then
    print("Warning: no playerDetector peripheral; locate/online disabled.")
end

reply(msg("startup"))

local function tick()
    username, message, uuid, isHidden = nil, nil, nil, nil
    local e = { os.pullEvent("chat") }
    if DEBUG then
        local parts = {}
        for i = 2, #e do parts[#parts + 1] = tostring(e[i]) end
        print("chat [" .. (#e - 1) .. "]: " .. table.concat(parts, " | "))
    end
    
    username, message, uuid, isHidden = parseChat(e)
    
    if message then
        local userLower = stripColors(username or ""):lower()
        if userLower == BOT_NAME:lower() then
            print("SKIP: own message")
        else
            print("[INFO]: going to parse cmd")
            local cmd, rest = parse(message)
            if cmd then
                if cmd == "" then
                    reply(msg("hello", { user = tostring(username or "there") }))
                else
                    local fn = commands[cmd]
                    if fn then
                        print("CMD: " .. tostring(cmd) .. " from " .. tostring(username) .. " rest=" .. tostring(rest))
                        local ok, res = pcall(fn, rest or "", username)
                        print("CMDRES: ok=" .. tostring(ok) .. " res=" .. tostring(type(res)))
                        if ok then
                            if res == nil then res = msg("error", { error = "nil response" }) end
                            reply(res)
                        else
                            reply(msg("error", { error = tostring(res) }))
                        end
                    else
                        reply(msg("unknown", { command = cmd }))
                    end
                end
            end
        end
    end
    sleep(0.05)
end

while true do
    tick()
end