-- Backstage Instrument Matching (INSTRUM.DXR): match the caught mouse to its instrument.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local Hotzone = require("src.core.hotzone")
local SceneManager = require("src.core.scene_manager")
local Traps = require("src.core.traps")
local Rooms = require("src.data.rooms")

local Instrum = {}

local REJECT_COOLDOWN = 1.0

local function pickTargetInstrument()
    App.session.foundInstruments = App.session.foundInstruments or {}
    local buildKey = "build" .. tostring(App.session.buildIndex or 1)
    local order = Assets.getMusicBuild(buildKey)
    if order then
        for _, tok in ipairs(order) do
            local id = Rooms.normalizeInstrumentId(tok)
            if not App.session.foundInstruments[id] and Rooms.INSTRUMENTS_BY_ID[id] then
                return Rooms.INSTRUMENTS_BY_ID[id]
            end
        end
    end
    for _, inst in ipairs(Rooms.INSTRUMENTS) do
        if not App.session.foundInstruments[inst.id] then
            return inst
        end
    end
    return Rooms.INSTRUMENTS[1]
end

function Instrum:enter(params)
    Cursor.reset()
    AudioQueue.stopAll()

    self.roomTitle = (params and params.roomTitle) or "Hotelkamer"
    self.score = Assets.getDxr("instrum")
    self.orderedLabels, self.spans = DirectorStage.getLabelSpans("instrum")
    self.fps = (self.score and self.score.fps) or 11

    self.target = pickTargetInstrument()
    self.selectFrame = (self.spans["select"] and self.spans["select"].startFrame) or 4
    self.mode = "select" -- select | reject | accept_intro | accept_loop | bored
    self.animSpan = nil
    self.animFrameFloat = self.selectFrame
    self.idleTimer = 0
    self.soloTimer = 0
    self.soloStarted = false
    self.hoveredFamily = nil
    self.rejectCooldown = 0
    self.rejectSfxSource = nil

    self:buildHotzones()
end

function Instrum:stopRejectSfx()
    if self.rejectSfxSource then
        self.rejectSfxSource:stop()
        self.rejectSfxSource = nil
    end
end

function Instrum:canChooseInstrument()
    if self.rejectCooldown > 0 then
        return false
    end
    return self.mode == "select" or self.mode == "bored" or self.mode == "reject"
end

function Instrum:exit()
    self:stopRejectSfx()
    AudioQueue.stopAll()
    Cursor.reset()
end

function Instrum:buildHotzones()
    self.hotzones = Hotzone.new()
    local frame = self.score and self.score.frames and self.score.frames[self.selectFrame]
    local byCh = {}
    if frame then
        for _, sp in ipairs(frame) do
            byCh[sp.ch] = sp
        end
    end

    for _, fam in ipairs(Rooms.INSTRUM_FAMILIES) do
        local sp = byCh[fam.ch]
        local cast = sp and self.score.casts[sp.cast]
        if sp and cast and cast.w and cast.h then
            local rx = cast.reg_x or 0
            local ry = cast.reg_y or 0
            self.hotzones:add({
                id = "fam_" .. fam.family,
                family = fam,
                x = sp.x - rx,
                y = sp.y - ry,
                w = cast.w,
                h = cast.h,
                onHover = function()
                    self.hoveredFamily = fam
                end,
                onLeave = function()
                    if self.hoveredFamily and self.hoveredFamily.family == fam.family then
                        self.hoveredFamily = nil
                    end
                end,
                onClick = function()
                    if self:canChooseInstrument() then
                        self:chooseFamily(fam)
                    end
                end,
            })
        end
    end

    self.hotzones:add({
        id = "instrum_skip",
        x = 16,
        y = 442,
        w = 56,
        h = 36,
        onClick = function()
            self:completeMatching()
        end,
    })

    self.hotzones:add({
        id = "instrum_cat",
        x = 574,
        y = 442,
        w = 60,
        h = 36,
        onClick = function()
            AudioQueue.pauseAll()
            Traps.openCatHint("cathel10", function()
                AudioQueue.resumeAll()
            end)
        end,
    })
end

function Instrum:chooseFamily(fam)
    self.idleTimer = 0
    self:stopRejectSfx()
    if fam.family == self.target.family then
        self.rejectCooldown = 0
        App.session.foundInstruments = App.session.foundInstruments or {}
        App.session.foundInstruments[self.target.id] = true
        App.session.lastInstrument = self.target.id

        self.soloTimer = 0
        self.soloStarted = false
        if App.session.musicEnabled ~= false then
            AudioQueue.playMusic({ group = "solos", key = self.target.id }, { loop = false, volume = 0.82 })
            self.soloStarted = true
        end

        local introSpan = self.spans[self.target.instrumLabel]
        if introSpan then
            self.mode = "accept_intro"
            self.animSpan = introSpan
            self.animFrameFloat = introSpan.startFrame
        else
            local loopSpan = self.spans[self.target.loopLabel]
            self.mode = "accept_loop"
            self.animSpan = loopSpan
            self.animFrameFloat = loopSpan and loopSpan.startFrame or self.selectFrame
        end
    else
        self.rejectCooldown = REJECT_COOLDOWN
        if fam.rejectSfx then
            self.rejectSfxSource = AudioQueue.playSfx(fam.rejectSfx, 0.85)
        end
        local rSpan = self.spans[fam.rejectLabel] or self.spans["reject general"]
        if rSpan then
            self.mode = "reject"
            self.animSpan = rSpan
            self.animFrameFloat = rSpan.startFrame
        end
        if not App.isTouchMode and App.lastVx and App.lastVy then
            self:mousemoved(App.lastVx, App.lastVy)
        end
    end
end

function Instrum:completeMatching()
    self:stopRejectSfx()
    App.session.foundInstruments = App.session.foundInstruments or {}
    App.session.foundInstruments[self.target.id] = true
    App.session.lastInstrument = self.target.id
    SceneManager.switch(App.states.orch, {
        roomTitle = self.roomTitle,
        latestInstrument = self.target.id,
        previewOnly = false,
    })
end

function Instrum:update(dt)
    if self.rejectCooldown > 0 then
        self.rejectCooldown = math.max(0, self.rejectCooldown - dt)
        if self.rejectCooldown == 0 and not App.isTouchMode and App.lastVx and App.lastVy then
            self:mousemoved(App.lastVx, App.lastVy)
        end
    end

    if self.mode == "select" then
        self.idleTimer = self.idleTimer + dt
        if self.idleTimer >= 14.0 and self.spans["bored"] then
            self.idleTimer = 0
            self.mode = "bored"
            self.animSpan = self.spans["bored"]
            self.animFrameFloat = self.animSpan.startFrame
        end
        return
    end

    if self.mode == "accept_intro" or self.mode == "accept_loop" then
        self.soloTimer = self.soloTimer + dt
        local playing = AudioQueue.musicSource and AudioQueue.musicSource:isPlaying()
        if (self.soloStarted and not playing and self.soloTimer >= 1.5) or (not self.soloStarted and self.soloTimer >= 3.5) then
            self:completeMatching()
            return
        end
    end

    if not self.animSpan then
        self.mode = "select"
        return
    end

    self.animFrameFloat = self.animFrameFloat + dt * self.fps
    if self.animFrameFloat > self.animSpan.endFrame + 0.99 then
        if self.mode == "accept_intro" then
            local loopSpan = self.spans[self.target.loopLabel]
            if loopSpan then
                self.mode = "accept_loop"
                self.animSpan = loopSpan
                self.animFrameFloat = loopSpan.startFrame
            else
                self:completeMatching()
            end
        elseif self.mode == "accept_loop" then
            self.animFrameFloat = self.animSpan.startFrame
        else
            self.mode = "select"
            self.animSpan = nil
        end
    end
end

function Instrum:mousemoved(vx, vy)
    if self.mode == "accept_intro" or self.mode == "accept_loop" then
        Cursor.setSystem("hand")
        return
    end
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    local clickable = (hit ~= nil) and (not hit.family or self:canChooseInstrument())
    Cursor.setSystem(clickable and "hand" or "arrow")
end

function Instrum:mousepressed(vx, vy, button)
    if button ~= 1 then return end
    if self.mode == "accept_intro" or self.mode == "accept_loop" then
        self:completeMatching()
        return
    end
    self.hotzones:click(vx, vy)
end

function Instrum:keypressed(key)
    if self.mode == "accept_intro" or self.mode == "accept_loop" then
        if key == "space" or key == "return" or key == "escape" then
            self:completeMatching()
            return true
        end
        return false
    end
    if key == "escape" then
        self:completeMatching()
        return true
    end
    return false
end

function Instrum:draw(vx, vy)
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    local frameNum = self.selectFrame
    if self.mode ~= "select" and self.animSpan then
        frameNum = math.max(self.animSpan.startFrame, math.min(self.animSpan.endFrame, math.floor(self.animFrameFloat)))
    end

    DirectorStage.drawFrame("instrum", frameNum)

    -- Status pill inside the bottom bar
    love.graphics.setColor(0.10, 0.12, 0.16, 0.88)
    love.graphics.rectangle("fill", 90, 449, 466, 24, 5, 5)
    love.graphics.setColor(0.95, 0.92, 0.68, 1)
    local msg
    if self.mode == "accept_intro" or self.mode == "accept_loop" then
        msg = string.format("Gevonden: %s! • Klik of druk op Esc voor het orkest", self.target.name)
    elseif self.hoveredFamily then
        msg = string.format("Welk instrument hoort bij deze muis? • %s", self.hoveredFamily.label)
    else
        msg = "Welk instrument hoort bij deze muis? • Klik op het juiste instrument"
    end
    love.graphics.printf(msg, 96, 454, 454, "center")

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
        love.graphics.setColor(0.2, 1, 0.4, 1)
        love.graphics.print("target=" .. self.target.id .. " (" .. self.target.family .. ")", 10, 24)
    end
    love.graphics.pop()
end

return Instrum
