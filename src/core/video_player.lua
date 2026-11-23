-- Option A video player: streams audio + on-demand JPEG frames in sync.

local Assets = require("src.core.assets")

local VideoPlayer = {}
VideoPlayer.__index = VideoPlayer

function VideoPlayer.new(videoKey, opts)
    opts = opts or {}
    local meta = Assets.getVideoMeta(videoKey)
    if not meta or not meta.frames or meta.frames <= 0 then
        return nil
    end

    local self = setmetatable({
        key = videoKey,
        meta = meta,
        fps = meta.fps or 12,
        totalFrames = meta.frames,
        currentFrameIdx = 0,
        currentImage = nil,
        audio = nil,
        audioWasPlaying = false,
        elapsed = 0,
        finished = false,
        paused = false,
        x = opts.x,
        y = opts.y,
        w = opts.w or meta.width,
        h = opts.h or meta.height,
        filter = opts.filter or "nearest",
        onFinish = opts.onFinish,
    }, VideoPlayer)

    -- Optional frame index map: logical frame -> unique (deduplicated) frame file
    if meta.index then
        local map = Assets.loadLuaTable(meta.index)
        if type(map) == "table" and #map > 0 then
            self.frameMap = map
        end
    end

    if not self.x then
        self.x = math.floor((640 - self.w) * 0.5)
    end
    if not self.y then
        self.y = math.floor((480 - self.h) * 0.5)
    end

    if meta.audio then
        local src = Assets.getAudioSource(meta.audio, "stream")
        if src then
            src:stop()
            src:setLooping(false)
            src:setVolume(opts.volume or 1.0)
            self.audio = src
        end
    end

    self:loadFrame(1)
    if self.audio then
        self.audio:play()
    end
    return self
end

function VideoPlayer:loadFrame(idx)
    idx = math.max(1, math.min(self.totalFrames, idx))
    if idx == self.currentFrameIdx and self.currentImage then
        return
    end
    local fileIdx = (self.frameMap and self.frameMap[idx]) or idx
    if fileIdx == self.currentFileIdx and self.currentImage then
        -- Held frame: same image as before, skip decoding
        self.currentFrameIdx = idx
        return
    end
    local path = string.format(self.meta.pattern, fileIdx)
    local img = Assets.loadUncachedImage(path, self.filter)
    if img then
        if self.currentImage and self.currentImage.release then
            self.currentImage:release()
        end
        self.currentImage = img
        self.currentFrameIdx = idx
        self.currentFileIdx = fileIdx
    end
end

function VideoPlayer:update(dt)
    if self.finished or self.paused then
        return
    end
    self.elapsed = self.elapsed + dt

    local t = self.elapsed
    if self.audio and self.audio:isPlaying() then
        local pos = self.audio:tell("seconds")
        if pos and pos > 0 then
            t = pos
        end
    end

    local targetFrame = math.floor(t * self.fps) + 1
    if targetFrame > self.totalFrames then
        if not self.audio or not self.audio:isPlaying() then
            self:finish()
            return
        end
        targetFrame = self.totalFrames
    end
    self:loadFrame(targetFrame)

    if self.meta.duration and self.meta.duration > 0 and self.elapsed >= self.meta.duration + 0.15 then
        if not self.audio or not self.audio:isPlaying() then
            self:finish()
        end
    end
end

function VideoPlayer:draw()
    if self.currentImage then
        love.graphics.setColor(1, 1, 1, 1)
        local iw, ih = self.currentImage:getDimensions()
        love.graphics.draw(
            self.currentImage,
            self.x,
            self.y,
            0,
            self.w / iw,
            self.h / ih
        )
    end
end

function VideoPlayer:pause()
    self.paused = true
    if self.audio and self.audio:isPlaying() then
        self.audioWasPlaying = true
        self.audio:pause()
    else
        self.audioWasPlaying = false
    end
end

function VideoPlayer:resume()
    if self.finished then return end
    self.paused = false
    if self.audio and self.audioWasPlaying then
        self.audio:play()
    end
    self.audioWasPlaying = false
end

function VideoPlayer:finish()
    if self.finished then return end
    self:stop()
    if self.onFinish then
        self.onFinish()
    end
end

function VideoPlayer:stop()
    self.finished = true
    if self.audio then
        self.audio:stop()
        self.audio = nil
    end
    if self.currentImage and self.currentImage.release then
        self.currentImage:release()
        self.currentImage = nil
    end
    self.currentFileIdx = nil
end

function VideoPlayer:isFinished()
    return self.finished
end

return VideoPlayer
