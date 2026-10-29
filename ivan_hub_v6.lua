--[[ ====================================================================
     Иван Хаб | Steal an Egg  (v6)
     Вставь в экзекьютор и нажми Execute.
     Меню: круглая кнопка «ИХ» на экране (перетаскивается) или RightShift.
     Все этапы пишут в консоль (F9): [DEBUG] ...

     Пути (по твоему сканированию):
       Яйца ........ Workspace.AreaEggSlotsClient   (модели с ProximityPrompt;
                     биом берётся из имени, напр. FirstAreaEgg_XXX_Forest:Slot_XXX)
       База ........ Workspace.World.Areas.EggCarryBounds.SafeZone
       Дорожка ..... Workspace.Plots.[Номер].TreadmillBottom
       Хэллоуин .... Workspace.HalloweenDimension.WorldEggs.HalloweenEgg
                     Workspace.HalloweenDimension.Zones.Zone1/Zone2/Zone3/SafeZone
==================================================================== ]]

local function IvanHubMain()

-- ============================== КОНФИГ ==================================
local Config = {
    Debug = true,                -- печатать [DEBUG] в консоль
    StartBiome = "Auto",         -- "Auto" (по скорости) | "All" | имя биома
    Priority = "Closest",        -- Closest | Income | Rarity | Weight
    MoveMode = "Walk",           -- Walk (MoveTo / Pathfinding) | Fly (AlignPosition + AlignOrientation)
    FlySpeed = 80,               -- studs/сек в режиме Fly
    SpeedMargin = 1.25,          -- запас к минимальной скорости биома (+25%)
    SpeedOverride = 0,           -- >0: ручное значение «скорости» для выбора биома
    IgnoreSpeedCheck = false,    -- не проверять скорость
    Halloween = false,           -- брать яйца Хэллоуина и нести в Zones.SafeZone
    Cooldown = 1,                -- пауза между циклами (сек)
    FarDistance = 200,           -- дальше этого: noclip + MoveTo вместо Pathfinding
    PortalJump = 500,            -- скачок дистанции больше этого = портал/телепорт → пересчёт
    AutoTreadmill = false, TreadmillDir = 1, TreadmillUsePrompt = true,
    AntiKnockback = true,        -- PlatformStand=false каждый кадр + гашение скорости
    KnockbackEveryFrame = false, -- true: гасить скорость каждый кадр (мешает ходьбе!)
    ESP = false,
    Favorites = {},
    Volume = 0.5,
    Music = {
        { name = "Phonk", id = "rbxassetid://9046862126" },
        { name = "Bass",  id = "rbxassetid://1836342909" },
    },
    -- Биомы и минимальная скорость (для авто-выбора)
    Biomes = {
        { name = "Forest", minSpeed = 0 },        { name = "Lake", minSpeed = 900 },
        { name = "Desert", minSpeed = 10e3 },     { name = "Jungle", minSpeed = 40e3 },
        { name = "Snow", minSpeed = 170e3 },      { name = "Volcano", minSpeed = 700e3 },
        { name = "Abyss Ocean", minSpeed = 2.5e6 }, { name = "Prehistoric", minSpeed = 18e6 },
        { name = "Cosmic", minSpeed = 700e6 },    { name = "Cherry Blossom", minSpeed = 2.5e9 },
        { name = "Titan Temple", minSpeed = 7e9 }, { name = "Angels & Demons", minSpeed = 20e9 },
        { name = "Enchanted Forest", minSpeed = 50e9 },
    },
}

local Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Cosmic", "Divine" }
local RarityRank = {}
for i, r in ipairs(Rarities) do RarityRank[r] = i end
local RarityRU = { Common = "Обычный", Uncommon = "Необычный", Rare = "Редкий", Epic = "Эпический", Legendary = "Легендарный",
    Mythic = "Мифический", Secret = "Секретный", Cosmic = "Космос", Divine = "Божественный" }
local RarityColor = {
    Common = Color3.fromRGB(190, 190, 190), Uncommon = Color3.fromRGB(110, 220, 110), Rare = Color3.fromRGB(90, 160, 255),
    Epic = Color3.fromRGB(190, 110, 255), Legendary = Color3.fromRGB(255, 190, 60), Mythic = Color3.fromRGB(255, 90, 120),
    Secret = Color3.fromRGB(240, 240, 240), Cosmic = Color3.fromRGB(100, 240, 255), Divine = Color3.fromRGB(255, 245, 160),
}
-- Корни русских названий редкости (регистр первой буквы неважен: берём без неё)
local RarityRUStems = {
    Divine = { "жествен" }, Cosmic = { "осмос" }, Secret = { "екретн" }, Mythic = { "ифич" }, Legendary = { "егендарн" },
    Epic = { "пич" }, Rare = { "едк" }, Uncommon = { "еобычн" }, Common = { "бычн" },
}
local MutationWords = { "golden", "diamond", "rainbow", "spectral", "shiny", "neon", "gold", "radioactive", "galaxy",
    "золот", "алмаз", "радуж", "призрач", "неон" }

-- ============================== СЕРВИСЫ / СОСТОЯНИЕ =====================
local env = (getgenv and getgenv()) or _G
for _, k in ipairs({ "IvanHub", "IvanHubV5", "IvanHubV6" }) do          -- выгружаем старые версии
    if env[k] and env[k].Unload then pcall(env[k].Unload) end
end
local IH = { Alive = true, Conns = {} }
env.IvanHubV6 = IH

local cloneref = cloneref or function(x) return x end
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local PathfindingService = cloneref(game:GetService("PathfindingService"))
local SoundService = cloneref(game:GetService("SoundService"))
local UIS = cloneref(game:GetService("UserInputService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local TweenService = cloneref(game:GetService("TweenService"))
local LP = Players.LocalPlayer

local State = { running = false, oneShot = false, gen = 0, cycleNo = 0, farming = false, blacklist = {}, forced = nil,
    spawnPos = nil, plotCache = nil, plotDumped = false, treadEntered = false, noclip = false, moving = false,
    stats = { eggs = 0, fails = 0 }, lastSig = "" }
local logLines = {}
local ui = {}

-- ============================== ОТЛАДКА =================================
local function dbg(msg, ...)
    local args = table.pack(...)
    local parts = { tostring(msg) }
    for i = 1, args.n do parts[#parts + 1] = tostring(args[i]) end
    local line = table.concat(parts, " ")
    if Config.Debug then print("[DEBUG] " .. line) end
    logLines[#logLines + 1] = line
    if #logLines > 8 then table.remove(logLines, 1) end
    if ui.log then ui.log.Text = table.concat(logLines, "\n") end
end
local function setStatus(t)
    if ui.status then ui.status.Text = "Статус: " .. tostring(t) end
    dbg("СТАТУС:", t)
end
local function tb(e)
    return tostring(e) .. " | " .. ((debug and debug.traceback) and debug.traceback("", 2) or "")
end

-- ============================== УТИЛИТЫ =================================
local function getChar() return LP.Character end
local function getHum() local c = LP.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function getHRP() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function alive() local h = getHum(); return h ~= nil and h.Health > 0 and getHRP() ~= nil end
local function hdist(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end
local function norm(s) return (tostring(s):lower():gsub("[^%w]", "")) end
local function dig(root, path)
    local n = root
    for seg in tostring(path):gmatch("[^%.]+") do
        if not n then return nil end
        n = n:FindFirstChild(seg)
    end
    return n
end
local function childNames(inst)
    local t = {}
    for _, c in ipairs(inst:GetChildren()) do t[#t + 1] = c.Name end
    return table.concat(t, ", ")
end
local function posOf(inst)
    local ok, p = pcall(function()
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then return inst:GetPivot().Position end
        local sum, n = Vector3.zero, 0
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then sum += d.Position; n += 1 end
        end
        if n > 0 then return sum / n end
    end)
    return ok and p or nil
end
local function boxOf(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
    if inst:IsA("Model") then
        local ok, cf, sz = pcall(function() return inst:GetBoundingBox() end)
        if ok then return cf, sz end
    end
    local minV, maxV, n = Vector3.one * math.huge, Vector3.one * -math.huge, 0
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then
            local p, s = d.Position, d.Size / 2
            minV = Vector3.new(math.min(minV.X, p.X - s.X), math.min(minV.Y, p.Y - s.Y), math.min(minV.Z, p.Z - s.Z))
            maxV = Vector3.new(math.max(maxV.X, p.X + s.X), math.max(maxV.Y, p.Y + s.Y), math.max(maxV.Z, p.Z + s.Z))
            n += 1
        end
    end
    if n == 0 then return nil end
    return CFrame.new((minV + maxV) / 2), maxV - minV
end
local function insideBox(inst, margin)
    local cf, size = boxOf(inst)
    local hrp = getHRP()
    if not cf or not hrp then return false end
    local rel = cf:PointToObjectSpace(hrp.Position)
    margin = margin or 0
    return math.abs(rel.X) <= size.X / 2 + margin and math.abs(rel.Z) <= size.Z / 2 + margin and math.abs(rel.Y) <= size.Y / 2 + 12
end
local function groundAt(x, z, yTop)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LP.Character }
    local r = workspace:Raycast(Vector3.new(x, yTop + 60, z), Vector3.new(0, -500, 0), params)
    return r and (r.Position.Y + 3) or (yTop + 3)
end
local SUF = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, Q = 1e15 }
local function parseNum(v, suffix)
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return nil end
    local s = v:gsub("[%$,%s]", "")
    local num, suf = s:match("^([%d%.]+)(%a*)$")
    local n = tonumber(num)
    if not n then return nil end
    suf = ((suffix and suffix ~= "") and suffix or suf or ""):upper()
    return n * (SUF[suf] or 1)
end
local function fmt(n)
    if not n then return "?" end
    for _, u in ipairs({ { 1e15, "Q" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
        if n >= u[1] then return ("%.2f%s"):format(n / u[1], u[2]) end
    end
    return tostring(math.floor(n))
end
local function connect(sig, fn)
    local c = sig:Connect(function(...)
        local ok, e = xpcall(fn, tb, ...)
        if not ok then dbg("ОШИБКА в обработчике:", e) end
    end)
    IH.Conns[#IH.Conns + 1] = c
    return c
end

-- ============================== ДАННЫЕ ЯЙЦА =============================
local function hasAny(text, list)
    for _, s in ipairs(list) do if text:find(s, 1, true) then return true end end
    return false
end

-- Разбор текста над яйцом: вес (kg), доход (K/M/B/T per s), редкость, мутация
local function parseEggData(model, prompt)
    local texts = {}
    for _, x in ipairs(model:GetDescendants()) do
        if x:IsA("TextLabel") and x.Text ~= "" and (x:FindFirstAncestorWhichIsA("BillboardGui") or x:FindFirstAncestorWhichIsA("SurfaceGui")) then
            texts[#texts + 1] = x.Text
        end
    end
    if prompt then
        if prompt.ObjectText ~= "" then texts[#texts + 1] = prompt.ObjectText end
        if prompt.ActionText ~= "" then texts[#texts + 1] = prompt.ActionText end
    end
    local raw = table.concat(texts, " | "):gsub("<[^>]+>", "")           -- убираем RichText-теги
    local low = raw:lower()
    local d = { text = raw, name = (texts[1] and texts[1]:gsub("<[^>]+>", ""):sub(1, 28)) or model.Name }
    if d.name == "" then d.name = model.Name end

    -- вес: число перед kg
    local w = raw:match("([%d%.,]+)%s*%a?%s*[kK][gG]")
    if w then d.weight = tonumber((w:gsub(",", ""))) end
    -- доход: число перед K/M/B/T + /s
    local clean = raw:gsub("%$", "")
    local inc, suf = clean:match("([%d%.,]+)%s*([KkMmBbTtQq]?)%s*/%s*[sS]")
    if inc then d.income = parseNum((inc:gsub(",", "")), suf) end
    -- цена (если есть «$123M» без /s)
    local val, vs = raw:match("%$%s*([%d%.,]+)%s*([KkMmBbTt]?)")
    if val and not inc then d.value = parseNum((val:gsub(",", "")), vs) end
    -- редкость: английские и русские названия (от редкой к частой)
    for i = #Rarities, 1, -1 do
        local r = Rarities[i]
        if low:find(r:lower(), 1, true) then d.rarity = r; break end
        local stems = RarityRUStems[r]
        if stems and hasAny(raw, stems) then d.rarity = r; break end
    end
    d.rarity = d.rarity or tostring(model:GetAttribute("Rarity") or "?")
    -- мутация
    for _, wd in ipairs(MutationWords) do
        if low:find(wd, 1, true) or raw:find(wd, 1, true) then d.mutation = wd; break end
    end
    return d
end

-- Биом из имени модели: FirstAreaEgg_XXX_Forest:Slot_XXX → Forest (длинные названия проверяются первыми)
local biomeKeys = {}
for _, b in ipairs(Config.Biomes) do biomeKeys[#biomeKeys + 1] = { name = b.name, key = norm(b.name) } end
table.sort(biomeKeys, function(a, b) return #a.key > #b.key end)
local function biomeFromName(name)
    local key = norm(name)
    for _, b in ipairs(biomeKeys) do
        if key:find(b.key, 1, true) then return b.name end
    end
    return nil
end

-- ============================== ПОИСК ЯИЦ ===============================
local function collectSlots(container, out, depth)
    for _, c in ipairs(container:GetChildren()) do
        local pr = (c:IsA("Model") or c:IsA("BasePart")) and c:FindFirstChildWhichIsA("ProximityPrompt", true)
        if pr then out[#out + 1] = { inst = c, prompt = pr }
        elseif depth < 3 and (c:IsA("Folder") or c:IsA("Model")) then collectSlots(c, out, depth + 1) end
    end
end

local function buildEgg(inst, prompt, biome)
    local pos = (prompt and prompt.Parent and posOf(prompt.Parent)) or posOf(inst)
    local data = parseEggData(inst, prompt)
    return { inst = inst, prompt = prompt, biome = biome or biomeFromName(inst.Name) or (inst.Parent and biomeFromName(inst.Parent.Name)) or "Unknown",
        pos = pos, data = data }
end

local function readSlots(silent)
    local folder = workspace:FindFirstChild("AreaEggSlotsClient")
    if not folder then
        if not silent then dbg("AreaEggSlotsClient НЕ НАЙДЕН (Workspace.AreaEggSlotsClient)") end
        return {}
    end
    local slots = {}
    collectSlots(folder, slots, 0)
    local eggs, counts = {}, {}
    for _, s in ipairs(slots) do
        local bl = State.blacklist[s.inst]
        if s.prompt.Enabled and not (bl and tick() < bl) then
            local e = buildEgg(s.inst, s.prompt)
            if e.pos then
                eggs[#eggs + 1] = e
                counts[e.biome] = (counts[e.biome] or 0) + 1
            end
        end
    end
    if not silent then
        local parts = {}
        for b, n in pairs(counts) do parts[#parts + 1] = b .. "=" .. n end
        dbg("AreaEggSlotsClient: слотов с prompt =", #slots, "| активных яиц =", #eggs, "| по биомам:", table.concat(parts, ", "))
        if #eggs == 0 and #folder:GetChildren() > 0 then dbg("  содержимое папки (первые):", childNames(folder):sub(1, 200)) end
    end
    return eggs
end

local function readHalloween(silent)
    local f = dig(workspace, "HalloweenDimension.WorldEggs")
    local eggs = {}
    if not silent then print("[DEBUG] Проверяю Хэллоуин: HalloweenDimension.WorldEggs") end
    if not f then
        if not silent then dbg("WorldEggs не найден"); print("[DEBUG] Найдено яиц: ", 0) end
        return eggs
    end
    local function add(c)
        local bl = State.blacklist[c]
        if (c:IsA("Model") or c:IsA("BasePart")) and not (bl and tick() < bl) then
            local pr = c:FindFirstChildWhichIsA("ProximityPrompt", true)
            local e = buildEgg(c, pr, "Halloween")
            e.pos = (pr and pr.Parent and posOf(pr.Parent)) or posOf(c)
            if e.pos then eggs[#eggs + 1] = e end
        end
    end
    for _, c in ipairs(f:GetChildren()) do
        if c:IsA("Folder") then for _, cc in ipairs(c:GetChildren()) do add(cc) end else add(c) end
    end
    if not silent then print("[DEBUG] Найдено яиц: ", #eggs) end
    return eggs
end

-- Текущая «скорость» игрока для выбора биома
local function getSpeed()
    if Config.SpeedOverride > 0 then return Config.SpeedOverride end
    local best = 0
    local hum = getHum()
    if hum then best = hum.WalkSpeed end
    pcall(function()
        local ls = LP:FindFirstChild("leaderstats")
        if ls then
            for _, v in ipairs(ls:GetChildren()) do
                if v:IsA("ValueBase") and v.Name:lower():find("speed") then
                    local n = parseNum(v.Value)
                    if n and n > best then best = n end
                end
            end
        end
        for _, k in ipairs({ "Speed", "WalkSpeed", "SpeedLevel" }) do
            local n = parseNum(LP:GetAttribute(k))
            if n and n > best then best = n end
        end
    end)
    return best
end

local function onlyBiome(list, name)
    local out = {}
    for _, e in ipairs(list) do if e.biome == name then out[#out + 1] = e end end
    return out
end

-- Выбор набора яиц по режиму (Auto = по скорости, All, конкретный биом, Хэллоуин)
local function gatherEggs(silent)
    if Config.Halloween then return readHalloween(silent), "Halloween" end
    local all = readSlots(silent)
    if Config.StartBiome == "All" then return all, "All" end
    if Config.StartBiome ~= "Auto" then
        if not silent then print("[DEBUG] Проверяю биом: ", Config.StartBiome) end
        local l = onlyBiome(all, Config.StartBiome)
        local b
        for _, bb in ipairs(Config.Biomes) do if bb.name == Config.StartBiome then b = bb end end
        local speed = getSpeed()
        if not silent and b and not Config.IgnoreSpeedCheck and speed < b.minSpeed then
            dbg(("⚠ Скорость %s ниже минимума биома %s (%s)"):format(fmt(speed), b.name, fmt(b.minSpeed)))
        end
        if not silent then print("[DEBUG] Найдено яиц: ", #l) end
        return l, Config.StartBiome
    end
    -- Auto: самый дальний биом, подходящий по скорости (с запасом), где есть яйца
    local speed = getSpeed()
    local top = 1
    for i, b in ipairs(Config.Biomes) do
        if Config.IgnoreSpeedCheck or speed >= b.minSpeed * Config.SpeedMargin then top = i end
    end
    if not silent then dbg(("Auto: скорость %s → доступны биомы до «%s»"):format(fmt(speed), Config.Biomes[top].name)) end
    for i = top, 1, -1 do
        local name = Config.Biomes[i].name
        if not silent then print("[DEBUG] Проверяю биом: ", name) end
        local l = onlyBiome(all, name)
        if not silent then print("[DEBUG] Найдено яиц: ", #l) end
        if #l > 0 then return l, name end
    end
    return {}, "Auto"
end

local function pickEgg(list)
    local hrp = getHRP()
    local best, bs
    for _, e in ipairs(list) do
        local d = e.data
        local s
        if Config.Priority == "Income" then s = d.income or d.value or 0
        elseif Config.Priority == "Rarity" then s = (RarityRank[d.rarity] or 0) * 1e6 + (d.income or 0) / 1e9
        elseif Config.Priority == "Weight" then s = d.weight or 0
        else s = hrp and -(e.pos - hrp.Position).Magnitude or 0 end
        if Config.Favorites[d.name] then s += 1e15 end
        if not bs or s > bs then best, bs = e, s end
    end
    return best
end

-- ============================== ДВИЖЕНИЕ ================================
-- Идём к точке: MoveTo + MoveToFinished. Застрял (скорость <2 за 1.5 c) → прыжок, затем обход.
-- Возвращает: reached | stuck | teleported | dead | abort | timeout
local function stepTo(target, timeout, cond, early, reach)
    reach = reach or 3.5
    local hum, hrp = getHum(), getHRP()
    if not hum or not hrp then return "dead" end
    hum:MoveTo(target)
    local finished, reachedFlag = false, false
    local conn = hum.MoveToFinished:Connect(function(r) finished = true; reachedFlag = r end)
    local t0, samples, stage, prev = os.clock(), {}, 0, hrp.Position
    local result = "timeout"
    while os.clock() - t0 < timeout and cond() do
        task.wait(0.1)
        hrp = getHRP()
        if not hrp or not alive() then result = "dead"; break end
        if (hrp.Position - prev).Magnitude > Config.PortalJump then
            dbg("Позиция скакнула на", math.floor((hrp.Position - prev).Magnitude), "studs — портал/телепорт")
            result = "teleported"; break
        end
        prev = hrp.Position
        if hdist(hrp.Position, target) <= reach then result = "reached"; break end
        if early and early() then result = "reached"; break end
        if finished then
            result = reachedFlag and "reached" or "stuck"
            if not reachedFlag then dbg("MoveToFinished(false) — цель не достигнута") end
            break
        end
        samples[#samples + 1] = { os.clock(), hrp.Position }
        while #samples > 1 and os.clock() - samples[1][1] > 1.7 do table.remove(samples, 1) end
        local first = samples[1]
        local dt = os.clock() - first[1]
        if dt >= 1.5 then
            local spd = hdist(hrp.Position, first[2]) / dt
            if spd < 2 then
                stage += 1
                samples = {}
                if stage == 1 then
                    dbg(("Застрял (скорость %.1f < 2 за 1.5 c) → прыжок"):format(spd))
                    hum.Jump = true
                else
                    dbg("Всё ещё стоит → обход вбок")
                    local side = hrp.CFrame.RightVector * ((stage % 2 == 0) and 6 or -6)
                    hum:MoveTo(hrp.Position + side)
                    task.wait(0.7)
                    hum.Jump = true
                    hum:MoveTo(target)
                    if stage >= 4 then result = "stuck"; break end
                end
            else
                stage = 0
            end
        end
    end
    conn:Disconnect()
    if not cond() then return "abort" end
    return result
end

local function followPath(target, cond, early, reach)
    local hrp = getHRP()
    local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, AgentCanClimb = true, WaypointSpacing = 6 })
    local ok, err = pcall(function() path:ComputeAsync(hrp.Position, target) end)
    if not ok or path.Status ~= Enum.PathStatus.Success then
        dbg("Pathfinding: путь не построен, статус =", ok and tostring(path.Status) or tostring(err))
        return "nopath"
    end
    local wps = path:GetWaypoints()
    dbg("Pathfinding: точек в пути =", #wps)
    for i = 2, #wps do
        if not cond() then return "abort" end
        if early and early() then return "reached" end
        if wps[i].Action == Enum.PathWaypointAction.Jump then local h = getHum(); if h then h.Jump = true end end
        local r = stepTo(wps[i].Position, 6, cond, early, i == #wps and reach or 3.5)
        if r == "stuck" then dbg("Застрял на точке", i, "из", #wps, "→ пересчёт пути"); return "stuck" end
        if r == "teleported" or r == "dead" or r == "abort" then return r end
    end
    return "reached"
end

-- Ходьба: ≤200 studs → Pathfinding + MoveTo; >200 → noclip + MoveTo; скачок дистанции 500+ → пересчёт
local function walkTo(target, stop, cond, early)
    stop = stop or 4
    local reach = math.min(3.5, math.max(1.0, stop - 0.5))      -- радиус «дошёл» всегда меньше stop
    local t0, lastDist = os.clock(), nil
    while cond() and os.clock() - t0 < 300 do
        local hrp = getHRP()
        if not hrp or not alive() then dbg("Персонаж мёртв/недоступен"); State.noclip = false; return false end
        local dist = hdist(hrp.Position, target)
        if dist <= stop or (early and early()) then
            dbg(("Дошёл (осталось %.0f studs)"):format(dist)); State.noclip = false; return true
        end
        if lastDist and dist - lastDist > Config.PortalJump then
            dbg(("Дистанция выросла на %.0f studs → портал, пересчитываю маршрут"):format(dist - lastDist))
        end
        lastDist = dist
        local r
        if dist > Config.FarDistance then
            dbg(("До цели %.0f studs (>%d) → NOCLIP + MoveTo"):format(dist, Config.FarDistance))
            State.noclip = true
            r = stepTo(target, 10, cond, early, reach)
        else
            State.noclip = false
            dbg(("До цели %.0f studs → Pathfinding + MoveTo"):format(dist))
            r = followPath(target, cond, early, reach)
            if r == "nopath" then r = stepTo(target, 8, cond, early, reach) end
        end
        if r == "teleported" then dbg("Маршрут будет пересчитан с нуля"); lastDist = nil
        elseif r == "abort" or r == "dead" then State.noclip = false; return false end
    end
    State.noclip = false
    return false
end

-- Полёт: AlignPosition + AlignOrientation (MaxForce = 1e9, Responsiveness = 100)
local function flyTo(target, stop, cond, early)
    stop = stop or 3
    local hrp = getHRP()
    if not hrp then return false end
    local a0 = Instance.new("Attachment"); a0.Parent = hrp
    local ap = Instance.new("AlignPosition")
    ap.Attachment0 = a0; ap.Mode = Enum.PositionAlignmentMode.OneAttachment; ap.MaxForce = 1e9
    ap.Responsiveness = 100; ap.MaxVelocity = Config.FlySpeed; ap.RigidityEnabled = false; ap.Position = target; ap.Parent = hrp
    local ao = Instance.new("AlignOrientation")
    ao.Attachment0 = a0; ao.Mode = Enum.OrientationAlignmentMode.OneAttachment; ao.MaxTorque = 1e9
    ao.Responsiveness = 100; ao.CFrame = hrp.CFrame; ao.Parent = hrp
    State.noclip, State.moving = true, true
    dbg(("Полёт к цели: %.0f studs, скорость %d"):format((hrp.Position - target).Magnitude, Config.FlySpeed))
    local t0, prev, ok = os.clock(), hrp.Position, false
    local limit = (hrp.Position - target).Magnitude / math.max(Config.FlySpeed, 1) * 2 + 6
    while cond() and alive() and os.clock() - t0 < limit do
        task.wait(0.05)
        local h = getHRP()
        if not h then break end
        if (h.Position - prev).Magnitude > Config.PortalJump then
            dbg("Позиция скакнула (портал?) → пересчитываю полёт")
            ap.Position = target
        end
        prev = h.Position
        local dir = Vector3.new(target.X - h.Position.X, 0, target.Z - h.Position.Z)
        if dir.Magnitude > 1 then ao.CFrame = CFrame.lookAt(Vector3.zero, dir) end
        if (h.Position - target).Magnitude <= stop or (early and early()) then ok = true; break end
    end
    pcall(function() ap:Destroy(); ao:Destroy(); a0:Destroy() end)
    local h = getHRP()
    if h then pcall(function() h.AssemblyLinearVelocity = Vector3.zero end) end
    State.noclip, State.moving = false, false
    dbg("Полёт завершён:", ok and "долетел" or "не долетел")
    return ok
end

local function moveTo(target, stop, cond, early)
    if Config.MoveMode == "Fly" then return flyTo(target, stop, cond, early) end
    return walkTo(target, stop, cond, early)
end

-- ============================== КРАЖА ===================================
local function isCarrying()
    local c = getChar()
    if not c then return false end
    for _, k in ipairs({ "Carrying", "CarryingEgg", "HasEgg", "IsCarrying" }) do
        if LP:GetAttribute(k) or c:GetAttribute(k) then return true end
    end
    for _, d in ipairs(c:GetDescendants()) do
        if d.Name:lower():find("egg") then return true end
    end
    return false
end

local function steal(egg, cond)
    local prompt = egg.prompt
    if not prompt or not prompt.Parent then
        prompt = egg.inst:FindFirstChildWhichIsA("ProximityPrompt", true)
    end
    local click = egg.inst:FindFirstChildWhichIsA("ClickDetector", true)
    local part = egg.inst:IsA("BasePart") and egg.inst or egg.inst:FindFirstChildWhichIsA("BasePart", true)
    dbg("КРАЖА: prompt =", prompt and prompt:GetFullName() or "нет", "| click =", click and "да" or "нет", "| часть для touch =", part and part.Name or "нет")

    if prompt then
        local pp = prompt.Parent and posOf(prompt.Parent)
        local hrp = getHRP()
        if pp and hrp then
            local d = (hrp.Position - pp).Magnitude
            local maxd = prompt.MaxActivationDistance or 10
            dbg(("Расстояние до prompt %.1f, активация до %.1f"):format(d, maxd))
            if d > maxd - 1.5 then
                dbg("Слишком далеко от prompt — подхожу ближе")
                walkTo(pp, math.max(2, maxd - 3), cond)
            end
        end
        pcall(function() prompt.HoldDuration = 0; prompt.RequiresLineOfSight = false end)
        if fireproximityprompt then
            dbg("Вызываю fireproximityprompt(prompt)")
            local ok, err = pcall(fireproximityprompt, prompt)
            dbg("fireproximityprompt результат:", ok, err)
        else
            dbg("fireproximityprompt недоступен → InputHoldBegin/End")
            pcall(function() prompt:InputHoldBegin(); task.wait(0.2); prompt:InputHoldEnd() end)
        end
    elseif click and fireclickdetector then
        dbg("Нет prompt → fireclickdetector")
        local ok, err = pcall(fireclickdetector, click)
        dbg("fireclickdetector результат:", ok, err)
    elseif part and firetouchinterest and getHRP() then
        dbg("Нет prompt/click → firetouchinterest")
        pcall(function() firetouchinterest(getHRP(), part, 0); task.wait(0.1); firetouchinterest(getHRP(), part, 1) end)
    else
        dbg("НЕТ СПОСОБА ЗАБРАТЬ: нет prompt/click и нет firetouchinterest")
        return false
    end
    task.wait(0.5)
    local carrying = isCarrying()
    local gone = not egg.inst.Parent or (prompt and (not prompt.Parent or not prompt.Enabled))
    dbg("После кражи: несу яйцо =", carrying, "| слот опустел/prompt выключен =", gone and true or false)
    return carrying or (gone and true or false)
end

local function deliver(zone, zoneName, cond)
    if not zone then dbg("База не найдена:", zoneName); return false end
    local cf, size = boxOf(zone)
    if not cf then dbg("Не удалось получить размеры базы"); return false end
    local top = cf.Position.Y + size.Y / 2
    local target = Vector3.new(cf.Position.X, groundAt(cf.Position.X, cf.Position.Z, top), cf.Position.Z)
    dbg("Иду на базу:", zoneName, "| центр:", math.floor(target.X) .. ", " .. math.floor(target.Z))
    local ok = moveTo(target, 6, cond, function() return insideBox(zone, -2) end)
    dbg("Доставка:", ok and "в зоне" or "не дошёл", "| несу яйцо =", isCarrying())
    task.wait(0.6)
    return ok
end

local function cycle(my)
    State.cycleNo += 1
    print("[DEBUG] ===== Цикл " .. State.cycleNo .. " =====")
    local function cond() return IH.Alive and State.gen == my and (State.running or State.oneShot) end
    if not alive() then setStatus("жду персонажа"); task.wait(1); return end

    local egg = State.forced
    State.forced = nil
    if egg and egg.inst.Parent and egg.prompt and egg.prompt.Parent and egg.prompt.Enabled then
        egg.data = parseEggData(egg.inst, egg.prompt)
        egg.pos = posOf(egg.prompt.Parent) or egg.pos
        dbg("Цель выбрана вручную:", egg.data.name)
    else
        egg = nil
        local list, label = gatherEggs(false)
        if #list == 0 then setStatus("яиц нет (" .. tostring(label) .. ")"); task.wait(2); return end
        egg = pickEgg(list)
    end
    local d = egg.data
    dbg("Выбрано:", egg.inst.Name, "| биом:", egg.biome, "| имя:", d.name, "| вес:", fmt(d.weight), "| доход:", fmt(d.income), "| редкость:", d.rarity)

    State.farming = true
    setStatus("иду к яйцу")
    print("[DEBUG] Иду к яйцу: ", egg.inst.Name)
    local arrived = moveTo(egg.pos, 4, cond)
    if not cond() then State.farming = false; return end
    if not arrived then
        dbg("НЕ ДОШЁЛ до яйца → пропускаю его на 30 сек")
        State.blacklist[egg.inst] = tick() + 30
        State.stats.fails += 1; State.farming = false
        return
    end

    setStatus("краду яйцо")
    if not steal(egg, cond) then
        dbg("КРАЖА НЕ УДАЛАСЬ → пропускаю яйцо на 30 сек")
        State.blacklist[egg.inst] = tick() + 30
        State.stats.fails += 1; State.farming = false
        return
    end

    setStatus("несу на базу")
    local zone, zoneName
    if Config.Halloween then
        zone, zoneName = dig(workspace, "HalloweenDimension.Zones.SafeZone"), "HalloweenDimension.Zones.SafeZone"
    else
        zone, zoneName = dig(workspace, "World.Areas.EggCarryBounds.SafeZone"), "World.Areas.EggCarryBounds.SafeZone"
    end
    if deliver(zone, zoneName, cond) then
        State.stats.eggs += 1
        setStatus("сдано! всего: " .. State.stats.eggs)
    else
        State.stats.fails += 1
        setStatus("не удалось донести")
    end
    State.farming = false
end

local function startFarm(once)
    State.gen += 1
    local my = State.gen
    if once then State.oneShot = true else State.running = true end
    dbg("СТАРТ", once and "(одно яйцо)" or "автокражи", "| биом:", Config.StartBiome, "| приоритет:", Config.Priority, "| режим:", Config.MoveMode)
    task.spawn(function()
        while IH.Alive and State.gen == my and (State.running or State.oneShot) do
            local ok, err = xpcall(cycle, tb, my)
            State.farming = false
            if not ok then dbg("ОШИБКА В ЦИКЛЕ:", err); task.wait(1) end
            if State.oneShot and not State.running then State.oneShot = false; break end
            task.wait(Config.Cooldown)
        end
        State.farming = false
        State.noclip = false
    end)
end
local function stopFarm()
    State.running = false; State.oneShot = false; State.gen += 1; State.farming = false; State.noclip = false
    dbg("СТОП автокражи")
    local hum, hrp = getHum(), getHRP()
    if hum and hrp then hum:MoveTo(hrp.Position) end
end

-- ============================== ДОРОЖКА =================================
local function findMyPlot()
    if State.plotCache and State.plotCache.Parent then return State.plotCache end
    local pf = workspace:FindFirstChild("Plots")
    if not pf then dbg("ДОРОЖКА: Workspace.Plots не найден"); return nil end
    local dump = not State.plotDumped
    State.plotDumped = true
    local function mine(plot)
        if plot.Name == LP.Name or plot.Name == LP.DisplayName then return true, "имя плота" end
        for k, v in pairs(plot:GetAttributes()) do
            local s = tostring(v)
            if k:lower():find("owner") and (s == LP.Name or s == tostring(LP.UserId) or s == LP.DisplayName) then return true, "атрибут " .. k end
        end
        for _, ch in ipairs(plot:GetChildren()) do
            if ch:IsA("ValueBase") and ch.Name:lower():find("owner") and
                (ch.Value == LP or tostring(ch.Value) == LP.Name or tostring(ch.Value) == tostring(LP.UserId)) then return true, "значение " .. ch.Name end
        end
        local n = 0
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("TextLabel") and (d.Text:find(LP.Name, 1, true) or d.Text:find(LP.DisplayName, 1, true)) then return true, "табличка с именем" end
            n += 1
            if n > 600 then break end
        end
        return false
    end
    local found
    for _, plot in ipairs(pf:GetChildren()) do
        local ok, why = mine(plot)
        if dump then dbg("  плот", plot.Name, "| мой =", ok and ("да, " .. why) or "нет") end
        if ok and not found then found = plot end
    end
    if not found and State.spawnPos then
        local bd
        for _, plot in ipairs(pf:GetChildren()) do
            local p = posOf(plot)
            if p then
                local d = (p - State.spawnPos).Magnitude
                if not bd or d < bd then found, bd = plot, d end
            end
        end
        if found then dbg("ДОРОЖКА: владелец не определён — беру плот, ближайший к месту появления:", found.Name) end
    end
    State.plotCache = found
    if found then dbg("ДОРОЖКА: мой плот =", found:GetFullName()) else dbg("ДОРОЖКА: плот не найден") end
    return found
end

local function onTreadmill(tm)
    local hrp = getHRP()
    if not hrp then return false end
    local rel = tm.CFrame:PointToObjectSpace(hrp.Position)
    return math.abs(rel.X) <= tm.Size.X / 2 + 1.5 and math.abs(rel.Z) <= tm.Size.Z / 2 + 1.5
        and rel.Y >= -tm.Size.Y / 2 - 2 and rel.Y <= tm.Size.Y / 2 + 8
end

-- 1) MoveTo в центр  2) firetouchinterest(0/1)  3) пауза 0.5  4) fireproximityprompt
local function enterTreadmill(tm, plot, cond)
    local center = tm.Position + Vector3.new(0, tm.Size.Y / 2 + 3, 0)
    for attempt = 1, 3 do
        if not cond() or not alive() then return false end
        dbg("ДОРОЖКА: встаю в центр через MoveTo, попытка", attempt)
        if hdist(getHRP().Position, center) > 3 then walkTo(center, 2.5, cond) end
        if not cond() or not alive() then return false end
        getHum():MoveTo(center)
        task.wait(0.4)
        if not onTreadmill(tm) and attempt == 3 then
            dbg("ДОРОЖКА: MoveTo не помог 3 раза → PivotTo в центр (запасной вариант)")
            local hrp = getHRP()
            pcall(function() getChar():PivotTo(CFrame.new(center) * (hrp.CFrame - hrp.CFrame.Position)) end)
            task.wait(0.3)
        end
        if onTreadmill(tm) then
            dbg("ДОРОЖКА: стою на дорожке")
            if firetouchinterest then
                dbg("ДОРОЖКА: firetouchinterest(HRP, TreadmillBottom, 0 → 1)")
                pcall(function() firetouchinterest(getHRP(), tm, 0); task.wait(0.1); firetouchinterest(getHRP(), tm, 1) end)
            else
                dbg("ДОРОЖКА: firetouchinterest недоступен в этом экзекьюторе")
            end
            task.wait(0.5)
            local pr = tm:FindFirstChildWhichIsA("ProximityPrompt", true)
            if not pr and tm.Parent and tm.Parent ~= plot then pr = tm.Parent:FindFirstChildWhichIsA("ProximityPrompt", true) end
            local cd = tm:FindFirstChildWhichIsA("ClickDetector", true)
            if Config.TreadmillUsePrompt and (pr or cd) then
                if pr and fireproximityprompt then
                    dbg("ДОРОЖКА: fireproximityprompt →", pr:GetFullName())
                    pcall(fireproximityprompt, pr)
                elseif cd and fireclickdetector then
                    dbg("ДОРОЖКА: fireclickdetector →", cd:GetFullName())
                    pcall(fireclickdetector, cd)
                end
                task.wait(0.3)
            else
                dbg("ДОРОЖКА: prompt/click не найден — просто бегу")
            end
            return true
        end
        dbg("ДОРОЖКА: всё ещё не на дорожке — повторяю")
    end
    dbg("ДОРОЖКА: встать не удалось → prompt НЕ вызываю (иначе: Not at treadmill!)")
    return false
end

local function treadmillTick()
    if not Config.AutoTreadmill or not alive() then State.treadEntered = false; return end
    if (State.running or State.oneShot) and State.farming then State.treadEntered = false; return end   -- кража важнее
    local plot = findMyPlot()
    local tm = plot and plot:FindFirstChild("TreadmillBottom", true)
    if not tm then
        if not State.warnedTread then dbg("ДОРОЖКА: TreadmillBottom не найден в", plot and plot.Name or "?"); State.warnedTread = true end
        return
    end
    local cond = function() return IH.Alive and Config.AutoTreadmill and not ((State.running or State.oneShot) and State.farming) end
    local center = tm.Position + Vector3.new(0, tm.Size.Y / 2 + 3, 0)
    local d = hdist(getHRP().Position, center)
    if not State.treadEntered or d > 30 or not onTreadmill(tm) then
        if State.treadEntered then dbg(("ДОРОЖКА: слетел (%.0f studs от центра) — возвращаюсь"):format(d)) end
        State.treadEntered = enterTreadmill(tm, plot, cond)
        if not State.treadEntered then task.wait(2) end
        return
    end
    getHum():MoveTo(center + tm.CFrame.LookVector * Config.TreadmillDir * 50)          -- бежим по LookVector
end

-- ============================== МУЗЫКА ==================================
local sound = Instance.new("Sound")
sound.Name = "IvanHubMusic"; sound.Looped = true; sound.Volume = Config.Volume; sound.Parent = SoundService

local function resolveSoundId(id)
    id = tostring(id or "")
    if id:match("^%d+$") then return "rbxassetid://" .. id end
    if id:match("^rbxassetid://") or id:match("^rbxasset://") or id:match("^rbxplay://") then return id end
    if getcustomasset and isfile and isfile(id) then
        local ok, a = pcall(getcustomasset, id)
        if ok then return a end
    end
    return id
end
local function playTrack(i)
    local tr = Config.Music[i]
    if not tr then return end
    sound:Stop()
    sound.SoundId = resolveSoundId(tr.id)
    sound.Volume = Config.Volume
    sound:Play()
    dbg("МУЗЫКА: играю", tr.name, "|", sound.SoundId)
    if ui.musicStatus then ui.musicStatus.Text = "Играет: " .. tr.name end
    task.delay(5, function()
        if IH.Alive and sound.IsPlaying and sound.TimeLength == 0 then
            dbg("МУЗЫКА: трек не загрузился (ID недоступен в этом плейсе/регионе)")
            if ui.musicStatus then ui.musicStatus.Text = "Не загрузился: ID недоступен" end
        end
    end)
end
local function stopMusic()
    sound:Stop(); dbg("МУЗЫКА: стоп")
    if ui.musicStatus then ui.musicStatus.Text = "Остановлено" end
end

-- ============================== ESP / ПАНЕЛЬ ============================
local espFolder
local espObjs = {}
local function espUpdate(eggs)
    if not espFolder then return end
    local seen, hl = {}, 0
    if Config.ESP then
        local hrp = getHRP()
        table.sort(eggs, function(a, b)
            if not hrp then return false end
            return (a.pos - hrp.Position).Magnitude < (b.pos - hrp.Position).Magnitude
        end)
        for i, e in ipairs(eggs) do
            if i > 60 then break end
            seen[e.inst] = true
            local o = espObjs[e.inst]
            local anchor = (e.prompt and e.prompt.Parent and e.prompt.Parent:IsA("BasePart") and e.prompt.Parent)
                or (e.inst:IsA("BasePart") and e.inst) or e.inst:FindFirstChildWhichIsA("BasePart", true)
            if anchor then
                if not o or not o.bb.Parent then
                    local bb = Instance.new("BillboardGui")
                    bb.Adornee = anchor; bb.AlwaysOnTop = true; bb.Size = UDim2.fromOffset(200, 70); bb.StudsOffset = Vector3.new(0, 4, 0)
                    bb.MaxDistance = math.huge; bb.Parent = espFolder
                    local tl = Instance.new("TextLabel")
                    tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 1); tl.Font = Enum.Font.GothamBold; tl.TextSize = 12
                    tl.TextStrokeTransparency = 0.3; tl.Parent = bb
                    o = { bb = bb, tl = tl }
                    espObjs[e.inst] = o
                end
                local d = e.data
                local dist = hrp and math.floor((e.pos - hrp.Position).Magnitude) or 0
                o.tl.Text = ("🥚 %s · %s\nВес: %s kg · Доход: %s/s\n%s · %d studs"):format(d.name, RarityRU[d.rarity] or d.rarity,
                    fmt(d.weight), fmt(d.income), e.biome, dist)
                o.tl.TextColor3 = RarityColor[d.rarity] or Color3.fromRGB(255, 220, 80)
                if hl < 25 and (e.inst:IsA("Model") or e.inst:IsA("BasePart")) then
                    hl += 1
                    if not o.hl or not o.hl.Parent then
                        local h = Instance.new("Highlight")
                        h.Adornee = e.inst; h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; h.FillTransparency = 0.55
                        h.OutlineColor = Color3.new(1, 1, 1); h.Parent = espFolder
                        o.hl = h
                    end
                    o.hl.FillColor = o.tl.TextColor3
                end
            end
        end
    end
    for k, o in pairs(espObjs) do
        if not seen[k] then
            pcall(function() o.bb:Destroy() end)
            if o.hl then pcall(function() o.hl:Destroy() end) end
            espObjs[k] = nil
        end
    end
end

local panelRows = {}
local function panelUpdate(eggs)
    if not ui.list then return end
    local hrp = getHRP()
    table.sort(eggs, function(a, b)
        local ra, rb = RarityRank[a.data.rarity] or 0, RarityRank[b.data.rarity] or 0
        if ra ~= rb then return ra > rb end
        return (a.data.income or 0) > (b.data.income or 0)
    end)
    local sig = { tostring(#eggs) }
    for i, e in ipairs(eggs) do
        if i > 40 then break end
        sig[#sig + 1] = e.data.name .. e.data.rarity .. tostring(e.data.income) .. tostring(e.data.weight) .. tostring(Config.Favorites[e.data.name])
    end
    local s = table.concat(sig, "|")
    ui.listTitle.Text = ("⚙  Панель кражи · яиц: %d"):format(#eggs)
    if s == State.lastSig then return end                      -- ничего не изменилось — не пересоздаём строки
    State.lastSig = s
    for _, r in ipairs(panelRows) do r:Destroy() end
    panelRows = {}
    for i, e in ipairs(eggs) do
        if i > 40 then break end
        local d = e.data
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 66); row.BackgroundColor3 = Color3.fromRGB(30, 22, 52); row.BorderSizePixel = 0; row.Parent = ui.list
        local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0, 8); cr.Parent = row
        local nm = Instance.new("TextLabel")
        nm.BackgroundTransparency = 1; nm.Size = UDim2.new(1, -110, 0, 18); nm.Position = UDim2.fromOffset(8, 4); nm.Font = Enum.Font.GothamBold
        nm.TextSize = 13; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextColor3 = Color3.fromRGB(245, 240, 255)
        nm.TextTruncate = Enum.TextTruncate.AtEnd; nm.Text = d.name .. "  · " .. e.biome; nm.Parent = row
        local rr = Instance.new("TextLabel")
        rr.BackgroundTransparency = 1; rr.Size = UDim2.fromOffset(100, 18); rr.Position = UDim2.new(1, -104, 0, 4); rr.Font = Enum.Font.GothamBold
        rr.TextSize = 12; rr.TextXAlignment = Enum.TextXAlignment.Right; rr.Text = RarityRU[d.rarity] or d.rarity
        rr.TextColor3 = RarityColor[d.rarity] or Color3.fromRGB(200, 200, 200); rr.Parent = row
        local inf = Instance.new("TextLabel")
        inf.BackgroundTransparency = 1; inf.Size = UDim2.new(1, -16, 0, 16); inf.Position = UDim2.fromOffset(8, 24); inf.Font = Enum.Font.Gotham
        inf.TextSize = 12; inf.TextXAlignment = Enum.TextXAlignment.Left; inf.TextColor3 = Color3.fromRGB(190, 185, 215)
        inf.Text = ("Вес: %s kg   Доход: $%s/s%s"):format(fmt(d.weight), fmt(d.income), d.mutation and ("   ✦" .. d.mutation) or ""); inf.Parent = row
        local steal = Instance.new("TextButton")
        steal.Size = UDim2.new(0.5, -12, 0, 24); steal.Position = UDim2.new(0, 8, 1, -30); steal.BackgroundColor3 = Color3.fromRGB(50, 170, 90)
        steal.Text = "Красть"; steal.Font = Enum.Font.GothamBold; steal.TextSize = 12; steal.TextColor3 = Color3.new(1, 1, 1); steal.Parent = row
        local c1 = Instance.new("UICorner"); c1.CornerRadius = UDim.new(0, 6); c1.Parent = steal
        steal.MouseButton1Click:Connect(function()
            State.forced = e
            dbg("ПАНЕЛЬ: «Красть» →", d.name)
            if not State.running then startFarm(true) end
        end)
        local fav = Instance.new("TextButton")
        fav.Size = UDim2.new(0.5, -12, 0, 24); fav.Position = UDim2.new(0.5, 4, 1, -30)
        fav.BackgroundColor3 = Config.Favorites[d.name] and Color3.fromRGB(200, 150, 30) or Color3.fromRGB(70, 60, 100)
        fav.Text = Config.Favorites[d.name] and "★ В избранном" or "☆ Избранное"; fav.Font = Enum.Font.GothamBold; fav.TextSize = 12
        fav.TextColor3 = Color3.new(1, 1, 1); fav.Parent = row
        local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0, 6); c2.Parent = fav
        fav.MouseButton1Click:Connect(function()
            Config.Favorites[d.name] = (not Config.Favorites[d.name]) or nil
            fav.Text = Config.Favorites[d.name] and "★ В избранном" or "☆ Избранное"
            fav.BackgroundColor3 = Config.Favorites[d.name] and Color3.fromRGB(200, 150, 30) or Color3.fromRGB(70, 60, 100)
            State.lastSig = ""
        end)
        panelRows[#panelRows + 1] = row
    end
end

-- ============================== ИНТЕРФЕЙС ===============================
local function buildGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "IvanHubV6"; gui.ResetOnSpawn = false; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.DisplayOrder = 999
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    local okp = pcall(function() gui.Parent = (gethui and gethui()) or CoreGui end)
    if not okp or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
    ui.gui = gui
    espFolder = Instance.new("Folder"); espFolder.Name = "ESP"; espFolder.Parent = gui

    local BG, PANEL, ACC, ACC2 = Color3.fromRGB(14, 10, 26), Color3.fromRGB(34, 24, 60), Color3.fromRGB(138, 92, 255), Color3.fromRGB(255, 140, 40)
    local TXT, GREEN, OFF = Color3.fromRGB(240, 235, 252), Color3.fromRGB(50, 170, 90), Color3.fromRGB(70, 60, 100)
    local function corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = i end
    local function stroke(i, col, th, tr) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th or 1.2; s.Transparency = tr or 0.4; s.Parent = i end
    local function grad(i, c1, c2, rot) local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(c1, c2); g.Rotation = rot or 0; g.Parent = i end
    local function tw(i, t, p) TweenService:Create(i, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), p):Play() end
    local function txt(parent, text, size, pos, fs, bold)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1; l.Size = size; l.Position = pos or UDim2.new(); l.Text = text; l.TextColor3 = TXT
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham; l.TextSize = fs or 13; l.TextWrapped = true
        l.TextXAlignment = Enum.TextXAlignment.Left; l.TextYAlignment = Enum.TextYAlignment.Top; l.Parent = parent
        return l
    end

    local W_, H_, PW = 470, 430, 320
    local TOTAL = W_ + PW + 8
    local root = Instance.new("CanvasGroup")
    root.Size = UDim2.fromOffset(TOTAL, H_); root.BackgroundTransparency = 1; root.Parent = gui
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local fit = math.min(1, (vp.X - 16) / TOTAL, (vp.Y - 16) / H_)
    local sc = Instance.new("UIScale"); sc.Scale = fit; sc.Parent = root
    root.Position = UDim2.new(0.5, -TOTAL * fit / 2, 0.5, -H_ * fit / 2)

    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(W_, H_); main.BackgroundColor3 = BG; main.BorderSizePixel = 0; main.Parent = root
    corner(main, 12); stroke(main, ACC, 1.4, 0.35)
    local head = Instance.new("TextButton")
    head.Size = UDim2.new(1, 0, 0, 36); head.Text = ""; head.AutoButtonColor = false; head.BorderSizePixel = 0
    head.BackgroundColor3 = Color3.new(1, 1, 1); head.Parent = main; corner(head, 12); grad(head, ACC, ACC2, 0)
    txt(head, "Иван Хаб  ·  Steal an Egg  ·  v6", UDim2.new(1, -16, 1, 0), UDim2.fromOffset(12, 9), 14, true).TextColor3 = Color3.new(1, 1, 1)

    -- Правая «Панель кражи»
    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(PW, H_); panel.Position = UDim2.fromOffset(W_ + 8, 0); panel.BackgroundColor3 = BG
    panel.BorderSizePixel = 0; panel.Parent = root; corner(panel, 12); stroke(panel, ACC2, 1.4, 0.35)
    local ph = Instance.new("TextButton")
    ph.Size = UDim2.new(1, 0, 0, 36); ph.Text = ""; ph.AutoButtonColor = false; ph.BorderSizePixel = 0
    ph.BackgroundColor3 = Color3.new(1, 1, 1); ph.Parent = panel; corner(ph, 12); grad(ph, ACC2, Color3.fromRGB(255, 90, 40), 0)
    ui.listTitle = txt(ph, "⚙  Панель кражи", UDim2.new(1, -16, 1, 0), UDim2.fromOffset(12, 9), 15, true)
    ui.listTitle.TextColor3 = Color3.new(1, 1, 1)
    ui.autoBtn = Instance.new("TextButton")
    ui.autoBtn.Size = UDim2.new(1, -16, 0, 32); ui.autoBtn.Position = UDim2.fromOffset(8, 44); ui.autoBtn.Font = Enum.Font.GothamBold
    ui.autoBtn.TextSize = 14; ui.autoBtn.TextColor3 = Color3.new(1, 1, 1); ui.autoBtn.Parent = panel; corner(ui.autoBtn, 8)
    local function refreshAuto()
        ui.autoBtn.Text = "Автокража: " .. (State.running and "ВКЛ" or "ВЫКЛ")
        tw(ui.autoBtn, 0.15, { BackgroundColor3 = State.running and GREEN or OFF })
    end
    ui.autoBtn.MouseButton1Click:Connect(function()
        if State.running then stopFarm() else startFarm(false) end
        refreshAuto()
    end)
    refreshAuto()
    ui.list = Instance.new("ScrollingFrame")
    ui.list.Size = UDim2.new(1, -12, 1, -88); ui.list.Position = UDim2.fromOffset(6, 82); ui.list.BackgroundTransparency = 1
    ui.list.BorderSizePixel = 0; ui.list.ScrollBarThickness = 3; ui.list.AutomaticCanvasSize = Enum.AutomaticSize.Y; ui.list.CanvasSize = UDim2.new()
    ui.list.Parent = panel
    do local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 5); l.Parent = ui.list end

    -- перетаскивание за шапки
    local function drag(handle)
        local dragging, ds, sp
        handle.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging, ds, sp = true, i.Position, root.Position
                i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
            end
        end)
        connect(UIS.InputChanged, function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - ds
                root.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
            end
        end)
    end
    drag(head); drag(ph)

    -- показ/скрытие с анимацией
    local menuOpen = true
    local function setMenu(open)
        menuOpen = open
        if open then
            root.Visible = true; sc.Scale = fit * 0.92; root.GroupTransparency = 1
            tw(root, 0.25, { GroupTransparency = 0 }); tw(sc, 0.25, { Scale = fit })
        else
            tw(root, 0.2, { GroupTransparency = 1 }); tw(sc, 0.2, { Scale = fit * 0.92 })
            task.delay(0.22, function() if not menuOpen then root.Visible = false end end)
        end
    end
    connect(UIS.InputBegan, function(i, gp)
        if not gp and i.KeyCode == Enum.KeyCode.RightShift then setMenu(not menuOpen) end
    end)

    -- круглая перетаскиваемая кнопка
    local orb = Instance.new("TextButton")
    orb.Size = UDim2.fromOffset(54, 54); orb.Position = UDim2.new(0, 14, 0.5, -27); orb.Text = "ИХ"; orb.Font = Enum.Font.GothamBold
    orb.TextSize = 18; orb.TextColor3 = Color3.new(1, 1, 1); orb.AutoButtonColor = false; orb.BackgroundColor3 = Color3.new(1, 1, 1)
    orb.ZIndex = 100; orb.Parent = gui; corner(orb, 27); stroke(orb, ACC2, 2, 0.15); grad(orb, ACC, ACC2, 45)
    do
        local down, moved, ds, sp = false, false, nil, nil
        orb.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                down, moved, ds, sp = true, false, i.Position, orb.Position
                tw(orb, 0.1, { Size = UDim2.fromOffset(48, 48) })
            end
        end)
        connect(UIS.InputChanged, function(i)
            if down and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - ds
                if d.Magnitude > 6 then moved = true end
                if moved then orb.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y) end
            end
        end)
        connect(UIS.InputEnded, function(i)
            if down and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
                down = false
                tw(orb, 0.1, { Size = UDim2.fromOffset(54, 54) })
                if not moved then setMenu(not menuOpen) end
            end
        end)
    end

    -- вкладки
    local tabsBar = Instance.new("Frame")
    tabsBar.Size = UDim2.new(1, -16, 0, 28); tabsBar.Position = UDim2.fromOffset(8, 42); tabsBar.BackgroundTransparency = 1; tabsBar.Parent = main
    do local l = Instance.new("UIListLayout"); l.FillDirection = Enum.FillDirection.Horizontal; l.Padding = UDim.new(0, 6); l.Parent = tabsBar end
    local pages, tabBtns = {}, {}
    local function selectTab(name)
        for n, p in pairs(pages) do p.Visible = (n == name) end
        for n, b in pairs(tabBtns) do tw(b, 0.15, { BackgroundColor3 = n == name and ACC or PANEL }) end
    end
    local function page(name)
        local p = Instance.new("ScrollingFrame")
        p.Size = UDim2.new(1, -16, 1, -78); p.Position = UDim2.fromOffset(8, 74); p.BackgroundTransparency = 1; p.BorderSizePixel = 0
        p.ScrollBarThickness = 3; p.AutomaticCanvasSize = Enum.AutomaticSize.Y; p.CanvasSize = UDim2.new(); p.Visible = false; p.Parent = main
        local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 6); l.Parent = p
        pages[name] = p
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(100, 28); b.Text = name; b.Font = Enum.Font.GothamMedium; b.TextSize = 13; b.TextColor3 = TXT
        b.BackgroundColor3 = PANEL; b.AutoButtonColor = false; b.Parent = tabsBar; corner(b, 7)
        tabBtns[name] = b
        b.MouseButton1Click:Connect(function() selectTab(name) end)
        return p
    end
    local function button(pg, text, fn, colorful)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 32); b.Text = text; b.TextColor3 = Color3.new(1, 1, 1); b.Font = Enum.Font.GothamBold; b.TextSize = 13
        b.BackgroundColor3 = colorful and Color3.new(1, 1, 1) or PANEL; b.Parent = pg; corner(b, 7)
        if colorful then grad(b, ACC, ACC2, 0) end
        b.MouseButton1Click:Connect(function() task.spawn(function() local ok, e = xpcall(fn, tb, b); if not ok then dbg("ОШИБКА кнопки:", e) end end) end)
        return b
    end
    local function cycler(pg, label, getv, options, setv)
        local b
        b = button(pg, "", function()
            local cur, idx = getv(), 1
            for i, o in ipairs(options) do if o == cur then idx = i end end
            local nv = options[idx % #options + 1]
            setv(nv)
            b.Text = label .. ": " .. tostring(nv) .. "  ›"
            dbg("НАСТРОЙКА:", label, "=", nv)
        end)
        b.Text = label .. ": " .. tostring(getv()) .. "  ›"
        return b
    end
    local function input(pg, placeholder, default, cb)
        local tb_ = Instance.new("TextBox")
        tb_.Size = UDim2.new(1, -6, 0, 28); tb_.BackgroundColor3 = PANEL; tb_.Text = default or ""; tb_.TextColor3 = TXT; tb_.Font = Enum.Font.Gotham
        tb_.TextSize = 12; tb_.ClearTextOnFocus = false; tb_.PlaceholderText = placeholder; tb_.TextXAlignment = Enum.TextXAlignment.Left; tb_.Parent = pg
        corner(tb_, 6)
        tb_.FocusLost:Connect(function() cb(tb_.Text) end)
        return tb_
    end

    -- Кража
    local pS = page("Кража")
    ui.status = txt(pS, "Статус: ожидание", UDim2.new(1, -6, 0, 18), nil, 13, true)
    local bOpts = { "Auto", "All" }
    for _, b in ipairs(Config.Biomes) do bOpts[#bOpts + 1] = b.name end
    cycler(pS, "Биом", function() return Config.StartBiome end, bOpts, function(v) Config.StartBiome = v end)
    cycler(pS, "Приоритет", function() return Config.Priority end, { "Closest", "Income", "Rarity", "Weight" }, function(v) Config.Priority = v end)
    cycler(pS, "Движение", function() return Config.MoveMode end, { "Walk", "Fly" }, function(v) Config.MoveMode = v end)
    cycler(pS, "Хэллоуин", function() return Config.Halloween and "ВКЛ" or "ВЫКЛ" end, { "ВЫКЛ", "ВКЛ" }, function(v) Config.Halloween = (v == "ВКЛ") end)
    cycler(pS, "ESP", function() return Config.ESP and "ВКЛ" or "ВЫКЛ" end, { "ВЫКЛ", "ВКЛ" }, function(v) Config.ESP = (v == "ВКЛ") end)
    cycler(pS, "Debug-print", function() return Config.Debug and "ВКЛ" or "ВЫКЛ" end, { "ВКЛ", "ВЫКЛ" }, function(v) Config.Debug = (v == "ВКЛ") end)
    button(pS, "Дамп AreaEggSlotsClient (в консоль)", function()
        print("[DEBUG] ===== ДАМП AreaEggSlotsClient =====")
        local f = workspace:FindFirstChild("AreaEggSlotsClient")
        if not f then print("[DEBUG] AreaEggSlotsClient НЕ НАЙДЕН"); return end
        local slots = {}
        collectSlots(f, slots, 0)
        print("[DEBUG] слотов с prompt:", #slots, "| детей в папке:", #f:GetChildren())
        for i, s in ipairs(slots) do
            if i > 12 then break end
            local e = buildEgg(s.inst, s.prompt)
            print("[DEBUG]", s.inst.Name, "| биом:", e.biome, "| prompt.Enabled:", s.prompt.Enabled, "| текст:", e.data.text)
            print("[DEBUG]    вес:", e.data.weight, "доход:", e.data.income, "редкость:", e.data.rarity)
        end
    end)
    ui.log = txt(pS, "(лог появится здесь)", UDim2.new(1, -6, 0, 120), nil, 11)
    ui.log.TextColor3 = Color3.fromRGB(180, 175, 205)

    -- Дорожка
    local pT = page("Дорожка")
    local tBtn
    tBtn = button(pT, "Авто-дорожка: ВЫКЛ", function()
        Config.AutoTreadmill = not Config.AutoTreadmill
        State.treadEntered = false
        tBtn.Text = "Авто-дорожка: " .. (Config.AutoTreadmill and "ВКЛ" or "ВЫКЛ")
        dbg("ДОРОЖКА:", Config.AutoTreadmill and "включена" or "выключена")
    end, true)
    button(pT, "Развернуть направление бега", function() Config.TreadmillDir = -Config.TreadmillDir; dbg("ДОРОЖКА: направление =", Config.TreadmillDir) end)
    button(pT, "Найти мой плот (дамп в консоль)", function()
        State.plotCache = nil; State.plotDumped = false; State.warnedTread = false
        local p = findMyPlot()
        if p then dbg("TreadmillBottom:", p:FindFirstChild("TreadmillBottom", true) and "найден" or "НЕ НАЙДЕН") end
    end)
    txt(pT, "Порядок: MoveTo в центр → firetouchinterest → пауза 0.5 c → fireproximityprompt → бег по LookVector. Кража важнее дорожки.", UDim2.new(1, -6, 0, 60), nil, 12)

    -- Музыка
    local pM = page("Музыка")
    ui.musicStatus = txt(pM, "Остановлено", UDim2.new(1, -6, 0, 18), nil, 13, true)
    for i, tr in ipairs(Config.Music) do
        button(pM, "▶ " .. tr.name, function() playTrack(i) end, true)
        input(pM, "ID / rbxassetid://... / путь к файлу", tr.id, function(t) Config.Music[i].id = t; dbg("МУЗЫКА: ID трека", i, "=", t) end)
    end
    button(pM, "■ Стоп", function() stopMusic() end)
    cycler(pM, "Громкость", function() return Config.Volume end, { 0.2, 0.5, 0.8, 1 }, function(v) Config.Volume = v; sound.Volume = v end)

    -- Настройки
    local pC = page("Настройки")
    cycler(pC, "Проверка скорости", function() return Config.IgnoreSpeedCheck and "выкл" or "вкл" end, { "вкл", "выкл" }, function(v) Config.IgnoreSpeedCheck = (v == "выкл") end)
    cycler(pC, "Запас к скорости", function() return Config.SpeedMargin end, { 1, 1.25, 1.5, 2 }, function(v) Config.SpeedMargin = v end)
    input(pC, "Ручная «скорость» (число, 0 = авто)", tostring(Config.SpeedOverride), function(t) Config.SpeedOverride = parseNum(t) or 0; dbg("Скорость вручную =", Config.SpeedOverride) end)
    cycler(pC, "Anti-Knockback", function() return Config.AntiKnockback and "ВКЛ" or "ВЫКЛ" end, { "ВКЛ", "ВЫКЛ" }, function(v) Config.AntiKnockback = (v == "ВКЛ") end)
    cycler(pC, "Гасить скорость каждый кадр", function() return Config.KnockbackEveryFrame and "ДА" or "нет" end, { "нет", "ДА" }, function(v) Config.KnockbackEveryFrame = (v == "ДА") end)
    cycler(pC, "Скорость полёта", function() return Config.FlySpeed end, { 50, 80, 120, 200 }, function(v) Config.FlySpeed = v end)
    button(pC, "ВЫГРУЗИТЬ СКРИПТ", function() IH.Unload() end, true)

    selectTab("Кража")
    ui.refreshAuto = refreshAuto
end

-- ============================== ЗАЩИТА / ЦИКЛЫ ==========================
connect(RunService.Heartbeat, function()
    local hum, hrp = getHum(), getHRP()
    if not hum or not hrp then return end
    if Config.AntiKnockback then
        if hum.PlatformStand then hum.PlatformStand = false end                      -- каждый кадр
        if not State.moving then
            local v = hrp.AssemblyLinearVelocity
            local h = Vector3.new(v.X, 0, v.Z).Magnitude
            if Config.KnockbackEveryFrame or h > hum.WalkSpeed * 1.5 + 15 then
                hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.1, v.Y, v.Z * 0.1)       -- гасим только X/Z
            end
        end
    end
end)
connect(RunService.Stepped, function()
    if State.noclip and getChar() then
        for _, p in ipairs(getChar():GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end
end)

IH.Unload = function()
    IH.Alive = false
    State.running = false; State.oneShot = false; State.gen += 1; State.noclip = false
    for _, c in ipairs(IH.Conns) do pcall(function() c:Disconnect() end) end
    pcall(function() sound:Stop(); sound:Destroy() end)
    pcall(function() if ui.gui then ui.gui:Destroy() end end)
    env.IvanHubV6 = nil
    print("[DEBUG] Скрипт выгружен")
end

-- ============================== ЗАПУСК ==================================
dbg("Скрипт v6 запущен. Игрок:", LP.Name)
local okGui, errGui = xpcall(buildGui, tb)
if not okGui then print("[DEBUG] ОШИБКА ПОСТРОЕНИЯ GUI:", errGui) end

task.spawn(function()
    local okS, errS = xpcall(function()
        for _ = 1, 40 do if getHRP() then break end; task.wait(0.25) end
        State.spawnPos = getHRP() and getHRP().Position
        dbg("Проверка путей: AreaEggSlotsClient =", workspace:FindFirstChild("AreaEggSlotsClient") and "есть" or "НЕТ",
            "| SafeZone =", dig(workspace, "World.Areas.EggCarryBounds.SafeZone") and "есть" or "НЕТ",
            "| Plots =", workspace:FindFirstChild("Plots") and "есть" or "НЕТ")
        dbg("Функции экзекьютора: fireproximityprompt =", fireproximityprompt ~= nil, "| fireclickdetector =", fireclickdetector ~= nil,
            "| firetouchinterest =", firetouchinterest ~= nil)
        dbg("Скорость для выбора биома:", fmt(getSpeed()), "(если неверно — задай вручную в «Настройки»)")
        local list = gatherEggs(false)
        dbg("Стартовая проверка яиц:", #list)
        setStatus("готов. Включи «Автокража» на панели справа")
    end, tb)
    if not okS then dbg("ОШИБКА СТАРТА:", errS) end
end)

task.spawn(function()
    while IH.Alive do
        local ok, err = xpcall(function()
            local eggs = gatherEggs(true)
            panelUpdate(eggs)
            espUpdate(eggs)
            if ui.refreshAuto then ui.refreshAuto() end
        end, tb)
        if not ok then dbg("ОШИБКА панели/ESP:", err) end
        task.wait(2)
    end
end)

task.spawn(function()
    while IH.Alive do
        local ok, err = xpcall(treadmillTick, tb)
        if not ok then dbg("ОШИБКА дорожки:", err) end
        task.wait(0.25)
    end
end)

connect(LP.CharacterAdded, function()
    task.wait(1.5)
    State.treadEntered = false; State.noclip = false; State.moving = false
    dbg("Респавн: персонаж создан заново")
end)

end

local okMain, errMain = xpcall(IvanHubMain, function(e)
    return tostring(e) .. " | " .. ((debug and debug.traceback) and debug.traceback("", 2) or "")
end)
if not okMain then print("[DEBUG] КРИТИЧЕСКАЯ ОШИБКА СКРИПТА (моего кода):", errMain) end
