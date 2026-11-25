-- Flexible multi-tier asset loader and cache.
-- Searches for manifest.lua in priority order:
--   1. MUIZEN_ASSETS_DIR env var
--   2. local_config.lua (assets_dir)
--   3. Bundled/project-local "assets/" via love.filesystem
--   4. User save directory "<save-dir>/assets/" via love.filesystem

local Assets = {
    manifest = nil,
    baseMode = nil, -- "fs" (love.filesystem) or "io" (OS path)
    basePath = nil,
    checkedPaths = {},
    images = {},
    imageData = {},
    sounds = {},
    dxrScores = {},
    missingLogged = {},
}

local function trimTrailingSlash(p)
    return (p:gsub("[/\\]+$", ""))
end

local function loadLuaFromFs(path)
    if not love.filesystem.getInfo(path) then
        return nil
    end
    local chunk, err = love.filesystem.load(path)
    if not chunk then
        print("[Assets] Failed loading Lua from fs (" .. path .. "): " .. tostring(err))
        return nil
    end
    local ok, res = pcall(chunk)
    if not ok then
        print("[Assets] Failed executing Lua from fs (" .. path .. "): " .. tostring(res))
        return nil
    end
    return res
end

local function loadLuaFromIo(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local src = f:read("*a")
    f:close()
    local fn, err = (loadstring or load)(src, "@" .. path)
    if not fn then
        print("[Assets] Failed loading Lua from io (" .. path .. "): " .. tostring(err))
        return nil
    end
    local ok, res = pcall(fn)
    if not ok then
        print("[Assets] Failed executing Lua from io (" .. path .. "): " .. tostring(res))
        return nil
    end
    return res
end

local function readFileData(relPath)
    if Assets.baseMode == "fs" then
        local full = Assets.basePath .. "/" .. relPath
        local ok, fd = pcall(love.filesystem.newFileData, full)
        if not ok then
            return nil
        end
        return fd
    elseif Assets.baseMode == "io" then
        local full = Assets.basePath .. "/" .. relPath
        local f = io.open(full, "rb")
        if not f then
            return nil
        end
        local bytes = f:read("*a")
        f:close()
        return love.filesystem.newFileData(bytes, relPath)
    end
    return nil
end

function Assets.resolvePath(relPath)
    if not relPath or not Assets.baseMode or not Assets.basePath then
        return nil, nil
    end
    return Assets.basePath .. "/" .. relPath, Assets.baseMode
end

function Assets.clearCache()
    Assets.images = {}
    Assets.imageData = {}
    Assets.sounds = {}
    Assets.dxrScores = {}
    Assets.missingLogged = {}
end

function Assets.init()
    Assets.clearCache()
    Assets.manifest = nil
    Assets.baseMode = nil
    Assets.basePath = nil
    Assets.checkedPaths = {}

    -- 1. Environment variable
    local envDir = os.getenv("MUIZEN_ASSETS_DIR")
    if envDir and envDir ~= "" then
        envDir = trimTrailingSlash(envDir)
        local mpath = envDir .. "/manifest.lua"
        table.insert(Assets.checkedPaths, "ENV MUIZEN_ASSETS_DIR: " .. mpath)
        local m = loadLuaFromIo(mpath)
        if m then
            Assets.manifest = m
            Assets.baseMode = "io"
            Assets.basePath = envDir
            return true
        end
    else
        table.insert(Assets.checkedPaths, "ENV MUIZEN_ASSETS_DIR: (not set)")
    end

    -- 2. local_config.lua
    local cfg = loadLuaFromFs("local_config.lua")
    if cfg and cfg.assets_dir and cfg.assets_dir ~= "" then
        local dir = trimTrailingSlash(cfg.assets_dir)
        local mpath = dir .. "/manifest.lua"
        table.insert(Assets.checkedPaths, "local_config.lua: " .. mpath)
        local m = loadLuaFromIo(mpath)
        if m then
            Assets.manifest = m
            Assets.baseMode = "io"
            Assets.basePath = dir
            return true
        end
    else
        table.insert(Assets.checkedPaths, "local_config.lua: (none or no assets_dir)")
    end

    -- 3. Project/bundled "assets/" via love.filesystem
    table.insert(Assets.checkedPaths, "love.filesystem: assets/manifest.lua")
    local bundled = loadLuaFromFs("assets/manifest.lua")
    if bundled then
        Assets.manifest = bundled
        Assets.baseMode = "fs"
        Assets.basePath = "assets"
        return true
    end

    -- 4. Save directory "<save-dir>/assets/"
    local saveDir = love.filesystem.getSaveDirectory()
    local saveManifest = saveDir .. "/assets/manifest.lua"
    table.insert(Assets.checkedPaths, "Save dir: " .. saveManifest)
    local saved = loadLuaFromIo(saveManifest)
    if saved then
        Assets.manifest = saved
        Assets.baseMode = "io"
        Assets.basePath = saveDir .. "/assets"
        return true
    end

    return false
end

function Assets.isReady()
    return Assets.manifest ~= nil
end

local function logMissingOnce(key)
    if not Assets.missingLogged[key] then
        Assets.missingLogged[key] = true
        print("[Assets] Missing asset: " .. tostring(key))
    end
end

function Assets.loadLuaTable(relPath)
    if not relPath then return nil end
    if Assets.baseMode == "fs" then
        return loadLuaFromFs(Assets.basePath .. "/" .. relPath)
    elseif Assets.baseMode == "io" then
        return loadLuaFromIo(Assets.basePath .. "/" .. relPath)
    end
    return nil
end

function Assets.getImageData(relPath)
    if not relPath then return nil end
    if Assets.imageData[relPath] then
        return Assets.imageData[relPath]
    end
    local fd = readFileData(relPath)
    if not fd then
        logMissingOnce("imageData:" .. relPath)
        return nil
    end
    local ok, idata = pcall(love.image.newImageData, fd)
    if not ok then
        logMissingOnce("imageDataDecode:" .. relPath)
        return nil
    end
    Assets.imageData[relPath] = idata
    return idata
end

function Assets.getImage(relPath, filter)
    if not relPath then return nil end
    if Assets.images[relPath] then
        return Assets.images[relPath]
    end
    local fd = readFileData(relPath)
    if not fd then
        logMissingOnce("image:" .. relPath)
        return nil
    end
    local ok, img = pcall(love.graphics.newImage, fd)
    if not ok then
        logMissingOnce("imageDecode:" .. relPath)
        return nil
    end
    local f = filter or "nearest"
    img:setFilter(f, f)
    Assets.images[relPath] = img
    return img
end

-- Uncached image loader for transient video frames
function Assets.loadUncachedImage(relPath, filter)
    if not relPath then return nil end
    local fd = readFileData(relPath)
    if not fd then
        return nil
    end
    local ok, img = pcall(love.graphics.newImage, fd)
    if not ok then
        return nil
    end
    local f = filter or "nearest"
    img:setFilter(f, f)
    return img
end

function Assets.getManifestImage(key)
    if not Assets.manifest or not Assets.manifest.images then return nil end
    local rel = Assets.manifest.images[key]
    if not rel then
        logMissingOnce("manifest.images." .. tostring(key))
        return nil
    end
    return Assets.getImage(rel)
end

function Assets.getAudioSource(relPath, sourceType)
    if not relPath then return nil end
    local cacheKey = (sourceType or "static") .. ":" .. relPath
    if Assets.sounds[cacheKey] then
        return Assets.sounds[cacheKey]
    end
    local fd = readFileData(relPath)
    if not fd and relPath:match("%.wav$") then
        fd = readFileData((relPath:gsub("%.wav$", ".mp3")))
    end
    if not fd then
        logMissingOnce("audio:" .. relPath)
        return nil
    end
    local ok, src = pcall(love.audio.newSource, fd, sourceType or "static")
    if not ok then
        logMissingOnce("audioDecode:" .. relPath)
        return nil
    end
    Assets.sounds[cacheKey] = src
    return src
end

function Assets.getAudioPath(group, key)
    if not Assets.manifest or not Assets.manifest.audio then return nil end
    local g = Assets.manifest.audio[group]
    if not g then return nil end
    return g[key]
end

function Assets.getManifestAudio(group, key, sourceType)
    local rel = Assets.getAudioPath(group, key)
    if not rel then
        logMissingOnce("manifest.audio." .. tostring(group) .. "." .. tostring(key))
        return nil
    end
    return Assets.getAudioSource(rel, sourceType)
end

function Assets.getDxr(key)
    if Assets.dxrScores[key] then
        return Assets.dxrScores[key]
    end
    if not Assets.manifest or not Assets.manifest.dxr then return nil end
    local rel = Assets.manifest.dxr[key]
    if not rel then
        logMissingOnce("manifest.dxr." .. tostring(key))
        return nil
    end
    local data = Assets.loadLuaTable(rel)
    if not data then
        logMissingOnce("dxrLoad:" .. rel)
        return nil
    end
    Assets.dxrScores[key] = data
    return data
end

function Assets.getVideoMeta(key)
    if not Assets.manifest or not Assets.manifest.videos then return nil end
    return Assets.manifest.videos[key]
end

function Assets.getMusicBuild(buildKey)
    if not Assets.manifest or not Assets.manifest.music_builds then return nil end
    return Assets.manifest.music_builds[buildKey]
end

return Assets
