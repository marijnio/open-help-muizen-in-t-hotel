-- Background worker thread for reading and decoding video frame PNGs into ImageData.

local reqChannel, resChannel = ...

require("love.filesystem")
require("love.image")

while true do
    local req = reqChannel:demand()
    if req == "quit" or type(req) ~= "table" then
        break
    end

    local fd = nil
    if req.baseMode == "fs" then
        local ok, data = pcall(love.filesystem.newFileData, req.path)
        if ok then
            fd = data
        end
    elseif req.baseMode == "io" then
        local f = io.open(req.path, "rb")
        if f then
            local bytes = f:read("*a")
            f:close()
            if bytes then
                local ok, data = pcall(love.filesystem.newFileData, bytes, req.name or "frame.png")
                if ok then
                    fd = data
                end
            end
        end
    end

    local imgData = nil
    if fd then
        local okImg, decoded = pcall(love.image.newImageData, fd)
        if okImg then
            imgData = decoded
        end
        if fd.release then
            fd:release()
        end
    end

    resChannel:push({
        jobId = req.jobId,
        pid = req.pid,
        imageData = imgData,
        failed = (imgData == nil),
    })
end
