-- Save / load game progress via love.filesystem.

local Save = {
    FILENAME = "savegame.lua",
    VERSION = 1,
}

local function serializeValue(v, indent)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "nil"
        end
        return tostring(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        local numKeys = {}
        local strKeys = {}
        for k in pairs(v) do
            if type(k) == "number" then
                table.insert(numKeys, k)
            elseif type(k) == "string" then
                table.insert(strKeys, k)
            end
        end
        table.sort(numKeys)
        table.sort(strKeys)

        local parts = { "{\n" }
        local pad = string.rep("  ", indent + 1)
        for _, k in ipairs(numKeys) do
            local val = serializeValue(v[k], indent + 1)
            if val ~= "nil" then
                table.insert(parts, pad .. "[" .. k .. "] = " .. val .. ",\n")
            end
        end
        for _, k in ipairs(strKeys) do
            local val = serializeValue(v[k], indent + 1)
            if val ~= "nil" then
                table.insert(parts, pad .. "[" .. string.format("%q", k) .. "] = " .. val .. ",\n")
            end
        end
        table.insert(parts, string.rep("  ", indent) .. "}")
        return table.concat(parts)
    end
    return "nil"
end

local function buildPayload(session)
    if type(session) ~= "table" then
        return {}
    end
    local payload = {
        version = Save.VERSION,
        savedAt = os.time(),
        difficulty = session.difficulty,
        musicEnabled = session.musicEnabled,
        trapsLeft = session.trapsLeft,
        caughtMice = {},
        caughtCount = session.caughtCount,
        roomQueue = {},
        activeMouseRoom = session.activeMouseRoom,
        mouseRooms = {},
        seenIntros = {},
        foundInstruments = {},
        lastInstrument = session.lastInstrument,
        buildIndex = session.buildIndex,
        pendingInstrumentRoom = session.pendingInstrumentRoom,
    }
    if type(session.caughtMice) == "table" then
        for k, v in pairs(session.caughtMice) do
            if type(k) == "string" and v then
                payload.caughtMice[k] = true
            end
        end
    end
    if type(session.roomQueue) == "table" then
        for _, id in ipairs(session.roomQueue) do
            if type(id) == "string" then
                table.insert(payload.roomQueue, id)
            end
        end
    end
    if type(session.mouseRooms) == "table" then
        for k, v in pairs(session.mouseRooms) do
            if type(k) == "string" and v then
                payload.mouseRooms[k] = true
            end
        end
    end
    if type(session.seenIntros) == "table" then
        for k, v in pairs(session.seenIntros) do
            if type(k) == "string" and v then
                payload.seenIntros[k] = true
            end
        end
    end
    if type(session.foundInstruments) == "table" then
        for k, v in pairs(session.foundInstruments) do
            if type(k) == "string" and v then
                payload.foundInstruments[k] = true
            end
        end
    end
    return payload
end

function Save.exists()
    return love.filesystem.getInfo(Save.FILENAME) ~= nil
end

function Save.write(data)
    local payload = buildPayload(data)
    local content = "return " .. serializeValue(payload, 0) .. "\n"
    local ok, err = love.filesystem.write(Save.FILENAME, content)
    if not ok then
        print("[Save] Failed to write savegame: " .. tostring(err))
    end
    return ok
end

function Save.load()
    if not Save.exists() then
        return nil
    end
    local chunk, err = love.filesystem.load(Save.FILENAME)
    if not chunk then
        print("[Save] Failed to load savegame: " .. tostring(err))
        return nil
    end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then
        return nil
    end
    if data.caughtMice == nil
        and data.difficulty == nil
        and data.roomQueue == nil
        and data.activeMouseRoom == nil
        and data.version == nil
    then
        return nil
    end
    return data
end

function Save.peekSummary()
    local data = Save.load()
    if not data then
        return nil
    end
    local caughtCount = 0
    if type(data.caughtMice) == "table" then
        for _, v in pairs(data.caughtMice) do
            if v then
                caughtCount = caughtCount + 1
            end
        end
    else
        caughtCount = tonumber(data.caughtCount) or 0
    end
    local difficulty = math.max(1, math.min(3, math.floor(tonumber(data.difficulty) or 1)))
    local trapsLeft = math.max(0, math.floor(tonumber(data.trapsLeft) or 0))
    local pending = (type(data.pendingInstrumentRoom) == "string" and data.pendingInstrumentRoom ~= "")
        and data.pendingInstrumentRoom or nil
    return {
        caughtCount = caughtCount,
        difficulty = difficulty,
        trapsLeft = trapsLeft,
        pendingInstrumentRoom = pending,
    }
end

function Save.delete()
    if Save.exists() then
        love.filesystem.remove(Save.FILENAME)
    end
end

return Save
