-- Cumulative Orchestra Rehearsal (ORCH.DXR): plays and animates all found mice together.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local DirectorStage = require("src.core.director_stage")
local SceneManager = require("src.core.scene_manager")
local Rooms = require("src.data.rooms")

local Orch = {}

local function pickBuildTrack(foundCount)
    local buildKey = "build" .. tostring(App.session.buildIndex or 1)
    local order = Assets.getMusicBuild(buildKey)
    if order and #order > 0 then
        local idx = math.max(1, math.min(#order, foundCount or 1))
        return buildKey, Rooms.normalizeInstrumentId(order[idx])
    end
    return buildKey, (App.session and App.session.lastInstrument) or "drums"
end

function Orch:enter(params)
    Cursor.reset()
    AudioQueue.stopAll()

    params = params or {}
    self.roomTitle = params.roomTitle
    self.previewOnly = params.previewOnly == true
    self.score = Assets.getDxr("orch")
    self.fps = (self.score and self.score.fps) or 10

    local _, spans = DirectorStage.getLabelSpans("orch")
    local mlSpan = spans["ml"]
    self.startFrame = (mlSpan and mlSpan.startFrame) or 5
    self.endFrame = (mlSpan and mlSpan.endFrame) or 28
    self.frameFloat = self.startFrame

    self.hiddenChannels = {}
    local found = (App.session and App.session.foundInstruments) or {}
    self.foundCount = 0
    for _, inst in ipairs(Rooms.INSTRUMENTS) do
        if found[inst.id] then
            self.foundCount = self.foundCount + 1
        else
            self.hiddenChannels[inst.orchChannel] = true
        end
    end

    local buildKey, trackKey = pickBuildTrack(self.foundCount)
    local groupName = "music_" .. buildKey
    self.elapsed = 0
    self.musicStarted = false
    if App.session.musicEnabled ~= false and Assets.getAudioPath(groupName, trackKey) then
        AudioQueue.playMusic({ group = groupName, key = trackKey }, { loop = false, volume = 0.85 })
        self.musicStarted = true
    end
end

function Orch:exit()
    AudioQueue.stopAll()
    Cursor.reset()
end

function Orch:proceed()
    if not self.previewOnly and (App.session.caughtCount or 0) >= 19 then
        SceneManager.switch(App.states.finale)
    else
        SceneManager.switch(App.states.hotel_hub, { justCaught = self.roomTitle })
    end
end

function Orch:update(dt)
    self.elapsed = self.elapsed + dt
    self.frameFloat = self.frameFloat + dt * self.fps
    if self.frameFloat > self.endFrame + 0.99 then
        self.frameFloat = self.startFrame
    end

    local playing = AudioQueue.musicSource and AudioQueue.musicSource:isPlaying()
    if (self.musicStarted and not playing and self.elapsed >= 1.5) or (not self.musicStarted and self.elapsed >= 5.0) then
        self:proceed()
    end
end

function Orch:mousepressed()
    self:proceed()
end

function Orch:keypressed(key)
    if key == "escape" or key == "space" or key == "return" then
        self:proceed()
        return true
    end
    return false
end

function Orch:draw()
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    local frameNum = math.max(self.startFrame, math.min(self.endFrame, math.floor(self.frameFloat)))
    DirectorStage.drawFrame("orch", frameNum, {
        sharedKey = nil,
        hiddenChannels = self.hiddenChannels,
    })

    love.graphics.setColor(0.08, 0.10, 0.14, 0.88)
    love.graphics.rectangle("fill", 40, 446, 560, 26, 6, 6)
    love.graphics.setColor(0.95, 0.92, 0.65, 1)
    love.graphics.printf(
        string.format("Het Grote Groene Muizenorkest (%d/19)  •  Klik / Esc = Verder", self.foundCount),
        48,
        452,
        544,
        "center"
    )
    love.graphics.pop()
end

return Orch
