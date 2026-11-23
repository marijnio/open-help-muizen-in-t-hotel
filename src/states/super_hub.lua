-- Bonus Mode 2: Super Spel Hub (super_ggmdmenu Frame 9 & Top-5 ScoreBoard).
-- Uses the Mouse-Detector TV scanner to locate and enter the active room,
-- tracks 0..19 caught mice & cumulative score, and displays the High Scores board.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local ConfirmDialog = require("src.core.confirm_dialog")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local Hotzone = require("src.core.hotzone")
local SceneManager = require("src.core.scene_manager")
local SuperScores = require("src.core.super_scores")
local Rooms = require("src.data.rooms")

local SuperHub = {}

local DETECTOR_BLINK_INTERVAL = 0.25
local TOTAL_MICE = 19

local function pickRandomStandardRoomId(excludeId)
    local pool = {}
    for i = 1, TOTAL_MICE do
        local r = Rooms.LIST[i]
        if r and r.id ~= excludeId then
            table.insert(pool, r.id)
        end
    end
    if #pool == 0 then
        return "artist"
    end
    return pool[love.math.random(1, #pool)]
end

function SuperHub.newSession()
    return {
        score = 0,
        caughtCount = 0,
        activeRoomId = pickRandomStandardRoomId(nil),
        escapeCount = 0,
        finished = false,
        recordedRank = nil,
    }
end

function SuperHub:enter(params)
    Cursor.reset()
    AudioQueue.stopVo()
    self.scoreData = Assets.getDxr("super_ggmdmenu")
    self.sharedData = Assets.getDxr("super_shared")
    self.frameNum = DirectorStage.getLabelFrame("super_ggmdmenu", "select") or 9

    params = params or {}
    if params.newGame or not App.superSession then
        App.superSession = SuperHub.newSession()
    end

    self.detectedRoom = nil
    self.blinkTimer = 0
    self.blinkOn = true
    self.touchSelectedRoomId = nil
    self.scannerVisible = false
    self.scanSfxSource = nil
    self.showingScores = false
    self.highScores = SuperScores.load()
    self.lastRank = App.superSession.recordedRank
    self.banner = nil
    self.bannerTimer = 0

    if params.justCaught then
        self.banner = string.format(
            "Gevangen in %s! +%d punten (%d/19)",
            params.justCaught,
            params.pointsEarned or 0,
            App.superSession.caughtCount or 0
        )
        self.bannerTimer = 3.2
    end

    if (App.superSession.caughtCount or 0) >= TOTAL_MICE then
        App.superSession.finished = true
        if not App.superSession.recordedRank then
            local list, rank = SuperScores.record(App.superSession.score, "Speler")
            self.highScores = list
            self.lastRank = rank
            App.superSession.recordedRank = rank or 0
        end
        self.showingScores = true
    elseif params.showScores then
        self.showingScores = true
    end

    self:buildHotzones()
    if not self.showingScores and not App.isTouchMode and App.lastVx and App.lastVy then
        self:mousemoved(App.lastVx, App.lastVy)
    end
end

function SuperHub:stopHoverAudio()
    AudioQueue.stopVo()
    if self.scanSfxSource then
        self.scanSfxSource:stop()
        self.scanSfxSource = nil
    end
end

function SuperHub:exit()
    self:stopHoverAudio()
    Cursor.reset()
end

function SuperHub:buildHotzones()
    self.hotzones = Hotzone.new()

    local frame = self.scoreData and self.scoreData.frames and self.scoreData.frames[self.frameNum]
    local byCh = {}
    if frame then
        for _, sp in ipairs(frame) do
            byCh[sp.ch] = sp
        end
    end

    -- Channels 5..23 correspond to Rooms.LIST[1..19] (standard hotel rooms)
    for i = 1, TOTAL_MICE do
        local room = Rooms.LIST[i]
        local sp = byCh[4 + i]
        local rx = (sp and sp.x) or room.x
        local ry = (sp and sp.y) or room.y
        local rw = (sp and sp.w and sp.w > 0) and sp.w or room.w
        local rh = (sp and sp.h and sp.h > 0) and sp.h or room.h

        self.hotzones:add({
            id = "super_room_" .. room.id,
            room = room,
            x = rx,
            y = ry,
            w = rw,
            h = rh,
            onHover = function()
                if not self.showingScores then
                    self:onRoomHover(room)
                end
            end,
            onLeave = function()
                if self.detectedRoom and self.detectedRoom.id == room.id then
                    self.detectedRoom = nil
                    self:stopHoverAudio()
                end
            end,
            onClick = function()
                if not self.showingScores then
                    self:onRoomClick(room)
                end
            end,
        })
    end

    self.hotzones:add({
        id = "super_exit",
        x = 18,
        y = 440,
        w = 54,
        h = 39,
        onClick = function()
            self.touchSelectedRoomId = nil
            self:promptExit()
        end,
    })

    self.hotzones:add({
        id = "super_scores_toggle",
        x = 538,
        y = 448,
        w = 90,
        h = 26,
        onClick = function()
            self.touchSelectedRoomId = nil
            self:toggleScores()
        end,
    })

    -- Scoreboard overlay buttons
    self.hotzones:add({
        id = "scores_replay",
        x = 170,
        y = 418,
        w = 140,
        h = 34,
        enabled = self.showingScores,
        onClick = function()
            App.superSession = SuperHub.newSession()
            self.showingScores = false
            self.banner = nil
            self:syncScoreZones()
            Cursor.reset()
        end,
    })

    self.hotzones:add({
        id = "scores_close",
        x = 330,
        y = 418,
        w = 140,
        h = 34,
        enabled = self.showingScores,
        onClick = function()
            if App.superSession and App.superSession.finished then
                SceneManager.switch(App.states.launcher)
            else
                self.showingScores = false
                self:syncScoreZones()
            end
        end,
    })
end

function SuperHub:syncScoreZones()
    for _, z in ipairs(self.hotzones.zones) do
        if z.id == "scores_replay" or z.id == "scores_close" then
            z.enabled = self.showingScores
        elseif z.id:match("^super_room_") or z.id == "super_exit" or z.id == "super_scores_toggle" then
            z.enabled = not self.showingScores
        end
    end
end

function SuperHub:toggleScores()
    self.showingScores = not self.showingScores
    if self.showingScores then
        self:stopHoverAudio()
        self.highScores = SuperScores.load()
        Cursor.setVisible(true)
    end
    self:syncScoreZones()
end

function SuperHub:roomHasMouse(roomId)
    return App.superSession and not App.superSession.finished and App.superSession.activeRoomId == roomId
end

function SuperHub:onRoomHover(room)
    if self:roomHasMouse(room.id) then
        if self.detectedRoom ~= room then
            self.blinkTimer = 0
            self.blinkOn = true
        end
        self.detectedRoom = room
        if not App.isTouchMode then
            self:stopHoverAudio()
            self.scanSfxSource = AudioQueue.playSfx("dxr/super_ggmdmenu/sounds/s_27.wav", 0.55)
            if room.startsnd and (App.session.musicEnabled ~= false) then
                AudioQueue.clearAndPlay({ group = "startsnd", key = room.startsnd })
            end
        end
    else
        self.detectedRoom = nil
        self:stopHoverAudio()
    end
end

function SuperHub:onRoomClick(room)
    if App.isTouchMode and self.touchSelectedRoomId ~= room.id then
        self.touchSelectedRoomId = room.id
        if self:roomHasMouse(room.id) then
            self.blinkTimer = 0
            self.blinkOn = true
            self.detectedRoom = room
            self:stopHoverAudio()
            self.scanSfxSource = AudioQueue.playSfx("dxr/super_ggmdmenu/sounds/s_27.wav", 0.55)
            if room.startsnd and (App.session.musicEnabled ~= false) then
                AudioQueue.clearAndPlay({ group = "startsnd", key = room.startsnd })
            end
        else
            self.detectedRoom = nil
            self:stopHoverAudio()
        end
        return
    end

    if not self:roomHasMouse(room.id) then
        return
    end

    App.superSession.escapeCount = 0
    SceneManager.switch(App.states.super_room, { roomId = room.id })
end

function SuperHub:promptExit()
    self:stopHoverAudio()
    Cursor.reset()
    SceneManager.setOverlay(ConfirmDialog, {
        title = "Super Spel verlaten",
        message = "Wil je terug naar het hoofdmenu?",
        buttons = {
            {
                label = "Ja",
                key = "return",
                action = function()
                    SceneManager.clearOverlay()
                    SceneManager.switch(App.states.launcher)
                end,
            },
            {
                label = "Nee",
                key = "escape",
                action = function()
                    SceneManager.clearOverlay()
                end,
            },
        },
    })
end

function SuperHub:update(dt)
    if self.bannerTimer > 0 then
        self.bannerTimer = self.bannerTimer - dt
        if self.bannerTimer <= 0 then
            self.banner = nil
        end
    end

    if self.detectedRoom and not self.showingScores then
        self.blinkTimer = self.blinkTimer + dt
        while self.blinkTimer >= DETECTOR_BLINK_INTERVAL do
            self.blinkTimer = self.blinkTimer - DETECTOR_BLINK_INTERVAL
            self.blinkOn = not self.blinkOn
        end
    else
        self.blinkTimer = 0
        self.blinkOn = true
    end
end

function SuperHub:mousemoved(vx, vy)
    local hit = self.hotzones:updateHover(vx, vy, App.isTouchMode)
    if self.showingScores then
        Cursor.setVisible(true)
        Cursor.setSystem(hit and "hand" or "arrow")
        return
    end
    local inHotelArea = (not App.isTouchMode) and vy < 435
    self.scannerVisible = inHotelArea
    if inHotelArea then
        Cursor.setVisible(false)
    else
        Cursor.setVisible(true)
        Cursor.setSystem(hit and "hand" or "arrow")
    end
end

function SuperHub:mousepressed(vx, vy, button)
    if button ~= 1 then return end
    local hit = self.hotzones:click(vx, vy)
    if not hit and not self.showingScores then
        self.touchSelectedRoomId = nil
        self.detectedRoom = nil
        self:stopHoverAudio()
    end
end

function SuperHub:keypressed(key)
    if key == "escape" then
        if self.showingScores and not (App.superSession and App.superSession.finished) then
            self:toggleScores()
        else
            self:promptExit()
        end
        return true
    end
    return false
end

function SuperHub:drawScoreboard()
    local boardCast = self.scoreData and self.scoreData.casts and self.scoreData.casts[69]
    if boardCast and boardCast.image then
        local img = Assets.getImage(boardCast.image, "nearest")
        if img then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, 320, 240, 0, 1, 1, boardCast.reg_x or 320, boardCast.reg_y or 241)
        end
    else
        love.graphics.setColor(0.35, 0.12, 0.10, 0.96)
        love.graphics.rectangle("fill", 40, 40, 560, 400, 12, 12)
    end

    if App.superSession and App.superSession.finished then
        love.graphics.setColor(0.55, 1.0, 0.45, 1)
        love.graphics.printf(
            string.format("Eindscore: %d punten! (%d/19 muizen)", App.superSession.score or 0, App.superSession.caughtCount or 0),
            120,
            116,
            400,
            "center"
        )
    end

    for i = 1, 5 do
        local rowY = 167 + (i - 1) * 46
        local entry = self.highScores[i]
        local isCurrent = (self.lastRank == i)
        if isCurrent then
            love.graphics.setColor(0.35, 1.0, 0.45, 1)
        else
            love.graphics.setColor(0.98, 0.86, 0.55, 1)
        end
        love.graphics.printf(tostring(i) .. ".", 124, rowY, 30, "right")
        love.graphics.printf(entry and entry.name or "---", 168, rowY, 240, "left")
        love.graphics.printf(entry and tostring(entry.score) or "0", 420, rowY, 100, "right")
    end

    local closeLabel = (App.superSession and App.superSession.finished) and "Hoofdmenu" or "Terug"
    for _, btn in ipairs({
        { id = "scores_replay", label = "Opnieuw spelen", x = 170 },
        { id = "scores_close",  label = closeLabel,       x = 330 },
    }) do
        local hot = (self.hotzones.hoveredId == btn.id)
        love.graphics.setColor(hot and 0.28 or 0.16, hot and 0.48 or 0.20, hot and 0.30 or 0.22, 0.95)
        love.graphics.rectangle("fill", btn.x, 418, 140, 34, 6, 6)
        love.graphics.setColor(0.90, 0.78, 0.42, 1)
        love.graphics.rectangle("line", btn.x, 418, 140, 34, 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(btn.label, btn.x, 427, 140, "center")
    end
end

function SuperHub:draw(vx, vy)
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    if self.showingScores then
        self:drawScoreboard()
        if App.debugMode then
            self.hotzones:drawDebug(vx, vy)
        end
        love.graphics.pop()
        return
    end

    DirectorStage.drawFrame("super_ggmdmenu", self.frameNum, {
        sharedKey = "super_shared",
        hiddenChannels = { [44] = true, [45] = true, [46] = true, [48] = true },
    })

    local caught = (App.superSession and App.superSession.caughtCount) or 0
    local score = (App.superSession and App.superSession.score) or 0

    -- Draw hanging green mice counters on the bottom bar (cast 824/823 or crisp dots)
    for i = 1, TOTAL_MICE do
        local mx = 104 + (i - 1) * 18
        if i <= caught then
            love.graphics.setColor(0.25, 0.95, 0.35, 1)
        else
            love.graphics.setColor(0.28, 0.30, 0.34, 0.85)
        end
        love.graphics.circle("fill", mx, 461, 5)
    end

    love.graphics.setColor(0.95, 0.92, 0.65, 1)
    love.graphics.printf(string.format("Score: %d", score), 446, 454, 86, "right")

    local hotScores = (self.hotzones.hoveredId == "super_scores_toggle")
    love.graphics.setColor(hotScores and 0.25 or 0.14, hotScores and 0.45 or 0.18, hotScores and 0.28 or 0.22, 0.95)
    love.graphics.rectangle("fill", 538, 448, 90, 26, 5, 5)
    love.graphics.setColor(0.85, 0.78, 0.38, 1)
    love.graphics.rectangle("line", 538, 448, 90, 26, 5, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Top 5", 538, 454, 90, "center")

    if self.detectedRoom then
        love.graphics.setColor(0.08, 0.10, 0.14, 0.88)
        love.graphics.rectangle("fill", 190, 12, 260, 26, 6, 6)
        love.graphics.setColor(0.45, 1.0, 0.50, 1)
        local prefix = App.isTouchMode and "Tik nogmaals: " or "Gevonden: "
        love.graphics.printf(prefix .. self.detectedRoom.title, 194, 18, 252, "center")
    elseif self.banner then
        love.graphics.setColor(0.08, 0.26, 0.14, 0.92)
        love.graphics.rectangle("fill", 120, 12, 400, 26, 6, 6)
        love.graphics.setColor(0.95, 0.92, 0.65, 1)
        love.graphics.printf(self.banner, 124, 18, 392, "center")
    end

    -- Mouse-Detector TV Scanner
    local scanX, scanY = nil, nil
    if App.isTouchMode then
        if self.touchSelectedRoomId then
            local r = Rooms.BY_ID[self.touchSelectedRoomId]
            if r then
                scanX = r.x + r.w * 0.5
                scanY = r.y + r.h * 0.5
            end
        end
    elseif self.scannerVisible and vx and vy then
        scanX, scanY = vx, vy
    end
    if scanX and scanY and self.scoreData and self.scoreData.casts then
        local castId = (self.detectedRoom and self.blinkOn) and 2 or 1
        local cast = self.scoreData.casts[castId]
        if cast and cast.image then
            local img = Assets.getImage(cast.image, "nearest")
            if img then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(img, scanX - (cast.reg_x or 41), scanY - (cast.reg_y or 53))
            end
        end
    end

    if App.debugMode then
        self.hotzones:drawDebug(vx, vy)
        love.graphics.setColor(0.2, 1, 0.4, 1)
        love.graphics.print("superActiveRoom=" .. tostring(App.superSession and App.superSession.activeRoomId), 10, 24)
    end
    love.graphics.pop()
end

return SuperHub
