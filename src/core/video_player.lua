-- Video player: streams audio + composites lossless delta-patch PNG frames (or legacy full frames)
-- with background thread PNG decoding, bounded LRU texture caching, and wall-clock A/V sync.

local Assets = require("src.core.assets")

local VideoPlayer = {}
VideoPlayer.__index = VideoPlayer

local PREFETCH_AHEAD = 16
local MAX_CACHE_ENTRIES = 32
local MAX_CACHE_BYTES = 12 * 1024 * 1024
local MAX_FRAME_WORK_SEC = 0.025

local worker = {
    thread = nil,
    req = nil,
    res = nil,
    nextJobId = 0,
}

local function getTime()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return nil
end

local function ensureWorker()
    if not (love and love.thread and love.thread.newChannel and love.thread.newThread) then
        return false
    end
    if worker.thread then
        if worker.thread:isRunning() then
            return true
        end
        worker.thread = nil
        worker.req = nil
        worker.res = nil
    end

    local req = love.thread.newChannel()
    local res = love.thread.newChannel()
    local ok, thread = pcall(love.thread.newThread, "src/core/video_decode_thread.lua")
    if not ok or not thread then
        return false
    end
    local started = pcall(thread.start, thread, req, res)
    if not started then
        return false
    end
    worker.req = req
    worker.res = res
    worker.thread = thread
    return true
end

function VideoPlayer.shutdownWorker()
    if worker.thread then
        if worker.thread:isRunning() and worker.req then
            pcall(worker.req.push, worker.req, "quit")
        end
        pcall(worker.thread.wait, worker.thread)
    end
    if worker.res then
        while true do
            local item = worker.res:pop()
            if not item then
                break
            end
            if type(item) == "table" and item.imageData and item.imageData.release then
                item.imageData:release()
            end
        end
    end
    worker.thread = nil
    worker.req = nil
    worker.res = nil
end

function VideoPlayer.new(videoKey, opts)
    opts = opts or {}
    local meta = Assets.getVideoMeta(videoKey)
    if not meta or not meta.frames or meta.frames <= 0 then
        return nil
    end

    worker.nextJobId = worker.nextJobId + 1

    local self = setmetatable({
        key = videoKey,
        meta = meta,
        jobId = worker.nextJobId,
        fps = meta.fps or 12,
        totalFrames = meta.frames,
        currentFrameIdx = 0,
        currentFileIdx = nil,
        currentImage = nil,
        canvas = nil,
        isDelta = false,
        patches = nil,
        steps = nil,
        frameMap = nil,
        audio = nil,
        audioWasPlaying = false,
        elapsed = 0,
        lastWallTime = getTime(),
        finished = false,
        paused = false,
        x = opts.x,
        y = opts.y,
        w = opts.w or meta.width,
        h = opts.h or meta.height,
        filter = opts.filter or "nearest",
        onFinish = opts.onFinish,
        texCache = {},
        texCacheCount = 0,
        texCacheBytes = 0,
        useSeq = 0,
        pendingRelease = {},
        prevPendingRelease = {},
        inFlight = {},
        inFlightCount = 0,
        decodedQueue = {},
        decodedCount = 0,
        decodedFailed = {},
        prefetchCursor = 1,
    }, VideoPlayer)

    -- Optional frame index: v2 delta-patch table or v1 frame map
    if meta.index then
        local idxData = Assets.loadLuaTable(meta.index)
        if type(idxData) == "table" then
            if idxData.version == 2 and type(idxData.patches) == "table" and type(idxData.steps) == "table" then
                self.isDelta = true
                self.patches = idxData.patches
                self.steps = idxData.steps
                self.canvas = love.graphics.newCanvas(meta.width, meta.height)
                self.canvas:setFilter(self.filter, self.filter)
                local prevCanvas = love.graphics.getCanvas()
                love.graphics.setCanvas(self.canvas)
                love.graphics.clear(0, 0, 0, 1)
                love.graphics.setCanvas(prevCanvas)
            elseif #idxData > 0 then
                self.frameMap = idxData
            end
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
    self:enqueuePrefetch()
    if self.audio then
        self.audio:play()
    end
    self.lastWallTime = getTime()
    return self
end

function VideoPlayer:getFramePid(frameIdx)
    if self.isDelta then
        local pid = self.steps[frameIdx]
        return (pid and pid > 0) and pid or nil
    end
    return (self.frameMap and self.frameMap[frameIdx]) or frameIdx
end

function VideoPlayer:drainDecoded()
    if not worker.res then
        return
    end
    while true do
        local item = worker.res:pop()
        if not item then
            break
        end
        if type(item) == "table" then
            if item.jobId ~= self.jobId then
                if item.imageData and item.imageData.release then
                    item.imageData:release()
                end
            else
                if self.inFlight[item.pid] then
                    self.inFlight[item.pid] = nil
                    self.inFlightCount = math.max(0, self.inFlightCount - 1)
                end
                if item.imageData then
                    if self.finished or self.texCache[item.pid] or self.decodedQueue[item.pid] then
                        if item.imageData.release then
                            item.imageData:release()
                        end
                    else
                        self.decodedQueue[item.pid] = item.imageData
                        self.decodedCount = self.decodedCount + 1
                    end
                elseif item.failed then
                    self.decodedFailed[item.pid] = true
                end
            end
        end
    end
end

function VideoPlayer:pruneStaleDecoded()
    if self.isDelta or self.decodedCount < PREFETCH_AHEAD then
        return
    end
    local keep = {}
    local limit = math.min(self.totalFrames, self.currentFrameIdx + PREFETCH_AHEAD)
    for f = self.currentFrameIdx + 1, limit do
        local pid = self:getFramePid(f)
        if pid then
            keep[pid] = true
        end
    end
    for pid, imgData in pairs(self.decodedQueue) do
        if not keep[pid] then
            if imgData and imgData.release then
                imgData:release()
            end
            self.decodedQueue[pid] = nil
            self.decodedCount = math.max(0, self.decodedCount - 1)
        end
    end
end

function VideoPlayer:enqueuePrefetch()
    if self.finished or not ensureWorker() then
        return
    end
    self:pruneStaleDecoded()
    local f = math.max(self.prefetchCursor, self.currentFrameIdx + 1)
    while f <= self.totalFrames and (self.inFlightCount + self.decodedCount) < PREFETCH_AHEAD do
        local pid = self:getFramePid(f)
        if pid and not self.texCache[pid] and not self.decodedQueue[pid]
            and not self.inFlight[pid] and not self.decodedFailed[pid]
        then
            local relPath = string.format(self.meta.pattern, pid)
            local fullPath, baseMode = Assets.resolvePath(relPath)
            if fullPath and baseMode then
                self.inFlight[pid] = true
                self.inFlightCount = self.inFlightCount + 1
                worker.req:push({
                    jobId = self.jobId,
                    pid = pid,
                    path = fullPath,
                    baseMode = baseMode,
                    name = relPath,
                })
            end
        end
        f = f + 1
    end
    self.prefetchCursor = f
end

function VideoPlayer:flushPendingReleases(all)
    for i = 1, #self.prevPendingRelease do
        local img = self.prevPendingRelease[i]
        if img and img.release then
            img:release()
        end
    end
    self.prevPendingRelease = {}

    if all then
        for i = 1, #self.pendingRelease do
            local img = self.pendingRelease[i]
            if img and img.release then
                img:release()
            end
        end
        self.pendingRelease = {}
    else
        self.prevPendingRelease = self.pendingRelease
        self.pendingRelease = {}
    end
end

function VideoPlayer:popDecodedImage(pid, filter)
    local imgData = self.decodedQueue[pid]
    if imgData then
        self.decodedQueue[pid] = nil
        self.decodedCount = math.max(0, self.decodedCount - 1)
        local ok, img = pcall(love.graphics.newImage, imgData)
        if imgData.release then
            imgData:release()
        end
        if ok and img then
            img:setFilter(filter, filter)
            return img
        end
    end
    local path = string.format(self.meta.pattern, pid)
    return Assets.loadUncachedImage(path, filter)
end

function VideoPlayer:evictOldestCached()
    local oldestPid = nil
    local oldestSeq = math.huge
    for pid, entry in pairs(self.texCache) do
        if entry.lastUse < oldestSeq then
            oldestSeq = entry.lastUse
            oldestPid = pid
        end
    end
    if not oldestPid then
        return false
    end
    local entry = self.texCache[oldestPid]
    self.texCache[oldestPid] = nil
    self.texCacheCount = math.max(0, self.texCacheCount - 1)
    self.texCacheBytes = math.max(0, self.texCacheBytes - entry.bytes)
    if entry.img then
        table.insert(self.pendingRelease, entry.img)
    end
    return true
end

function VideoPlayer:acquirePatchTexture(pid)
    self.useSeq = self.useSeq + 1
    local cached = self.texCache[pid]
    if cached then
        cached.lastUse = self.useSeq
        return cached.img
    end

    local img = self:popDecodedImage(pid, "nearest")
    if not img then
        return nil
    end

    local iw, ih = img:getDimensions()
    local bytes = iw * ih * 4
    if bytes <= MAX_CACHE_BYTES * 0.5 then
        while self.texCacheCount >= MAX_CACHE_ENTRIES or (self.texCacheBytes + bytes) > MAX_CACHE_BYTES do
            if not self:evictOldestCached() then
                break
            end
        end
        self.texCache[pid] = {
            img = img,
            bytes = bytes,
            lastUse = self.useSeq,
        }
        self.texCacheCount = self.texCacheCount + 1
        self.texCacheBytes = self.texCacheBytes + bytes
    else
        table.insert(self.pendingRelease, img)
    end
    return img
end

function VideoPlayer:loadFrame(idx, budgetSec)
    idx = math.max(1, math.min(self.totalFrames, idx))
    if self.isDelta then
        if idx <= self.currentFrameIdx then
            return
        end
        local hasPatch = false
        for f = self.currentFrameIdx + 1, idx do
            local pid = self.steps[f]
            if pid and pid > 0 then
                hasPatch = true
                break
            end
        end
        if hasPatch then
            local startT = budgetSec and getTime() or nil
            local prevCanvas = love.graphics.getCanvas()
            love.graphics.push("all")
            love.graphics.setCanvas(self.canvas)
            love.graphics.origin()
            love.graphics.setScissor()
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(1, 1, 1, 1)
            local appliedCount = 0
            local reachedFrame = self.currentFrameIdx
            for f = self.currentFrameIdx + 1, idx do
                local pid = self.steps[f]
                if pid and pid > 0 then
                    local patch = self.patches[pid]
                    local img = self:acquirePatchTexture(pid)
                    if img and patch then
                        love.graphics.draw(img, patch[1], patch[2])
                    end
                    appliedCount = appliedCount + 1
                end
                reachedFrame = f
                if budgetSec and startT and appliedCount > 0 and f < idx then
                    local now = getTime()
                    if now and (now - startT) >= budgetSec then
                        break
                    end
                end
            end
            love.graphics.pop()
            love.graphics.setCanvas(prevCanvas)
            self.currentFrameIdx = reachedFrame
        else
            self.currentFrameIdx = idx
        end
        return
    end

    if idx == self.currentFrameIdx and self.currentImage then
        return
    end
    local fileIdx = (self.frameMap and self.frameMap[idx]) or idx
    if fileIdx == self.currentFileIdx and self.currentImage then
        -- Held frame: same image as before, skip decoding
        self.currentFrameIdx = idx
        return
    end
    local img = self:popDecodedImage(fileIdx, self.filter)
    if img then
        if self.currentImage then
            table.insert(self.pendingRelease, self.currentImage)
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

    local now = getTime()
    local wallDt = dt
    if now and self.lastWallTime then
        wallDt = math.max(0, now - self.lastWallTime)
        self.lastWallTime = now
    elseif now then
        self.lastWallTime = now
    end
    self.elapsed = self.elapsed + wallDt

    local audioPlaying = (self.audio ~= nil and self.audio:isPlaying())
    local t = self.elapsed
    if audioPlaying then
        local pos = self.audio:tell("seconds")
        if pos and pos > 0 then
            t = pos
            if pos > self.elapsed then
                self.elapsed = pos
            end
        end
    end

    local targetFrame = math.floor(t * self.fps) + 1
    if targetFrame > self.totalFrames then
        if not audioPlaying then
            self:finish()
            return
        end
        targetFrame = self.totalFrames
    end

    self:drainDecoded()
    self:flushPendingReleases(false)
    self:enqueuePrefetch()
    self:loadFrame(targetFrame, MAX_FRAME_WORK_SEC)
    self:enqueuePrefetch()

    if self.meta.duration and self.meta.duration > 0 and self.elapsed >= self.meta.duration + 0.15 then
        if not self.audio or not self.audio:isPlaying() then
            self:finish()
        end
    end
end

function VideoPlayer:draw()
    local drawable = self.isDelta and self.canvas or self.currentImage
    if drawable then
        love.graphics.setColor(1, 1, 1, 1)
        local iw, ih = drawable:getDimensions()
        love.graphics.draw(
            drawable,
            self.x,
            self.y,
            0,
            self.w / iw,
            self.h / ih
        )
    end
end

function VideoPlayer:pause()
    if self.finished then return end
    if not self.paused then
        local now = getTime()
        if now and self.lastWallTime then
            self.elapsed = self.elapsed + math.max(0, now - self.lastWallTime)
        end
        self.lastWallTime = nil
        self.paused = true
    end
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
    self.lastWallTime = getTime()
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
    if self.canvas and self.canvas.release then
        self.canvas:release()
        self.canvas = nil
    end
    for pid, entry in pairs(self.texCache) do
        if entry.img and entry.img.release then
            entry.img:release()
        end
        self.texCache[pid] = nil
    end
    self.texCacheCount = 0
    self.texCacheBytes = 0

    for pid, imgData in pairs(self.decodedQueue) do
        if imgData and imgData.release then
            imgData:release()
        end
        self.decodedQueue[pid] = nil
    end
    self.decodedCount = 0
    self.inFlight = {}
    self.inFlightCount = 0
    self.decodedFailed = {}

    self:flushPendingReleases(true)
    self.currentFileIdx = nil
end

function VideoPlayer:isFinished()
    return self.finished
end

return VideoPlayer
