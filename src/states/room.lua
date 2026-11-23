-- Data-driven gameplay engine for the 19 standard hotel rooms.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local Hotzone = require("src.core.hotzone")
local SceneManager = require("src.core.scene_manager")
local Traps = require("src.core.traps")
local VideoPlayer = require("src.core.video_player")

local Room = {}

local DIFFICULTY_SPEED = { [1] = 0.78, [2] = 1.10, [3] = 1.45 }
local HINT_VIDEOS = { "cathelp7", "cathelp9", "cathel10", "cathel11" }

local function pointInRect(px, py, r)
    return px >= r.x and px < (r.x + r.w) and py >= r.y and py < (r.y + r.h)
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
    self.toast = nil
    self.toastTimer = 0

    -- Place mouse in a valid hiding spot if this room still has a mouse
    self.hasMouse = App.session.mouseRooms and App.session.mouseRooms[self.room.id] == true
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

    local seen = App.session.seenIntros and App.session.seenIntros[self.room.id]
    if self.room.mov and not seen then
        App.session.seenIntros = App.session.seenIntros or {}
        App.session.seenIntros[self.room.id] = true
        self.mode = "intro"
        self.introPlayer = VideoPlayer.new(self.room.mov, {
            onFinish = function()
                self:finishIntro()
            end,
        })
        if not self.introPlayer then
            self:finishIntro()
        end
    else
        self:finishIntro()
    end
end

function Room:finishIntro()
    if self.introPlayer then
        self.introPlayer:stop()
        self.introPlayer = nil
    end
    self.mode = "idle"
    self:startAmbientAudio()
end

function Room:startAmbientAudio()
    if App.session.musicEnabled ~= false and self.meta.ambientSound then
        AudioQueue.playMusic(self.meta.ambientSound, { loop = true, volume = 0.45 })
    end
end

function Room:exit()
    if self.introPlayer then
        self.introPlayer:stop()
        self.introPlayer = nil
    end
    AudioQueue.stopAll()
    Cursor.reset()
end

function Room:onFocus(focused)
    if self.introPlayer then
        if focused then self.introPlayer:resume() else self.introPlayer:pause() end
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
            end,
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
        end,
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
        end,
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
            Traps.openCatHint(HINT_VIDEOS[idx], function()
                AudioQueue.resumeAll()
            end)
        end,
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

function Room:triggerSpot(spotId)
    self.traps.menuOpen = false
    self:playSpotSound(spotId)

    if self.hasMouse and spotId == self.mouseSpot then
        local dest, span = self:findMouseRunSpan(spotId)
        if span then
            AudioQueue.playSfx("dxr/shared/sounds/s_821.wav", 0.7)
            self.mode = "mouse_run"
            self.animSpan = span
            self.animFrameFloat = span.startFrame
            self.animDestSpot = dest
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

function Room:catchMouse()
    self.hasMouse = false
    self.mouseSpot = nil
    App.session.mouseRooms[self.room.id] = false
    App.session.caughtMice = App.session.caughtMice or {}
    App.session.caughtMice[self.room.id] = true

    local count = 0
    for _, v in pairs(App.session.caughtMice) do
        if v then count = count + 1 end
    end
    App.session.caughtCount = count

    AudioQueue.playSfx("dxr/shared/sounds/s_821.wav", 0.9)
    local rndIdx = love.math.random(1, 7)
    AudioQueue.clearAndPlay({ group = "endsound", key = "random" .. rndIdx })

    local caughtSpan = self.spans["caught"]
    if caughtSpan then
        self.mode = "caught"
        self.animSpan = caughtSpan
        self.animFrameFloat = caughtSpan.startFrame
    else
        SceneManager.switch(App.states.hotel_hub, { justCaught = self.room.title })
    end
end

function Room:update(dt)
    if self.toastTimer > 0 then
        self.toastTimer = self.toastTimer - dt
        if self.toastTimer <= 0 then
            self.toast = nil
        end
    end

    if self.mode == "intro" then
        if self.introPlayer then
            self.introPlayer:update(dt)
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

    if self.mode == "idle" then
        if self.meta.numLoops > 1 then
            self.loopTimer = self.loopTimer + dt
            if self.loopTimer >= 3.5 then
                self.loopTimer = 0
                self.loopIdx = (self.loopIdx % self.meta.numLoops) + 1
            end
        end
        return
    end

    if not self.animSpan then
        self.mode = "idle"
        return
    end

    local speedMult = 1.0
    if self.mode == "mouse_run" then
        speedMult = DIFFICULTY_SPEED[App.session.difficulty or 1] or 1.0
        local progress = (self.animFrameFloat - self.animSpan.startFrame) /
            math.max(1, self.animSpan.endFrame - self.animSpan.startFrame)
        if self.traps.active then
            if not self.traps.active.sprung and progress >= 0.25 then
                Traps.spring(self.traps)
            end
            if self.traps.active.sprung then
                speedMult = speedMult * 0.42
            end
        end
    end

    self.animFrameFloat = self.animFrameFloat + dt * self.fps * speedMult
    if self.animFrameFloat > self.animSpan.endFrame + 0.99 then
        if self.mode == "caught" then
            SceneManager.switch(App.states.hotel_hub, { justCaught = self.room.title })
            return
        elseif self.mode == "mouse_run" then
            AudioQueue.playSfx("dxr/shared/sounds/s_822.wav", 0.65)
            self.mouseSpot = self.animDestSpot or self.mouseSpot
            if self.traps.active and self.traps.active.sprung then
                self.traps.active = nil
            end
            self:showToast("Mis! De muis heeft zich weer verstopt!")
        end
        self.mode = "idle"
        self.animSpan = nil
    end
end

function Room:mousemoved(vx, vy)
    if self.mode == "intro" then return end
    if self.mode == "mouse_run" then
        Cursor.setSystem("hand")
        return
    end
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    Cursor.setSystem(hit and "hand" or "arrow")
end

function Room:mousepressed(vx, vy, button)
    if button ~= 1 then return end
    if self.mode == "intro" then
        self:finishIntro()
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
    end

    -- Catching a running mouse takes priority over hiding-spot zones
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
    if self.mode == "intro" then
        if key == "escape" or key == "space" or key == "return" then
            self:finishIntro()
            return true
        end
        return false
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

    if self.mode == "intro" then
        if self.introPlayer then
            self.introPlayer:draw()
        end
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 454, 450, 180, 24, 5, 5)
        love.graphics.setColor(0.95, 0.95, 0.95, 0.9)
        love.graphics.printf("Klik / Esc = Overslaan", 454, 455, 180, "center")
        love.graphics.pop()
        return
    end

    local frameNum = self:currentFrameNumber()
    -- Hide built-in trap popup channels 41..45 and show our clean interactive menu instead
    DirectorStage.drawFrame(self.dxrKey, frameNum, {
        loopTick = self.loopTick,
        hiddenChannels = { [41] = true, [42] = true, [43] = true, [44] = true, [45] = true },
    })

    Traps.drawActive(self.traps)
    Traps.drawToolbarHud(self.traps, self.room.title, self.hasMouse)

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
                love.graphics.setColor(0, 1, 0, 0.9)
                love.graphics.rectangle("line", b.x - 14, b.y - 14, b.w + 28, b.h + 28)
            end
        end
        if self.mouseSpot then
            love.graphics.setColor(0.2, 1, 0.4, 1)
            love.graphics.print("mouseSpot=" .. tostring(self.mouseSpot), 10, 24)
        end
    end

    love.graphics.pop()
end

return Room
