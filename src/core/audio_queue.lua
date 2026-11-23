-- Audio manager: sequential VO queue, independent music channel, cloned SFX.

local Assets = require("src.core.assets")

local AudioQueue = {
    queue = {},
    currentVo = nil,
    gap = 0.08,
    gapTimer = 0,
    musicSource = nil,
    musicVolume = 0.65,
    musicEnabled = true,
    sfxVolume = 0.9,
    voVolume = 1.0,
    paused = false,
    pauseDepth = 0,
    pausedVo = false,
    pausedMusic = false,
}

local function resolveSource(item, stype)
    if type(item) == "table" and item.group and item.key then
        return Assets.getManifestAudio(item.group, item.key, stype or "static")
    elseif type(item) == "string" then
        return Assets.getAudioSource(item, stype or "static")
    end
    return nil
end

function AudioQueue.enqueue(item)
    table.insert(AudioQueue.queue, item)
end

function AudioQueue.playSequence(items, gapSeconds)
    AudioQueue.stopVo()
    if gapSeconds ~= nil then
        AudioQueue.gap = gapSeconds
    end
    for _, item in ipairs(items) do
        table.insert(AudioQueue.queue, item)
    end
end

function AudioQueue.clearAndPlay(item)
    AudioQueue.stopVo()
    if item then
        table.insert(AudioQueue.queue, item)
    end
end

function AudioQueue.stopVo()
    AudioQueue.queue = {}
    AudioQueue.gapTimer = 0
    AudioQueue.pausedVo = false
    if AudioQueue.currentVo then
        AudioQueue.currentVo:stop()
        AudioQueue.currentVo = nil
    end
end

function AudioQueue.isPlaying()
    if AudioQueue.currentVo and AudioQueue.currentVo:isPlaying() then
        return true
    end
    return #AudioQueue.queue > 0
end

function AudioQueue.playMusic(item, opts)
    opts = opts or {}
    AudioQueue.stopMusic()
    if not AudioQueue.musicEnabled then
        return
    end
    local src = resolveSource(item, "stream")
    if src then
        src:setLooping(opts.loop ~= false)
        src:setVolume(opts.volume or AudioQueue.musicVolume)
        src:play()
        AudioQueue.musicSource = src
    end
end

function AudioQueue.stopMusic()
    AudioQueue.pausedMusic = false
    if AudioQueue.musicSource then
        AudioQueue.musicSource:stop()
        AudioQueue.musicSource = nil
    end
end

function AudioQueue.setMusicEnabled(enabled)
    AudioQueue.musicEnabled = enabled and true or false
    if not AudioQueue.musicEnabled then
        AudioQueue.stopMusic()
    end
end

function AudioQueue.playSfx(item, volume)
    local base = resolveSource(item, "static")
    if not base then
        return nil
    end
    local clone = base:clone()
    clone:setVolume(volume or AudioQueue.sfxVolume)
    clone:play()
    return clone
end

function AudioQueue.update(dt)
    if AudioQueue.paused then
        return
    end
    if AudioQueue.currentVo then
        if not AudioQueue.currentVo:isPlaying() then
            AudioQueue.currentVo = nil
            AudioQueue.gapTimer = AudioQueue.gap
        else
            return
        end
    end

    if AudioQueue.gapTimer > 0 then
        AudioQueue.gapTimer = AudioQueue.gapTimer - dt
        if AudioQueue.gapTimer > 0 then
            return
        end
    end

    if #AudioQueue.queue > 0 then
        local nextItem = table.remove(AudioQueue.queue, 1)
        local src = resolveSource(nextItem, "static")
        if src then
            local inst = src:clone()
            inst:setVolume(AudioQueue.voVolume)
            inst:play()
            AudioQueue.currentVo = inst
        end
    end
end

function AudioQueue.pauseAll()
    AudioQueue.pauseDepth = AudioQueue.pauseDepth + 1
    AudioQueue.paused = true
    if AudioQueue.pauseDepth == 1 then
        if AudioQueue.currentVo and AudioQueue.currentVo:isPlaying() then
            AudioQueue.currentVo:pause()
            AudioQueue.pausedVo = true
        else
            AudioQueue.pausedVo = false
        end
        if AudioQueue.musicSource and AudioQueue.musicSource:isPlaying() then
            AudioQueue.musicSource:pause()
            AudioQueue.pausedMusic = true
        else
            AudioQueue.pausedMusic = false
        end
    end
end

function AudioQueue.resumeAll()
    if AudioQueue.pauseDepth > 0 then
        AudioQueue.pauseDepth = AudioQueue.pauseDepth - 1
    end
    if AudioQueue.pauseDepth == 0 then
        AudioQueue.paused = false
        if AudioQueue.pausedVo and AudioQueue.currentVo then
            AudioQueue.currentVo:play()
        end
        if AudioQueue.pausedMusic and AudioQueue.musicEnabled and AudioQueue.musicSource then
            AudioQueue.musicSource:play()
        end
        AudioQueue.pausedVo = false
        AudioQueue.pausedMusic = false
    end
end

function AudioQueue.stopAll()
    AudioQueue.pauseDepth = 0
    AudioQueue.paused = false
    AudioQueue.stopVo()
    AudioQueue.stopMusic()
end

return AudioQueue
