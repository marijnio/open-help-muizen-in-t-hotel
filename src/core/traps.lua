-- Shared mousetrap state, animation, and Fat Lazy Cat hint overlay for all rooms.

local Assets = require("src.core.assets")
local AudioQueue = require("src.core.audio_queue")
local Cursor = require("src.core.cursor")
local SceneManager = require("src.core.scene_manager")
local VideoPlayer = require("src.core.video_player")

local Traps = {}

-- Exact cast sequences in SHARED.DXR for the 5 mousetrap types
Traps.SEQUENCES = {
    [1] = { 765, 766, 767, 768, 769, 770, 771, 762, 763, 764 },
    [2] = { 777, 778, 779, 780, 781, 782, 783, 784, 785, 786, 787, 788 },
    [3] = { 789, 790, 791, 792, 793, 794, 795 },
    [4] = { 809, 810, 811, 812, 813, 814 },
    [5] = { 796, 797, 798, 799, 800, 801, 802, 803, 804 },
}

-- Toolbar channel positions for the 5 selectable trap icons (matching ch 41..45)
Traps.MENU_SLOTS = {
    { trapType = 1, cast = 772, x = 526, y = 414, w = 35, h = 36 },
    { trapType = 2, cast = 773, x = 492, y = 414, w = 35, h = 36 },
    { trapType = 3, cast = 774, x = 458, y = 414, w = 35, h = 36 },
    { trapType = 4, cast = 775, x = 424, y = 414, w = 35, h = 36 },
    { trapType = 5, cast = 776, x = 390, y = 414, w = 35, h = 36 },
}

Traps.BAG_RECT = { x = 518, y = 444, w = 50, h = 35 }
Traps.EXIT_RECT = { x = 14, y = 442, w = 60, h = 38 }
Traps.CAT_RECT = { x = 574, y = 442, w = 60, h = 38 }

-- Modal hint video overlay (320x200) for Fat Lazy Cat inside rooms
local HintOverlay = {}

function HintOverlay:enter(params)
    Cursor.reset()
    self.videoKey = params.videoKey or "cathelp7"
    self.onClose = params.onClose
    self.player = VideoPlayer.new(self.videoKey, {
        onFinish = function()
            self:close()
        end,
    })
    if not self.player then
        self:close()
    end
end

function HintOverlay:close()
    if self.player then
        self.player:stop()
        self.player = nil
    end
    SceneManager.clearOverlay()
    if self.onClose then
        self.onClose()
    end
end

function HintOverlay:exit()
    if self.player then
        self.player:stop()
        self.player = nil
    end
end

function HintOverlay:update(dt)
    if self.player then
        self.player:update(dt)
    end
end

function HintOverlay:mousepressed()
    self:close()
end

function HintOverlay:keypressed(key)
    if key == "escape" or key == "space" or key == "return" then
        self:close()
    end
    return true
end

function HintOverlay:draw()
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", 0, 0, 640, 480)
    if self.player then
        self.player:draw()
    end
    love.graphics.setColor(1, 0.92, 0.6, 1)
    love.graphics.printf("De Dikke Luie Kater • Klik of Esc om te sluiten", 120, 355, 400, "center")
    love.graphics.pop()
end

function Traps.openCatHint(videoKey, onClose)
    SceneManager.setOverlay(HintOverlay, {
        videoKey = videoKey,
        onClose = onClose,
    })
end

function Traps.newState(trapPos)
    return {
        menuOpen = false,
        active = nil, -- { trapType, x, y, frame, timer, sprung }
        trapPos = trapPos or { x = 320, y = 370 },
    }
end

function Traps.place(state, trapType)
    if (App.session.trapsLeft or 0) <= 0 then
        return false
    end
    App.session.trapsLeft = App.session.trapsLeft - 1
    state.menuOpen = false
    state.active = {
        trapType = trapType,
        x = state.trapPos.x,
        y = state.trapPos.y,
        frame = 1,
        timer = 0,
        sprung = false,
    }
    AudioQueue.playSfx("dxr/shared/sounds/s_822.wav", 0.55)
    return true
end

function Traps.spring(state)
    if state.active and not state.active.sprung then
        state.active.sprung = true
        state.active.frame = 1
        state.active.timer = 0
        return true
    end
    return false
end

function Traps.update(state, dt)
    if not state.active or not state.active.sprung then
        return
    end
    local seq = Traps.SEQUENCES[state.active.trapType]
    if not seq then return end
    state.active.timer = state.active.timer + dt
    if state.active.timer >= 0.08 then
        state.active.timer = state.active.timer - 0.08
        if state.active.frame < #seq then
            state.active.frame = state.active.frame + 1
        end
    end
end

function Traps.drawActive(state)
    if not state.active then return end
    local shared = Assets.getDxr("shared")
    if not shared then return end
    local seq = Traps.SEQUENCES[state.active.trapType]
    local castId = seq and seq[state.active.frame]
    local cast = castId and shared.casts[castId]
    if cast and cast.image then
        local img = Assets.getImage(cast.image, "nearest")
        if img then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, state.active.x - (cast.reg_x or 0), state.active.y - (cast.reg_y or 0))
        end
    end
end

function Traps.drawToolbarHud(state, roomTitle, hasMouse)
    local trapsLeft = App.session.trapsLeft or 0
    local caught = App.session.caughtCount or 0

    -- Draw trap selector popup icons cleanly when open
    if state.menuOpen and trapsLeft > 0 then
        local shared = Assets.getDxr("shared")
        love.graphics.setColor(0.10, 0.13, 0.18, 0.92)
        love.graphics.rectangle("fill", 384, 408, 182, 42, 6, 6)
        love.graphics.setColor(0.85, 0.78, 0.35, 1)
        love.graphics.rectangle("line", 384, 408, 182, 42, 6, 6)
        if shared then
            love.graphics.setColor(1, 1, 1, 1)
            for _, slot in ipairs(Traps.MENU_SLOTS) do
                local cast = shared.casts[slot.cast]
                if cast and cast.image then
                    local img = Assets.getImage(cast.image, "nearest")
                    if img then
                        love.graphics.draw(img, slot.x, slot.y + 4)
                    end
                end
            end
        end
    end

    -- Subtle HUD pill inside the center of the bottom bar
    love.graphics.setColor(0.10, 0.12, 0.16, 0.88)
    love.graphics.rectangle("fill", 90, 449, 412, 24, 5, 5)
    love.graphics.setColor(0.95, 0.92, 0.68, 1)
    local mouseTag = hasMouse and "Muis aanwezig!" or "Kamer leeg"
    love.graphics.printf(
        string.format("%s  •  %s  •  Gevangen: %d/19  •  Vallen: %d", roomTitle, mouseTag, caught, trapsLeft),
        94,
        454,
        404,
        "center"
    )
end

return Traps
