-- Simple scene manager with clean enter/exit lifecycle and modal overlay support.

local SceneManager = {
    current = nil,
    overlay = nil,
}

function SceneManager.switch(scene, params)
    if SceneManager.overlay then
        local oldOverlay = SceneManager.overlay
        SceneManager.overlay = nil
        if oldOverlay.exit then
            oldOverlay:exit()
        end
    end
    if SceneManager.current and SceneManager.current.exit then
        SceneManager.current:exit()
    end
    SceneManager.current = scene
    if scene and scene.enter then
        scene:enter(params)
    end
end

function SceneManager.setOverlay(overlayScene, params)
    if SceneManager.overlay and SceneManager.overlay.exit then
        SceneManager.overlay:exit()
    end
    SceneManager.overlay = overlayScene
    if overlayScene and overlayScene.enter then
        overlayScene:enter(params)
    end
end

function SceneManager.clearOverlay()
    if SceneManager.overlay and SceneManager.overlay.exit then
        SceneManager.overlay:exit()
    end
    SceneManager.overlay = nil
    if App and not App.isTouchMode and App.lastVx and App.lastVy
        and SceneManager.current and SceneManager.current.mousemoved
    then
        SceneManager.current:mousemoved(App.lastVx, App.lastVy)
    end
end

function SceneManager.update(dt)
    if SceneManager.overlay then
        if SceneManager.overlay.update then
            SceneManager.overlay:update(dt)
        end
        return
    end
    if SceneManager.current and SceneManager.current.update then
        SceneManager.current:update(dt)
    end
end

function SceneManager.draw(vx, vy)
    if SceneManager.current and SceneManager.current.draw then
        SceneManager.current:draw(vx, vy)
    end
    if SceneManager.overlay and SceneManager.overlay.draw then
        SceneManager.overlay:draw(vx, vy)
    end
end

function SceneManager.mousemoved(vx, vy)
    if SceneManager.overlay then
        if SceneManager.overlay.mousemoved then
            SceneManager.overlay:mousemoved(vx, vy)
        end
        return
    end
    if SceneManager.current and SceneManager.current.mousemoved then
        SceneManager.current:mousemoved(vx, vy)
    end
end

function SceneManager.mousepressed(vx, vy, button)
    if SceneManager.overlay then
        if SceneManager.overlay.mousepressed then
            SceneManager.overlay:mousepressed(vx, vy, button)
        end
        return
    end
    if SceneManager.current and SceneManager.current.mousepressed then
        SceneManager.current:mousepressed(vx, vy, button)
    end
end

function SceneManager.mousereleased(vx, vy, button)
    if SceneManager.overlay then
        if SceneManager.overlay.mousereleased then
            SceneManager.overlay:mousereleased(vx, vy, button)
        end
        return
    end
    if SceneManager.current and SceneManager.current.mousereleased then
        SceneManager.current:mousereleased(vx, vy, button)
    end
end

function SceneManager.keypressed(key)
    if SceneManager.overlay then
        if SceneManager.overlay.keypressed then
            SceneManager.overlay:keypressed(key)
        end
        return true
    end
    if SceneManager.current and SceneManager.current.keypressed then
        return SceneManager.current:keypressed(key)
    end
    return false
end

return SceneManager
