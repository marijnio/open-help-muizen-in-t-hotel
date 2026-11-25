-- Top-5 high score persistence for Super Spel via love.filesystem.

local SuperScores = {
    FILENAME = "superscores.lua",
    MAX_ENTRIES = 5,
}

local function sanitizeEntries(raw)
    local list = {}
    if type(raw) ~= "table" then
        return list
    end
    for _, item in ipairs(raw) do
        if type(item) == "table" then
            local sc = tonumber(item.score)
            if sc and sc == sc and sc ~= math.huge and sc ~= -math.huge then
                local name = type(item.name) == "string" and item.name:gsub("[%c]", "") or "Speler"
                if name == "" then
                    name = "Speler"
                end
                table.insert(list, {
                    name = name,
                    score = math.max(0, math.floor(sc)),
                })
            end
        end
    end
    table.sort(list, function(a, b) return a.score > b.score end)
    while #list > SuperScores.MAX_ENTRIES do
        table.remove(list)
    end
    return list
end

local function serializeList(list)
    local parts = { "return {\n" }
    for _, item in ipairs(list) do
        table.insert(parts, string.format("  { name = %q, score = %d },\n", item.name, item.score))
    end
    table.insert(parts, "}\n")
    return table.concat(parts)
end

function SuperScores.exists()
    return love.filesystem.getInfo(SuperScores.FILENAME) ~= nil
end

function SuperScores.delete()
    if SuperScores.exists() then
        love.filesystem.remove(SuperScores.FILENAME)
    end
end

function SuperScores.load()
    if not love.filesystem.getInfo(SuperScores.FILENAME) then
        return {}
    end
    local chunk, err = love.filesystem.load(SuperScores.FILENAME)
    if not chunk then
        print("[SuperScores] Failed to load scores: " .. tostring(err))
        return {}
    end
    local ok, data = pcall(chunk)
    if not ok then
        return {}
    end
    return sanitizeEntries(data)
end

function SuperScores.save(list)
    local clean = sanitizeEntries(list)
    local ok, err = love.filesystem.write(SuperScores.FILENAME, serializeList(clean))
    if not ok then
        print("[SuperScores] Failed to save scores: " .. tostring(err))
    end
    return ok
end

function SuperScores.record(score, name)
    local cleanScore = math.max(0, math.floor(tonumber(score) or 0))
    local cleanName = (type(name) == "string" and name ~= "") and name:gsub("[%c]", "") or "Speler"
    local list = SuperScores.load()
    local entry = { name = cleanName, score = cleanScore, _isNew = true }
    table.insert(list, entry)
    table.sort(list, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return (a._isNew and not b._isNew) == false
    end)

    local rank = nil
    for i, item in ipairs(list) do
        if item == entry and i <= SuperScores.MAX_ENTRIES then
            rank = i
        end
        item._isNew = nil
    end

    while #list > SuperScores.MAX_ENTRIES do
        table.remove(list)
    end
    SuperScores.save(list)
    return list, rank
end

return SuperScores
