-- Data-driven gameplay engine for the 19 standard hotel rooms.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local Hotzone = require("src.core.hotzone")
local SceneManager = require("src.core.scene_manager")
local Traps = require("src.core.traps")
local VideoPlayer = require("src.core.video_player")
local Rooms = require("src.data.rooms")

local Room = {}

local DIFFICULTY_FPS = { [1] = 8, [2] = 12, [3] = 16 }
local AUTO_RUN_DELAY_BY_DIFFICULTY = { [1] = 20, [2] = 30, [3] = nil }
local MOUSE_CATCH_LOCK_SECONDS = 0.40
local MOUSE_CATCH_LOCK_MIN_SECONDS = 0.15
local MOUSE_CATCH_LOCK_MAX_FRACTION = 0.40
local WIPE_DURATION = 1.4
local HINT_VIDEOS = { "cathelp7", "cathelp9", "cathel10", "cathel11" }
local CATCH_DANGLING_CASTS = { 707, 708, 709, 710, 711 }
local CATCH_HANG_DURATION = 0.45
local CATCH_MOVE_DURATION = 0.50
local CATCH_HOLD_DURATION = 0.16
local CATCH_WIGGLE_FPS = 12

local function computeCatchLockDuration(span)
    local baseFps = DIFFICULTY_FPS[App.session.difficulty or 1] or 12
    local spanFrames = math.max(1, (span.endFrame - span.startFrame) + 1)
    local capped = math.max(MOUSE_CATCH_LOCK_MIN_SECONDS, (spanFrames / baseFps) * MOUSE_CATCH_LOCK_MAX_FRACTION)
    return math.min(MOUSE_CATCH_LOCK_SECONDS, capped)
end

local function getAutoRunDelay()
    local diff = (App.session and App.session.difficulty) or 1
    return AUTO_RUN_DELAY_BY_DIFFICULTY[diff]
end

local function pointInRect(px, py, r)
    return px >= r.x and px < (r.x + r.w) and py >= r.y and py < (r.y + r.h)
end

local function findCaughtPreVideoEnd(score, caughtSpan)
    if score and score.frames and score.casts then
        for f = caughtSpan.startFrame, caughtSpan.endFrame do
            local frame = score.frames[f]
            if frame then
                for _, sp in ipairs(frame) do
                    local cast = score.casts[sp.cast]
                    if cast and cast.type == "digital_video" then
                        return math.max(caughtSpan.startFrame, f - 1)
                    end
                end
            end
        end
    end
    return math.min(caughtSpan.endFrame, caughtSpan.startFrame + 7)
end

function Room:enter(params)
    Cursor.reset()
    AudioQueue.stopAll()

    self.room = params.room
    self.dxrKey = self.room.dxr
    self.score = Assets.getDxr(self.dxrKey)
    self.meta = DirectorStage.parseRoomMeta(self.dxrKey) or { numLoops = 1, hidelist = {}, spots = {} }
    self.orderedLabels, self.spans = DirectorStage.getLabelSpans(self.dxrKey)
    self.fps = (self.score and self.score.fps) or 11

    self.traps = Traps.newState(self.meta.trapPos)
    self.loopIdx = 1
    self.loopTimer = 0
    self.loopTick = 0
    self.loopTickTimer = 0

    self.animSpan = nil
    self.animFrameFloat = 1
    self.animDestSpot = nil
    self.mouseCatchLockTimer = 0
    self.mouseIdleTimer = 0
    self.catchAnim = nil
    self.caughtPlayer = nil
    self.toast = nil
    self.toastTimer = 0
    self.wipeProgress = 0

    -- Place mouse in a valid hiding spot if this room still has a mouse
    self.hasMouse = Rooms.isActiveMouseRoom(App.session, self.room.id)
    self.mouseSpot = nil
    if self.hasMouse then
        local candidates = {}
        for spotId, _ in pairs(self.meta.hidelist) do
            table.insert(candidates, spotId)
        end
        if #candidates == 0 then
            for _, sp in ipairs(self.meta.spots) do
                table.insert(candidates, sp.spot)
            end
        end
        if #candidates > 0 then
            self.mouseSpot = candidates[love.math.random(1, #candidates)]
        end
    end

    self:buildHotzones()

    -- Play room entry music (startsnd) during the slow wipe reveal, matching original behavior
    self.mode = "entering"
    if App.session.musicEnabled ~= false and self.room.startsnd then
        AudioQueue.playMusic({ group = "startsnd", key = self.room.startsnd }, { loop = false, volume = 0.65 })
    elseif App.session.musicEnabled ~= false and self.meta.ambientSound then
        AudioQueue.playMusic(self.meta.ambientSound, { loop = true, volume = 0.45 })
    end
end

function Room:finishEntering()
    self.wipeProgress = 1
    self.mode = "idle"
    if not App.isTouchMode and App.lastVx and App.lastVy then
        self:mousemoved(App.lastVx, App.lastVy)
    end
end

function Room:exit()
    if self.caughtPlayer then
        self.caughtPlayer:stop()
        self.caughtPlayer = nil
    end
    AudioQueue.stopAll()
    Cursor.reset()
end

function Room:onFocus(focused)
    if self.caughtPlayer then
        if focused then self.caughtPlayer:resume() else self.caughtPlayer:pause() end
    end
end

function Room:buildHotzones()
    self.hotzones = Hotzone.new()

    for _, sp in ipairs(self.meta.spots) do
        self.hotzones:add({
            id = "spot_" .. sp.spot,
            spot = sp.spot,
            x = sp.x,
            y = sp.y,
            w = sp.w,
            h = sp.h,
            onClick = function()
                if self.mode == "idle" then
                    self:triggerSpot(sp.spot)
                end
            end
        })
    end

    self.hotzones:add({
        id = "exit_room",
        x = Traps.EXIT_RECT.x,
        y = Traps.EXIT_RECT.y,
        w = Traps.EXIT_RECT.w,
        h = Traps.EXIT_RECT.h,
        onClick = function()
            SceneManager.switch(App.states.hotel_hub)
        end
    })

    self.hotzones:add({
        id = "trap_bag",
        x = Traps.BAG_RECT.x,
        y = Traps.BAG_RECT.y,
        w = Traps.BAG_RECT.w,
        h = Traps.BAG_RECT.h,
        onClick = function()
            if (App.session.trapsLeft or 0) <= 0 then
                self:showToast("Geen muizenvallen meer!")
                return
            end
            self.traps.menuOpen = not self.traps.menuOpen
        end
    })

    self.hotzones:add({
        id = "cat_help",
        x = Traps.CAT_RECT.x,
        y = Traps.CAT_RECT.y,
        w = Traps.CAT_RECT.w,
        h = Traps.CAT_RECT.h,
        onClick = function()
            AudioQueue.pauseAll()
            local idx = love.math.random(1, #HINT_VIDEOS)
            Traps.openCatHint(
                HINT_VIDEOS[idx], function()
                    AudioQueue.resumeAll()
                end
            )
        end
    })
end

function Room:showToast(msg)
    self.toast = msg
    self.toastTimer = 2.2
end

function Room:playSpotSound(spotId)
    if not self.meta.prefix then return end
    local key = self.meta.prefix .. tostring(spotId)
    if Assets.getAudioPath("sounds", key) then
        AudioQueue.playSfx({ group = "sounds", key = key }, 0.85)
    end
end

function Room:findMouseRunSpan(fromSpot)
    local dests = self.meta.hidelist[fromSpot] or {}
    local valid = {}
    for _, dest in ipairs(dests) do
        local lbl = string.format("ma%d:%d", fromSpot, dest)
        if self.spans[lbl] then
            table.insert(valid, { dest = dest, span = self.spans[lbl] })
        end
    end
    -- Fallback: scan any ma<fromSpot>:<dest> label in the movie
    if #valid == 0 then
        local pat = "^ma" .. tostring(fromSpot) .. ":(%d+)$"
        for k, sp in pairs(self.spans) do
            local d = k:match(pat)
            if d then
                table.insert(valid, { dest = tonumber(d), span = sp })
            end
        end
    end
    if #valid == 0 then
        return nil, nil
    end
    local pick = valid[love.math.random(1, #valid)]
    return pick.dest, pick.span
end

function Room:canCatchMouse()
    return self.mode == "mouse_run" and (self.mouseCatchLockTimer or 0) <= 0
end

function Room:startMouseRun(fromSpot, isAuto)
    local dest, span = self:findMouseRunSpan(fromSpot)
    if not span then
        return false
    end
    if isAuto then
        self.traps.menuOpen = false
        self:playSpotSound(fromSpot)
    end
    AudioQueue.playSfx("dxr/shared/sounds/s_821.wav", 0.7)
    self.mode = "mouse_run"
    self.animSpan = span
    self.animFrameFloat = span.startFrame
    self.animDestSpot = dest
    self.mouseCatchLockTimer = computeCatchLockDuration(span)
    self.mouseIdleTimer = 0
    Cursor.setSystem("arrow")
    return true
end

function Room:triggerSpot(spotId)
    self.traps.menuOpen = false
    self:playSpotSound(spotId)

    if self.hasMouse and spotId == self.mouseSpot then
        if self:startMouseRun(spotId, false) then
            return
        end
    end

    local emptySpan = self.spans["a" .. tostring(spotId)]
    if emptySpan then
        self.mode = "anim_empty"
        self.animSpan = emptySpan
        self.animFrameFloat = emptySpan.startFrame
    end
end

function Room:currentIdleFrame()
    local key = "loop" .. tostring(self.loopIdx)
    return (self.spans[key] and self.spans[key].startFrame)
            or (self.spans["loop1"] and self.spans["loop1"].startFrame)
            or 22
end

function Room:currentFrameNumber()
    if self.mode == "idle" then
        return self:currentIdleFrame()
    elseif self.animSpan then
        return math.max(self.animSpan.startFrame, math.min(self.animSpan.endFrame, math.floor(self.animFrameFloat)))
    end
    return self:currentIdleFrame()
end

function Room:startCaughtVideo()
    self.catchAnim = nil
    Cursor.reset()
    if self.room.mov then
        AudioQueue.stopAll()
        self.mode = "caught_video"
        self.caughtPlayer = VideoPlayer.new(
            self.room.mov, {
                onFinish = function()
                    self:finishRoomCapture()
                end
            }
        )
        if self.caughtPlayer then
            return
        end
    end
    local rndIdx = love.math.random(1, 7)
    AudioQueue.clearAndPlay({ group = "endsound", key = "random" .. rndIdx })
    self:finishRoomCapture()
end

function Room:finishRoomCapture()
    if self.caughtPlayer then
        self.caughtPlayer:stop()
        self.caughtPlayer = nil
    end
    SceneManager.switch(App.states.instrum, { roomTitle = self.room.title })
end

function Room:catchMouse(catchX, catchY)
    self.hasMouse = false
    self.mouseSpot = nil
    self.mouseCatchLockTimer = 0
    self.mouseIdleTimer = 0
    Rooms.markRoomCaught(App.session, self.room.id, self.room.title)
    if App.saveProgress then
        App.saveProgress()
    end

    self.traps.active = nil
    self.traps.menuOpen = false
    Cursor.setVisible(false)

    AudioQueue.stopMusic()
    AudioQueue.playSfx("dxr/shared/sounds/s_821.wav", 0.9)

    local startX = math.max(0, math.min(640, catchX or App.lastVx or 320))
    local startY = math.max(0, math.min(440, catchY or App.lastVy or 240))
    local caughtSpan = self.spans["caught"]
    local target = self.meta and self.meta.pos1

    if caughtSpan or target then
        self.mode = "caught"
        if caughtSpan then
            local endF = findCaughtPreVideoEnd(self.score, caughtSpan)
            self.animSpan = { startFrame = caughtSpan.startFrame, endFrame = endF }
            self.animFrameFloat = caughtSpan.startFrame
        else
            self.animSpan = nil
        end
        self.catchAnim = {
            phase = "hang",
            timer = 0,
            wiggleTimer = 0,
            wiggleIdx = 1,
            x = startX,
            y = startY,
            startX = startX,
            startY = startY,
            targetX = target and target.x or startX,
            targetY = target and target.y or startY,
            hasTarget = (target ~= nil),
        }
    else
        self:startCaughtVideo()
    end
end

function Room:update(dt)
    if self.toastTimer > 0 then
        self.toastTimer = self.toastTimer - dt
        if self.toastTimer <= 0 then
            self.toast = nil
        end
    end

    if self.mode == "entering" then
        self.wipeProgress = self.wipeProgress + dt / WIPE_DURATION
        if self.wipeProgress >= 1 then
            self:finishEntering()
        end
        return
    end

    if self.mode == "caught_video" then
        if self.caughtPlayer then
            self.caughtPlayer:update(dt)
        end
        return
    end

    if self.mode == "caught" then
        local anim = self.catchAnim
        if not anim then
            self:startCaughtVideo()
            return
        end

        anim.wiggleTimer = anim.wiggleTimer + dt
        local wiggleStep = 1 / CATCH_WIGGLE_FPS
        while anim.wiggleTimer >= wiggleStep do
            anim.wiggleTimer = anim.wiggleTimer - wiggleStep
            anim.wiggleIdx = (anim.wiggleIdx % #CATCH_DANGLING_CASTS) + 1
        end

        anim.timer = anim.timer + dt
        if anim.phase == "hang" then
            if not App.isTouchMode then
                anim.x = math.max(0, math.min(640, App.lastVx or anim.x))
                anim.y = math.max(0, math.min(440, App.lastVy or anim.y))
            end
            if self.animSpan then
                self.animFrameFloat = self.animSpan.startFrame
            end
            if anim.timer >= CATCH_HANG_DURATION then
                if anim.hasTarget then
                    anim.phase = "move"
                    anim.timer = 0
                    anim.startX = anim.x
                    anim.startY = anim.y
                else
                    self:startCaughtVideo()
                end
            end
        elseif anim.phase == "move" then
            local t = math.min(1, anim.timer / CATCH_MOVE_DURATION)
            anim.x = anim.startX + (anim.targetX - anim.startX) * t
            anim.y = anim.startY + (anim.targetY - anim.startY) * t
            if self.animSpan then
                self.animFrameFloat = self.animSpan.startFrame + (self.animSpan.endFrame - self.animSpan.startFrame) * t
            end
            if anim.timer >= CATCH_MOVE_DURATION then
                anim.x = anim.targetX
                anim.y = anim.targetY
                anim.phase = "hold"
                anim.timer = 0
                if self.animSpan then
                    self.animFrameFloat = self.animSpan.endFrame
                end
            end
        elseif anim.phase == "hold" then
            anim.x = anim.targetX
            anim.y = anim.targetY
            if anim.timer >= CATCH_HOLD_DURATION then
                self:startCaughtVideo()
            end
        end
        return
    end

    Traps.update(self.traps, dt)

    self.loopTickTimer = self.loopTickTimer + dt
    local tickStep = 1 / self.fps
    if self.loopTickTimer >= tickStep then
        self.loopTickTimer = self.loopTickTimer - tickStep
        self.loopTick = self.loopTick + 1
    end

    if self.meta.numLoops > 1 and self.mode ~= "caught" then
        self.loopTimer = self.loopTimer + dt
        if self.loopTimer >= 3.5 then
            self.loopTimer = 0
            self.loopIdx = (self.loopIdx % self.meta.numLoops) + 1
        end
    end

    local autoRunDelay = (self.hasMouse and self.mouseSpot) and getAutoRunDelay() or nil
    if autoRunDelay and (self.mode == "idle" or self.mode == "anim_empty") then
        self.mouseIdleTimer = self.mouseIdleTimer + dt
    end

    if self.mode == "idle" then
        if autoRunDelay and not self.traps.menuOpen and self.mouseIdleTimer >= autoRunDelay then
            if not self:startMouseRun(self.mouseSpot, true) then
                self.mouseIdleTimer = 0
            end
        end
        return
    end

    if not self.animSpan then
        self.mode = "idle"
        self.mouseCatchLockTimer = 0
        return
    end

    local playFps = self.fps
    if self.mode == "mouse_run" then
        if self.mouseCatchLockTimer > 0 then
            self.mouseCatchLockTimer = math.max(0, self.mouseCatchLockTimer - dt)
            if self.mouseCatchLockTimer <= 0 then
                Cursor.setSystem("hand")
            end
        end
        playFps = DIFFICULTY_FPS[App.session.difficulty or 1] or 12
        local progress = (self.animFrameFloat - self.animSpan.startFrame)
                / math.max(1, self.animSpan.endFrame - self.animSpan.startFrame)
        if self.traps.active then
            if not self.traps.active.sprung and progress >= 0.25 then
                Traps.spring(self.traps)
            end
            if self.traps.active.sprung then
                playFps = playFps * 0.42
            end
        end
    end

    self.animFrameFloat = self.animFrameFloat + dt * playFps
    if self.animFrameFloat > self.animSpan.endFrame + 0.99 then
        local finishedMode = self.mode
        if finishedMode == "mouse_run" then
            AudioQueue.playSfx("dxr/shared/sounds/s_822.wav", 0.65)
            self.mouseSpot = self.animDestSpot or self.mouseSpot
            if self.traps.active and self.traps.active.sprung then
                self.traps.active = nil
            end
            self.mouseIdleTimer = 0
        end
        self.mode = "idle"
        self.animSpan = nil
        self.mouseCatchLockTimer = 0
        if finishedMode == "mouse_run" and not App.isTouchMode and App.lastVx and App.lastVy then
            self:mousemoved(App.lastVx, App.lastVy)
        end
    end
end

function Room:mousemoved(vx, vy)
    if self.mode == "entering" or self.mode == "caught" or self.mode == "caught_video" then return end
    if self.mode == "mouse_run" then
        Cursor.setSystem(self:canCatchMouse() and "hand" or "arrow")
        return
    end
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    Cursor.setSystem(hit and "hand" or "arrow")
end

function Room:mousepressed(vx, vy, button)
    if button ~= 1 then return end
    if self.mode == "entering" then
        self:finishEntering()
        return
    end
    if self.mode == "caught" then
        if App.debugMode then
            self:startCaughtVideo()
        end
        return
    end
    if self.mode == "caught_video" then
        if App.debugMode then
            self:finishRoomCapture()
        end
        return
    end

    -- Check popup trap icons first when trap bag menu is open
    if self.traps.menuOpen and (App.session.trapsLeft or 0) > 0 then
        for _, slot in ipairs(Traps.MENU_SLOTS) do
            if pointInRect(vx, vy, slot) then
                Traps.place(self.traps, slot.trapType)
                return
            end
        end
        if not pointInRect(vx, vy, Traps.BAG_RECT) then
            self.traps.menuOpen = false
            return
        end
    end

    -- Catching a running mouse takes priority over hiding-spot zones
    if self.mode == "mouse_run" then
        if self:canCatchMouse() then
            local bounds = DirectorStage.getMouseBounds(self.dxrKey, self:currentFrameNumber(), "shared")
            if bounds then
                local pad = App.isTouchMode and 26 or 14
                if vx >= (bounds.x - pad) and vx <= (bounds.x + bounds.w + pad)
                        and vy >= (bounds.y - pad) and vy <= (bounds.y + bounds.h + pad) then
                    self:catchMouse(vx, vy)
                    return
                end
            end
        end
        -- Allow exiting or opening traps/help even during a run
        if pointInRect(vx, vy, Traps.EXIT_RECT) or pointInRect(vx, vy, Traps.CAT_RECT) then
            self.hotzones:click(vx, vy)
        end
        return
    end

    if self.mode == "idle" then
        self.hotzones:click(vx, vy)
    else
        -- Allow exit button during empty spot animations
        if pointInRect(vx, vy, Traps.EXIT_RECT) then
            SceneManager.switch(App.states.hotel_hub)
        end
    end
end

function Room:keypressed(key)
    if App.debugMode and key == "c" and self.hasMouse and self.mode ~= "caught" and self.mode ~= "caught_video" then
        local cx, cy = 320, 240
        if self.mode == "mouse_run" then
            local bounds = DirectorStage.getMouseBounds(self.dxrKey, self:currentFrameNumber(), "shared")
            if bounds then
                cx, cy = bounds.cx, bounds.cy
            end
        elseif self.mouseSpot and self.meta and self.meta.spots then
            for _, sp in ipairs(self.meta.spots) do
                if sp.spot == self.mouseSpot then
                    cx = sp.x + sp.w * 0.5
                    cy = sp.y + sp.h * 0.5
                    break
                end
            end
        end
        self.wipeProgress = 1
        self:catchMouse(cx, cy)
        return true
    end
    if self.mode == "entering" then
        if key == "space" or key == "return" then
            self:finishEntering()
            return true
        elseif key == "escape" then
            SceneManager.switch(App.states.hotel_hub)
            return true
        end
        return false
    end
    if self.mode == "caught" then
        if App.debugMode and (key == "escape" or key == "space" or key == "return") then
            self:startCaughtVideo()
        end
        return true
    end
    if self.mode == "caught_video" then
        if App.debugMode and (key == "escape" or key == "space" or key == "return") then
            self:finishRoomCapture()
        end
        return true
    end
    if key == "escape" then
        if self.traps.menuOpen then
            self.traps.menuOpen = false
        else
            SceneManager.switch(App.states.hotel_hub)
        end
        return true
    end
    return false
end

function Room:draw(vx, vy)
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    if self.mode == "caught_video" then
        if self.caughtPlayer then
            self.caughtPlayer:draw()
        end
        if App.debugMode then
            love.graphics.setColor(0, 0, 0, 0.55)
            love.graphics.rectangle("fill", 454, 450, 180, 24, 5, 5)
            love.graphics.setColor(0.95, 0.95, 0.95, 0.9)
            love.graphics.printf("Klik / Esc = Overslaan", 454, 455, 180, "center")
        end
        love.graphics.pop()
        return
    end

    local frameNum = self:currentFrameNumber()
    if self.mode == "entering" then
        local wipeW = math.max(1, math.min(640, math.floor(640 * self.wipeProgress)))
        love.graphics.setScissor(0, 0, wipeW, 480)
    end

    local puppetSprites = nil
    if self.mode == "caught" and self.catchAnim then
        puppetSprites = {
            [39] = {
                ch = 39,
                cast = CATCH_DANGLING_CASTS[self.catchAnim.wiggleIdx] or 707,
                x = math.floor(self.catchAnim.x + 0.5),
                y = math.floor(self.catchAnim.y + 0.5),
            },
        }
    elseif self.mode ~= "caught" and self.meta.loopChannel and self.meta.loopChannel > 0 then
        local idleFrame = self:currentIdleFrame()
        local loopSp = DirectorStage.getChannelSprite(self.dxrKey, idleFrame, self.meta.loopChannel)
        if not loopSp then
            local l1 = (self.spans["loop1"] and self.spans["loop1"].startFrame) or 22
            loopSp = DirectorStage.getChannelSprite(self.dxrKey, l1, self.meta.loopChannel)
        end
        if loopSp then
            puppetSprites = { [self.meta.loopChannel] = loopSp }
        end
    end

    -- Hide built-in trap popup channels 41..45 and show our clean interactive menu instead
    DirectorStage.drawFrame(
        self.dxrKey, frameNum, {
            loopTick = self.loopTick,
            puppetSprites = puppetSprites,
            hiddenChannels = { [41] = true, [42] = true, [43] = true, [44] = true, [45] = true }
        }
    )

    if self.mode == "entering" then
        love.graphics.setScissor()
        local wipeX = math.floor(640 * self.wipeProgress)
        love.graphics.setColor(0.9, 0.85, 0.5, 0.35)
        love.graphics.rectangle("fill", wipeX, 0, 2, 480)
    end

    if self.mode ~= "caught" then
        Traps.drawActive(self.traps)
        Traps.drawToolbarHud(self.traps, self.room.title, self.hasMouse)
    end

    if self.toast then
        love.graphics.setColor(0.08, 0.10, 0.14, 0.92)
        love.graphics.rectangle("fill", 150, 14, 340, 28, 6, 6)
        love.graphics.setColor(1, 0.88, 0.35, 1)
        love.graphics.printf(self.toast, 150, 21, 340, "center")
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
        if self.mode == "mouse_run" then
            local b = DirectorStage.getMouseBounds(self.dxrKey, frameNum, "shared")
            if b then
                if self:canCatchMouse() then
                    love.graphics.setColor(0, 1, 0, 0.9)
                else
                    love.graphics.setColor(1, 0.35, 0.2, 0.9)
                end
                love.graphics.rectangle("line", b.x - 14, b.y - 14, b.w + 28, b.h + 28)
            end
        end
        if self.hasMouse then
            love.graphics.setColor(0.2, 1, 0.4, 1)
            local autoRunDelay = getAutoRunDelay()
            local autoText = autoRunDelay
                and string.format("  autoRun=%.1fs", math.max(0, autoRunDelay - (self.mouseIdleTimer or 0)))
                or "  autoRun=off"
            love.graphics.print("mouseSpot=" .. tostring(self.mouseSpot) .. autoText .. "  [C = auto-catch]", 10, 24)
        end
    end

    love.graphics.pop()
end

return Room