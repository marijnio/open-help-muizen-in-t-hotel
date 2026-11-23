-- Renders extracted Director 4 score frames (including SCVW FilmLoops) and extracts room metadata/bounds.

local Assets = require("src.core.assets")

local DirectorStage = {}

local function resolveCast(movieKey, castId, sharedKey)
    local score = Assets.getDxr(movieKey)
    if not score then return nil end
    local cast = score.casts[castId]
    if cast then
        return cast
    end
    if sharedKey then
        local sharedScore = Assets.getDxr(sharedKey)
        if sharedScore and sharedScore.casts[castId] then
            return sharedScore.casts[castId]
        end
    end
    return nil
end

local function drawCastSprite(movieKey, sp, cast, opts)
    if cast.type == "bitmap" and cast.image then
        local img = Assets.getImage(cast.image, opts.filter or "nearest")
        if img then
            local rx = cast.reg_x or 0
            local ry = cast.reg_y or 0
            love.graphics.draw(img, sp.x - rx, sp.y - ry)
        end
    elseif cast.type == "filmloop" and cast.filmloop and #cast.filmloop > 0 then
        local tick = opts.loopTick or 0
        local subFrame = cast.filmloop[(tick % #cast.filmloop) + 1]
        if subFrame then
            local sharedKey = opts.sharedKey
            for _, sub in ipairs(subFrame) do
                local subCast = resolveCast(movieKey, sub.cast, sharedKey)
                if subCast and subCast.type == "bitmap" and subCast.image then
                    local img = Assets.getImage(subCast.image, opts.filter or "nearest")
                    if img then
                        local rx = subCast.reg_x or 0
                        local ry = subCast.reg_y or 0
                        love.graphics.draw(img, sub.x - rx, sub.y - ry)
                    end
                end
            end
        end
    end
end

function DirectorStage.getChannelSprite(movieKey, frameNum, ch)
    local score = Assets.getDxr(movieKey)
    local frame = score and score.frames and score.frames[frameNum]
    if not frame then return nil end
    for _, sp in ipairs(frame) do
        if sp.ch == ch then
            return sp
        end
    end
    return nil
end

function DirectorStage.drawFrame(movieKey, frameNum, opts)
    opts = opts or {}
    local score = Assets.getDxr(movieKey)
    if not score or not score.frames then
        return
    end
    local frame = score.frames[frameNum]
    if not frame then
        return
    end

    local sharedKey = (opts.sharedKey == nil) and "shared" or opts.sharedKey
    local channelCastOverrides = opts.channelCasts or {}
    local hiddenChannels = opts.hiddenChannels or {}
    local puppetSprites = opts.puppetSprites
    opts._resolvedShared = sharedKey

    local drawOpts = {
        filter = opts.filter,
        loopTick = opts.loopTick,
        sharedKey = sharedKey,
    }

    local byChannel = {}
    for _, sp in ipairs(frame) do
        byChannel[sp.ch] = sp
    end
    if puppetSprites then
        for ch, psp in pairs(puppetSprites) do
            byChannel[ch] = psp
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    for ch = 1, 48 do
        local sp = byChannel[ch]
        if sp and not hiddenChannels[ch] then
            local castId = channelCastOverrides[ch] or sp.cast
            local cast = resolveCast(movieKey, castId, sharedKey)
            if cast then
                drawCastSprite(movieKey, sp, cast, drawOpts)
            end
        end
    end
end

function DirectorStage.getLabelFrame(movieKey, labelName)
    local score = Assets.getDxr(movieKey)
    if not score or not score.label_frames then
        return nil
    end
    return score.label_frames[string.lower(labelName)]
end

local function frameHasChannel(frame, ch)
    if not frame then return false end
    for _, sp in ipairs(frame) do
        if sp.ch == ch then
            return true
        end
    end
    return false
end

function DirectorStage.getLabelSpans(movieKey)
    local score = Assets.getDxr(movieKey)
    if not score or not score.labels then
        return {}, {}
    end
    local ordered = {}
    for fr, lbl in pairs(score.labels) do
        table.insert(ordered, { frame = fr, label = lbl, key = string.lower(lbl) })
    end
    table.sort(ordered, function(a, b) return a.frame < b.frame end)

    local totalFrames = #score.frames
    local spans = {}
    for i, item in ipairs(ordered) do
        local nextFrame = ordered[i + 1] and ordered[i + 1].frame or (totalFrames + 1)
        local endFrame = math.max(item.frame, math.min(totalFrames, nextFrame - 1))
        local startData = score.frames[item.frame]
        local requireBg = startData and frameHasChannel(startData, 1)
        while endFrame > item.frame do
            local fd = score.frames[endFrame]
            if not fd or #fd == 0 or (requireBg and not frameHasChannel(fd, 1)) then
                endFrame = endFrame - 1
            else
                break
            end
        end
        item.startFrame = item.frame
        item.endFrame = endFrame
        if not spans[item.key] then
            spans[item.key] = { startFrame = item.frame, endFrame = endFrame, label = item.label }
        end
    end
    return ordered, spans
end

function DirectorStage.getMouseBounds(movieKey, frameNum, sharedKey)
    local score = Assets.getDxr(movieKey)
    if not score or not score.frames then return nil end
    local frame = score.frames[frameNum]
    if not frame then return nil end

    sharedKey = sharedKey or "shared"
    for i = #frame, 1, -1 do
        local sp = frame[i]
        -- SHARED.DXR green mice sprites live in casts 400..753
        if sp.cast >= 400 and sp.cast <= 753 then
            local cast = resolveCast(movieKey, sp.cast, sharedKey)
            if cast and cast.type == "bitmap" and cast.w and cast.h then
                local rx = cast.reg_x or 0
                local ry = cast.reg_y or 0
                return {
                    x = sp.x - rx,
                    y = sp.y - ry,
                    w = cast.w,
                    h = cast.h,
                    cx = sp.x - rx + cast.w * 0.5,
                    cy = sp.y - ry + cast.h * 0.5,
                    cast = sp.cast,
                }
            end
        end
    end
    return nil
end

local function parsePair(line)
    if not line then return nil end
    local a, b = line:match("(%-?%d+)%s*,%s*(%-?%d+)")
    if a and b then
        return { x = tonumber(a), y = tonumber(b) }
    end
    return nil
end

function DirectorStage.parseRoomMeta(movieKey)
    local score = Assets.getDxr(movieKey)
    if not score then return nil end

    local meta = {
        prefix = nil,
        numLoops = 1,
        loopChannel = 0,
        pos1 = nil,
        trapPos = { x = 320, y = 370 },
        hidelist = {},
        spots = {},
        ambientSound = nil,
    }

    for _, cast in pairs(score.casts) do
        if cast.type == "text" and cast.name and cast.text then
            local nm = string.lower(cast.name)
            if nm == "movieinfo" then
                local lines = {}
                for raw in (cast.text .. "\n"):gmatch("([^\n]*)\n") do
                    local cleaned = raw:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if cleaned ~= "" then
                        table.insert(lines, cleaned)
                    end
                end
                if lines[1] then meta.prefix = string.lower(lines[1]) end
                if lines[2] then meta.numLoops = tonumber(lines[2]) or 1 end
                if lines[3] then meta.loopChannel = tonumber(lines[3]) or 0 end
                if lines[4] then meta.pos1 = parsePair(lines[4]) end
                if lines[5] then meta.trapPos = parsePair(lines[5]) or meta.trapPos end
            elseif nm == "hidelist" then
                for raw in (cast.text .. "\n"):gmatch("([^\n]*)\n") do
                    local fromStr, toStr = raw:match("(%d+)%s*:%s*([%d,%s]+)")
                    if fromStr and toStr then
                        local fromId = tonumber(fromStr)
                        local dests = {}
                        for d in toStr:gmatch("%d+") do
                            table.insert(dests, tonumber(d))
                        end
                        if #dests > 0 then
                            meta.hidelist[fromId] = dests
                        end
                    end
                end
            end
        elseif cast.type == "sound" and cast.sound then
            local nm = string.lower(cast.name or "")
            if nm:match("%.aif$") or nm == "music" or nm:match("cycle") then
                meta.ambientSound = cast.sound
            elseif not meta.ambientSound then
                meta.ambientSound = cast.sound
            end
        end
    end

    -- Extract hiding spot hotzones from loop1 frame (shape sprites on channels 30..41)
    local l1 = DirectorStage.getLabelFrame(movieKey, "loop1") or 22
    local frame = score.frames[l1]
    if frame then
        for _, sp in ipairs(frame) do
            if sp.ch >= 30 and sp.ch <= 41 then
                local cast = score.casts[sp.cast]
                if cast and cast.type == "shape" then
                    table.insert(meta.spots, {
                        spot = sp.ch - 29,
                        ch = sp.ch,
                        x = sp.x,
                        y = sp.y,
                        w = sp.w,
                        h = sp.h,
                    })
                end
            end
        end
        table.sort(meta.spots, function(a, b) return a.spot < b.spot end)
    end

    return meta
end

return DirectorStage
