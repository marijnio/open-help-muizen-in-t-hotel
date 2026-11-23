-- Save / load game progress via love.filesystem.

local Save = {
    FILENAME = "savegame.lua",
}

local function serializeValue(v, indent)
    local t = type(v)
    if t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        local parts = { "{\n" }
        local pad = string.rep("  ", indent + 1)
        for k, val in pairs(v) do
            local keyStr = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
            table.insert(parts, pad .. keyStr .. " = " .. serializeValue(val, indent + 1) .. ",\n")
        end
        table.insert(parts, string.rep("  ", indent) .. "}")
        return table.concat(parts)
    end
    return "nil"
end

function Save.exists()
    return love.filesystem.getInfo(Save.FILENAME) ~= nil
end

function Save.write(data)
    local content = "return " .. serializeValue(data, 0) .. "\n"
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
    return data
end

function Save.delete()
    if Save.exists() then
        love.filesystem.remove(Save.FILENAME)
    end
end

return Save
