-- Renders extracted Director 4 score frames using cast registration points.

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

    local sharedKey = opts.sharedKey or "shared"
    local channelCastOverrides = opts.channelCasts or {}
    local hiddenChannels = opts.hiddenChannels or {}

    love.graphics.setColor(1, 1, 1, 1)
    for _, sp in ipairs(frame) do
        if not hiddenChannels[sp.ch] then
            local castId = channelCastOverrides[sp.ch] or sp.cast
            local cast = resolveCast(movieKey, castId, sharedKey)
            if cast and cast.type == "bitmap" and cast.image then
                local img = Assets.getImage(cast.image, opts.filter or "nearest")
                if img then
                    local rx = cast.reg_x or 0
                    local ry = cast.reg_y or 0
                    love.graphics.draw(img, sp.x - rx, sp.y - ry)
                end
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

return DirectorStage
