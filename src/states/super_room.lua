-- Bonus Mode 2: Super Spel Room (super_<roomId>.DXR).
-- Hiding spots animate automatically; clicking before a mouse appears deducts points.
-- Real green mice award 300/200/100/50 points and escape to neighbor rooms if missed.
-- Occasional blue decoy mice deduct 100 points if clicked.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local SceneManager = require("src.core.scene_manager")
local Traps = require("src.core.traps")
local Rooms = require("src.data.rooms")

local SuperRoom = {}

local TOTAL_MICE = 19
local SCORE_BY_ESCAPE = { [0] = 300, [1] = 200, [2] = 100 }
local SCORE_MIN_CATCH = 50
local PENALTY_PREMATURE = 50
local PENALTY_BLUE_MOUSE = 100
local PENALTY_MISS = 25
local DECOY_CHANCE = 0.25
local ESCAPE_BANNER_SECONDS = 0.9

local function pointInRect(px, py, r)
    return px >= r.x and px < (r.x + r.w) and py >= r.y and py < (r.y + r.h)
end

local function parseSuperInfo(score)
    local neighbors = {}
    local spotCount = 9
    local prefix = nil

    if score and score.casts then
        for _, cast in pairs(score.casts) do
            if cast.type == "text" and cast.name and string.lower(cast.name) == "myinfo" and cast.text then
                local lines = {}
                for raw in (cast.text .. "\n"):gmatch("([^\n]*)\n") do
                    local cleaned = raw:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if cleaned ~= "" then
                        table.insert(lines, cleaned)
                    end
                end
                if lines[1] then
                    for tok in lines[1]:gmatch("[^,%s]+") do
                        local nid = string.lower(tok)
                        if Rooms.BY_ID[nid] and nid ~= "attic" then
                            table.insert(neighbors, nid)
                        end
                    end
                end
                if lines[2] then
                    spotCount = tonumber(lines[2]) or spotCount
                end
                if lines[3] then
                    prefix = string.lower(lines[3])
                end
                break
            end
        end
    end

    return neighbors, spotCount, prefix
end

local function clampRoomFps(rawFps)
    if not rawFps or rawFps < 6 or rawFps > 24 then
        return 11
    end
    return rawFps
end

local function pickNextRandomRoom(excludeId)
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

function SuperRoom:enter(params)
    Cursor.reset()
    AudioQueue.stopAll()

    local roomId = (params and params.roomId)
        or (App.superSession and App.superSession.activeRoomId)
        or "artist"
    self.room = Rooms.BY_ID[roomId] or Rooms.LIST[1]
    self.dxrKey = "super_" .. self.room.id
    self.scoreData = Assets.getDxr(self.dxrKey)
    self.orderedLabels, self.spans = DirectorStage.getLabelSpans(self.dxrKey)
    self.fps = clampRoomFps(self.scoreData and self.scoreData.fps)
    self.neighbors, self.spotCount, self.prefix = parseSuperInfo(self.scoreData)

    self.loopFrame = (self.spans["loop"] and self.spans["loop"].startFrame)
        or (self.spans["loop1"] and self.spans["loop1"].startFrame)
        or 6

    self.teaseSpans = {}
    self.runSpans = {}
    for _, item in ipairs(self.orderedLabels) do
        local kl = item.key
        local aNum = kl:match("^a(%d+)$")
        local maNum = kl:match("^ma(%d+)$")
        if aNum then
            table.insert(self.teaseSpans, { num = tonumber(aNum), span = self.spans[kl] })
        elseif maNum then
            table.insert(self.runSpans, { num = tonumber(maNum), span = self.spans[kl] })
        end
    end

    self.decoyStreak = 0
    self.isBlueMouse = false
    self.animSpan = nil
    self.animFrameFloat = self.loopFrame
    self.teasesRemaining = love.math.random(1, 3)
    self.pauseBeforeNext = 0
    self.escapeTimer = 0
    self.escapeNextRoomId = nil
    self.feedback = nil
    self.feedbackColor = { 1, 0.88, 0.35, 1 }
    self.feedbackTimer = 0

    if App.session and App.session.musicEnabled ~= false and self.room.startsnd then
        AudioQueue.playMusic({ group = "startsnd", key = self.room.startsnd }, { loop = false, volume = 0.55 })
    end

    self:startNextTease()
end

function SuperRoom:exit()
    AudioQueue.stopAll()
    Cursor.reset()
end

function SuperRoom:showFeedback(msg, isPenalty)
    self.feedback = msg
    self.feedbackTimer = 1.6
    if isPenalty then
        self.feedbackColor = { 1, 0.35, 0.30, 1 }
    else
        self.feedbackColor = { 0.45, 1.0, 0.50, 1 }
    end
end

function SuperRoom:deductScore(amount, label)
    if not App.superSession then return end
    App.superSession.score = math.max(0, (App.superSession.score or 0) - amount)
    AudioQueue.playSfx("dxr/super_shared/sounds/s_822.wav", 0.7)
    self:showFeedback(string.format("%s -%d", label, amount), true)
end

function SuperRoom:playSpotSound(spotNum)
    if not self.prefix or not spotNum then return end
    local key = self.prefix .. tostring(spotNum)
    if Assets.getAudioPath("super_sounds", key) then
        AudioQueue.playSfx({ group = "super_sounds", key = key }, 0.8)
    end
end

function SuperRoom:startNextTease()
    if self.teasesRemaining <= 0 or #self.teaseSpans == 0 then
        self:startMouseRun()
        return
    end
    self.teasesRemaining = self.teasesRemaining - 1
    local pick = self.teaseSpans[love.math.random(1, #self.teaseSpans)]
    self.mode = "tease"
    self.isBlueMouse = false
    self.animSpan = pick.span
    self.animFrameFloat = pick.span.startFrame
    self:playSpotSound(pick.num)
end

function SuperRoom:startMouseRun()
    if #self.runSpans == 0 then
        self.teasesRemaining = 2
        self:startNextTease()
        return
    end
    local pick = self.runSpans[love.math.random(1, #self.runSpans)]
    local wantBlue = (self.decoyStreak < 2) and (love.math.random() < DECOY_CHANCE)
    self.isBlueMouse = wantBlue
    if wantBlue then
        self.decoyStreak = self.decoyStreak + 1
    else
        self.decoyStreak = 0
    end

    self.mode = "mouse_run"
    self.animSpan = pick.span
    self.animFrameFloat = pick.span.startFrame
    AudioQueue.playSfx("dxr/super_shared/sounds/s_821.wav", 0.75)
end

function SuperRoom:catchGreenMouse()
    local sess = App.superSession
    local esc = sess and sess.escapeCount or 0
    local pts = SCORE_BY_ESCAPE[esc] or SCORE_MIN_CATCH
    if sess then
        sess.score = (sess.score or 0) + pts
        sess.caughtCount = (sess.caughtCount or 0) + 1
        sess.escapeCount = 0
        if sess.caughtCount < TOTAL_MICE then
            sess.activeRoomId = pickNextRandomRoom(self.room.id)
        end
    end

    AudioQueue.stopMusic()
    AudioQueue.playSfx("dxr/super_shared/sounds/s_821.wav", 0.9)
    self.lastPointsEarned = pts

    local caughtSpan = self.spans["caught"]
    if caughtSpan then
        self.mode = "caught"
        self.isBlueMouse = false
        self.animSpan = caughtSpan
        self.animFrameFloat = caughtSpan.startFrame
    else
        self:finishCapture()
    end
end

function SuperRoom:finishCapture()
    local caught = (App.superSession and App.superSession.caughtCount) or 0
    if caught >= TOTAL_MICE then
        SceneManager.switch(App.states.super_hub, {
            justCaught = self.room.title,
            pointsEarned = self.lastPointsEarned or 0,
            showScores = true,
        })
    else
        SceneManager.switch(App.states.super_hub, {
            justCaught = self.room.title,
            pointsEarned = self.lastPointsEarned or 0,
        })
    end
end

function SuperRoom:triggerEscape()
    AudioQueue.playSfx("dxr/super_shared/sounds/s_822.wav", 0.75)
    local nextId = nil
    if #self.neighbors > 0 then
        nextId = self.neighbors[love.math.random(1, #self.neighbors)]
    else
        nextId = pickNextRandomRoom(self.room.id)
    end
    if App.superSession then
        App.superSession.escapeCount = (App.superSession.escapeCount or 0) + 1
        App.superSession.activeRoomId = nextId
    end
    local nextRoom = Rooms.BY_ID[nextId]
    self.escapeNextRoomId = nextId
    self.escapeTimer = ESCAPE_BANNER_SECONDS
    self.mode = "escaping"
    self:showFeedback("Ontsnapt naar " .. (nextRoom and nextRoom.title or nextId) .. "!", false)
end

function SuperRoom:currentFrameNumber()
    if self.mode == "escaping" then
        return self.loopFrame
    elseif self.animSpan then
        return math.max(self.animSpan.startFrame, math.min(self.animSpan.endFrame, math.floor(self.animFrameFloat)))
    end
    return self.loopFrame
end

function SuperRoom:update(dt)
    if self.feedbackTimer > 0 then
        self.feedbackTimer = self.feedbackTimer - dt
        if self.feedbackTimer <= 0 then
            self.feedback = nil
        end
    end

    if self.mode == "escaping" then
        self.escapeTimer = self.escapeTimer - dt
        if self.escapeTimer <= 0 then
            SceneManager.switch(App.states.super_room, { roomId = self.escapeNextRoomId })
        end
        return
    end

    if not self.animSpan then
        return
    end

    local playFps = self.fps
    if self.mode == "mouse_run" then
        local caught = (App.superSession and App.superSession.caughtCount) or 0
        playFps = 12 + math.floor(caught * 0.22)
    end

    self.animFrameFloat = self.animFrameFloat + dt * playFps
    if self.animFrameFloat > self.animSpan.endFrame + 0.99 then
        if self.mode == "caught" then
            self:finishCapture()
        elseif self.mode == "tease" then
            self:startNextTease()
        elseif self.mode == "mouse_run" then
            if self.isBlueMouse then
                self.teasesRemaining = love.math.random(1, 2)
                self:startNextTease()
            else
                self:triggerEscape()
            end
        end
    end
end

function SuperRoom:mousemoved(vx, vy)
    if pointInRect(vx, vy, Traps.EXIT_RECT) then
        Cursor.setSystem("hand")
    elseif self.mode == "mouse_run" then
        Cursor.setSystem("hand")
    else
        Cursor.setSystem("arrow")
    end
end

function SuperRoom:mousepressed(vx, vy, button)
    if button ~= 1 then return end

    if pointInRect(vx, vy, Traps.EXIT_RECT) then
        SceneManager.switch(App.states.super_hub)
        return
    end

    if self.mode == "caught" then
        if App.debugMode then
            self:finishCapture()
        end
        return
    elseif self.mode == "escaping" then
        return
    elseif self.mode == "tease" then
        self:deductScore(PENALTY_PREMATURE, "Wacht op de muis!")
        return
    elseif self.mode == "mouse_run" then
        local bounds = DirectorStage.getMouseBounds(self.dxrKey, self:currentFrameNumber(), "super_shared")
        if bounds then
            local pad = App.isTouchMode and 26 or 14
            if vx >= (bounds.x - pad) and vx <= (bounds.x + bounds.w + pad)
               and vy >= (bounds.y - pad) and vy <= (bounds.y + bounds.h + pad) then
                if self.isBlueMouse then
                    self:deductScore(PENALTY_BLUE_MOUSE, "Blauwe muis!")
                    self.teasesRemaining = love.math.random(1, 2)
                    self:startNextTease()
                else
                    self:catchGreenMouse()
                end
                return
            end
        end
        self:deductScore(PENALTY_MISS, "Mis!")
    end
end

function SuperRoom:keypressed(key)
    if App.debugMode and key == "c" and self.mode ~= "caught" and self.mode ~= "escaping" then
        self:catchGreenMouse()
        return true
    end
    if key == "escape" then
        SceneManager.switch(App.states.super_hub)
        return true
    end
    return false
end

function SuperRoom:draw()
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    local frameNum = self:currentFrameNumber()
    DirectorStage.drawFrame(self.dxrKey, frameNum, {
        sharedKey = "super_shared",
        blueMouse = (self.mode == "mouse_run" and self.isBlueMouse),
    })

    -- Bottom HUD pill
    local caught = (App.superSession and App.superSession.caughtCount) or 0
    local score = (App.superSession and App.superSession.score) or 0
    local attempt = ((App.superSession and App.superSession.escapeCount) or 0) + 1
    love.graphics.setColor(0.10, 0.12, 0.16, 0.90)
    love.graphics.rectangle("fill", 90, 449, 466, 24, 5, 5)
    love.graphics.setColor(0.95, 0.92, 0.68, 1)
    love.graphics.printf(
        string.format("%s  •  %d/19  •  Score: %d  •  Kamer #%d", self.room.title, caught, score, attempt),
        96,
        454,
        454,
        "center"
    )

    if self.feedback then
        love.graphics.setColor(0.08, 0.10, 0.14, 0.92)
        love.graphics.rectangle("fill", 160, 14, 320, 28, 6, 6)
        love.graphics.setColor(self.feedbackColor)
        love.graphics.printf(self.feedback, 164, 21, 312, "center")
    end

    if App.debugMode then
        if self.mode == "mouse_run" then
            local b = DirectorStage.getMouseBounds(self.dxrKey, frameNum, "super_shared")
            if b then
                if self.isBlueMouse then
                    love.graphics.setColor(0.3, 0.7, 1, 0.95)
                else
                    love.graphics.setColor(0, 1, 0, 0.95)
                end
                love.graphics.rectangle("line", b.x - 14, b.y - 14, b.w + 28, b.h + 28)
            end
        end
        love.graphics.setColor(0.2, 1, 0.4, 1)
        love.graphics.print(
            string.format("super=%s mode=%s blue=%s [C = catch]", self.room.id, tostring(self.mode), tostring(self.isBlueMouse)),
            10,
            24
        )
    end

    love.graphics.pop()
end

return SuperRoom
