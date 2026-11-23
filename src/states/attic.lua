-- Multi-subroom Attic (ATTIC.DXR): 6 connected attic rooms with mini-map & detector dot.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local Hotzone = require("src.core.hotzone")
local SceneManager = require("src.core.scene_manager")
local Traps = require("src.core.traps")

local Attic = {}

local DIFFICULTY_FPS = { [1] = 8, [2] = 12, [3] = 16 }
local MINIMAP_MOUSE_DOTS = {
    [1] = { x = 487, y = 428 },
    [2] = { x = 487, y = 401 },
    [3] = { x = 517, y = 398 },
    [4] = { x = 544, y = 398 },
    [5] = { x = 572, y = 401 },
    [6] = { x = 572, y = 428 },
}

local function pointInRect(px, py, r)
    return px >= r.x and px < (r.x + r.w) and py >= r.y and py < (r.y + r.h)
end

function Attic:enter()
    Cursor.reset()
    AudioQueue.stopAll()

    self.dxrKey = "attic"
    self.score = Assets.getDxr(self.dxrKey)
    self.orderedLabels, self.spans = DirectorStage.getLabelSpans(self.dxrKey)
    self.fps = (self.score and self.score.fps) or 13

    self.curRoom = 1
    self.mode = "idle"
    self.animSpan = nil
    self.animFrameFloat = 1
    self.traps = Traps.newState({ x = 320, y = 365 })
    self.toast = nil
    self.toastTimer = 0
    self.pulseTimer = 0

    self.hasMouse = App.session.mouseRooms and App.session.mouseRooms["attic"] == true
    if self.hasMouse then
        self.mouseRoom = love.math.random(1, 6)
        self.mouseSpot = love.math.random(1, 3)
    else
        self.mouseRoom = nil
        self.mouseSpot = nil
    end

    if App.session.musicEnabled ~= false then
        local amb = self.score and self.score.casts[230] and self.score.casts[230].sound
        if amb then
            AudioQueue.playMusic(amb, { loop = true, volume = 0.45 })
        end
    end

    self:rebuildHotzones()
end

function Attic:exit()
    AudioQueue.stopAll()
    Cursor.reset()
end

function Attic:getIdleFrame(roomIdx)
    local lbl = "r" .. tostring(roomIdx) .. "a"
    return (self.spans[lbl] and self.spans[lbl].startFrame) or 7
end

function Attic:rebuildHotzones()
    self.hotzones = Hotzone.new()
    local idleFrame = self:getIdleFrame(self.curRoom)
    local frame = self.score and self.score.frames[idleFrame]
    if frame then
        for _, sp in ipairs(frame) do
            -- Hiding spots on channels 30..32
            if sp.ch >= 30 and sp.ch <= 32 then
                local spotIdx = sp.ch - 29
                self.hotzones:add({
                    id = "attic_spot_" .. spotIdx,
                    spot = spotIdx,
                    x = sp.x,
                    y = sp.y,
                    w = sp.w,
                    h = sp.h,
                    onClick = function()
                        if self.mode == "idle" then
                            self:triggerSpot(spotIdx)
                        end
                    end,
                })
            elseif sp.ch >= 34 and sp.ch <= 39 then
                -- Mini-map rooms 1..6 (bitmap casts 207..212)
                local targetRoom = sp.ch - 33
                local cast = self.score.casts[sp.cast]
                if cast and cast.w and cast.h then
                    local rx = cast.reg_x or 0
                    local ry = cast.reg_y or 0
                    self.hotzones:add({
                        id = "attic_map_" .. targetRoom,
                        x = sp.x - rx,
                        y = sp.y - ry,
                        w = cast.w,
                        h = cast.h,
                        onClick = function()
                            if self.mode == "idle" and self.curRoom ~= targetRoom then
                                self.curRoom = targetRoom
                                self.traps.menuOpen = false
                                self:rebuildHotzones()
                            end
                        end,
                    })
                end
            end
        end
    end

    self.hotzones:add({
        id = "attic_exit",
        x = 12,
        y = 442,
        w = 62,
        h = 36,
        onClick = function()
            SceneManager.switch(App.states.hotel_hub)
        end,
    })

    self.hotzones:add({
        id = "attic_trap_bag",
        x = 530,
        y = 444,
        w = 46,
        h = 34,
        onClick = function()
            if (App.session.trapsLeft or 0) <= 0 then
                self:showToast("Geen muizenvallen meer!")
                return
            end
            self.traps.menuOpen = not self.traps.menuOpen
        end,
    })

    self.hotzones:add({
        id = "attic_cat",
        x = 576,
        y = 442,
        w = 60,
        h = 36,
        onClick = function()
            AudioQueue.pauseAll()
            Traps.openCatHint("cathelp9", function()
                AudioQueue.resumeAll()
            end)
        end,
    })
end

function Attic:showToast(msg)
    self.toast = msg
    self.toastTimer = 2.2
end

function Attic:triggerSpot(spotIdx)
    self.traps.menuOpen = false
    local sndNum = (self.curRoom - 1) * 3 + spotIdx
    local sndKey = "att" .. tostring(sndNum)
    if Assets.getAudioPath("sounds", sndKey) then
        AudioQueue.playSfx({ group = "sounds", key = sndKey }, 0.85)
    end

    if self.hasMouse and self.curRoom == self.mouseRoom and spotIdx == self.mouseSpot then
        local variant = love.math.random(1, 2)
        local lbl = string.format("m%d%d:%d", self.curRoom, spotIdx, variant)
        local span = self.spans[lbl] or self.spans[string.format("m%d%d:1", self.curRoom, spotIdx)]
        if span then
            AudioQueue.playSfx("dxr/shared/sounds/s_821.wav", 0.7)
            self.mode = "mouse_run"
            self.animSpan = span
            self.animFrameFloat = span.startFrame
            return
        end
    end

    local emptyLbl = string.format("a%d%d", self.curRoom, spotIdx)
    local span = self.spans[emptyLbl]
    if span then
        self.mode = "anim_empty"
        self.animSpan = span
        self.animFrameFloat = span.startFrame
    end
end

function Attic:catchMouse()
    self.hasMouse = false
    self.mouseRoom = nil
    self.mouseSpot = nil
    App.session.mouseRooms["attic"] = false
    App.session.caughtMice = App.session.caughtMice or {}
    App.session.caughtMice["attic"] = true

    local count = 0
    for _, v in pairs(App.session.caughtMice) do
        if v then count = count + 1 end
    end
    App.session.caughtCount = count

    AudioQueue.playSfx("dxr/shared/sounds/s_821.wav", 0.9)
    AudioQueue.clearAndPlay({ group = "endsound", key = "atticend" })

    local endSpan = self.spans["end" .. tostring(self.curRoom)]
    if endSpan then
        self.mode = "caught"
        self.animSpan = endSpan
        self.animFrameFloat = endSpan.startFrame
    else
        SceneManager.switch(App.states.instrum, { roomTitle = "Zolder" })
    end
end

function Attic:currentFrameNumber()
    if self.mode == "idle" then
        return self:getIdleFrame(self.curRoom)
    elseif self.animSpan then
        return math.max(self.animSpan.startFrame, math.min(self.animSpan.endFrame, math.floor(self.animFrameFloat)))
    end
    return self:getIdleFrame(self.curRoom)
end

function Attic:update(dt)
    self.pulseTimer = self.pulseTimer + dt
    if self.toastTimer > 0 then
        self.toastTimer = self.toastTimer - dt
        if self.toastTimer <= 0 then
            self.toast = nil
        end
    end

    Traps.update(self.traps, dt)

    if self.mode == "idle" or not self.animSpan then
        return
    end

    local playFps = self.fps
    if self.mode == "mouse_run" then
        playFps = DIFFICULTY_FPS[App.session.difficulty or 1] or 12
        local progress = (self.animFrameFloat - self.animSpan.startFrame) /
            math.max(1, self.animSpan.endFrame - self.animSpan.startFrame)
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
        if self.mode == "caught" then
            SceneManager.switch(App.states.instrum, { roomTitle = "Zolder" })
            return
        elseif self.mode == "mouse_run" then
            AudioQueue.playSfx("dxr/shared/sounds/s_822.wav", 0.65)
            -- Move mouse to an adjacent attic subroom
            local delta = (love.math.random(1, 2) == 1) and 1 or -1
            self.mouseRoom = ((self.curRoom - 1 + delta) % 6) + 1
            self.mouseSpot = love.math.random(1, 3)
            if self.traps.active and self.traps.active.sprung then
                self.traps.active = nil
            end
            self:showToast("Ontsnapt naar een andere zolderkamer!")
        end
        self.mode = "idle"
        self.animSpan = nil
    end
end

function Attic:mousemoved(vx, vy)
    if self.mode == "mouse_run" then
        Cursor.setSystem("hand")
        return
    end
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    Cursor.setSystem(hit and "hand" or "arrow")
end

function Attic:mousepressed(vx, vy, button)
    if button ~= 1 then return end

    if self.traps.menuOpen and (App.session.trapsLeft or 0) > 0 then
        for _, slot in ipairs(Traps.MENU_SLOTS) do
            if pointInRect(vx, vy, slot) then
                Traps.place(self.traps, slot.trapType)
                return
            end
        end
    end

    if self.mode == "mouse_run" then
        local bounds = DirectorStage.getMouseBounds(self.dxrKey, self:currentFrameNumber(), "shared")
        if bounds then
            local pad = App.isTouchMode and 26 or 14
            if vx >= (bounds.x - pad) and vx <= (bounds.x + bounds.w + pad)
               and vy >= (bounds.y - pad) and vy <= (bounds.y + bounds.h + pad) then
                self:catchMouse()
                return
            end
        end
        if pointInRect(vx, vy, Traps.EXIT_RECT) then
            SceneManager.switch(App.states.hotel_hub)
        end
        return
    end

    if self.mode == "idle" then
        self.hotzones:click(vx, vy)
    elseif pointInRect(vx, vy, Traps.EXIT_RECT) then
        SceneManager.switch(App.states.hotel_hub)
    end
end

function Attic:keypressed(key)
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

function Attic:draw(vx, vy)
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    local frameNum = self:currentFrameNumber()
    DirectorStage.drawFrame(self.dxrKey, frameNum, {
        hiddenChannels = { [41] = true },
    })

    -- Draw active subroom indicator on mini-map
    local curDot = MINIMAP_MOUSE_DOTS[self.curRoom]
    if curDot then
        love.graphics.setColor(0.95, 0.85, 0.25, 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", curDot.x, curDot.y, 8)
    end

    -- Draw pulsing green mouse-detector dot on the mini-map subroom where the mouse hides
    if self.hasMouse and self.mouseRoom then
        local mDot = MINIMAP_MOUSE_DOTS[self.mouseRoom]
        if mDot then
            local alpha = 0.55 + 0.45 * math.sin(self.pulseTimer * 6)
            love.graphics.setColor(0.2, 1.0, 0.3, alpha)
            love.graphics.circle("fill", mDot.x, mDot.y, 4)
        end
    end

    Traps.drawActive(self.traps)
    Traps.drawToolbarHud(self.traps, "Zolder " .. self.curRoom .. "/6", self.hasMouse and (self.curRoom == self.mouseRoom))

    if self.toast then
        love.graphics.setColor(0.08, 0.10, 0.14, 0.92)
        love.graphics.rectangle("fill", 150, 14, 340, 28, 6, 6)
        love.graphics.setColor(1, 0.88, 0.35, 1)
        love.graphics.printf(self.toast, 150, 21, 340, "center")
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
    end
    love.graphics.pop()
end

return Attic
