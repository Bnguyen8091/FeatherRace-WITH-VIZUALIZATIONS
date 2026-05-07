-- FeatherRace - LÖVE2D Graphical Version

local tools   = require("stats")
local track   = require("race")
local shopMod = require("shop")
local json    = require("json")
local trainer = require("trainer")

math.randomseed(os.time())

-- Print intercept
local gameLog = {}
local _print  = print
print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    local line = table.concat(t, "  "):gsub("^[\n%s]+", "")
    if line ~= "" then
        table.insert(gameLog, line)
        if #gameLog > 60 then table.remove(gameLog, 1) end
    end
    _print(...)
end

-- Window
local W, H = 960, 600

-- Colors
local C = {
    bg     = { 0.06, 0.06, 0.14 },
    panel  = { 0.10, 0.10, 0.22 },
    border = { 0.28, 0.28, 0.65 },
    title  = { 1.00, 0.85, 0.00 },
    sel    = { 1.00, 0.42, 0.18 },
    normal = { 0.85, 0.85, 0.90 },
    dim    = { 0.48, 0.48, 0.58 },
    green  = { 0.22, 0.88, 0.44 },
    red    = { 1.00, 0.28, 0.28 },
    blue   = { 0.40, 0.72, 1.00 },
}

local fLarge, fMed, fSmall

-- State
local state = "menu"

-- Draw helpers
local function rgb(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function drawPanel(x, y, w, h)
    rgb(C.panel)
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    rgb(C.border)
    love.graphics.rectangle("line", x, y, w, h, 5, 5)
end

local function centered(text, y, color, font)
    if font then love.graphics.setFont(font) end
    rgb(color or C.normal)
    love.graphics.printf(text, 0, y, W, "center")
end

local function statBar(val, max, x, y, w)
    rgb(C.panel)
    love.graphics.rectangle("fill", x, y, w, 10)
    local r = math.min(val / max, 1)
    rgb(r > 0.6 and C.green or (r > 0.3 and C.title or C.red))
    love.graphics.rectangle("fill", x, y, w * r, 10)
    rgb(C.border)
    love.graphics.rectangle("line", x, y, w, 10)
end

-- Save / load
local function saveExists()
    local f = io.open("savegame.json", "r")
    if f then f:close() return true end
    return false
end

local function doSave()
    local ok, data = pcall(function()
        return { bird = tools.getBird(), race = track.getRaceData(), purchases = shopMod.getPurchases() }
    end)
    if not ok then return false end
    local f = io.open("savegame.json", "w")
    if f then f:write(json.encode(data)); f:close(); return true end
    return false
end

local function doLoad()
    local f = io.open("savegame.json", "r")
    if not f then return false end
    local raw = f:read("*a"); f:close()
    local ok, data = pcall(json.decode, raw)
    if ok and data then
        if data.bird      then tools.setBird(data.bird)             end
        if data.race      then track.setRaceData(data.race)         end
        if data.purchases then shopMod.setPurchases(data.purchases) end
        return true
    end
    return false
end

-- Menu
local menu = { items = {}, sel = 1 }

local function buildMenu()
    if saveExists() then
        menu.items = {
            { label = "Continue",    id = "continue"   },
            { label = "New Game",    id = "newgame"    },
            { label = "Delete Save", id = "deletesave" },
        }
    else
        menu.items = { { label = "New Game", id = "newgame" } }
    end
    menu.sel = 1
end

local function drawMenu()
    centered("FEATHERRACE", 90, C.title, fLarge)
    centered("WITH VISUALIZATIONS", 160, C.dim, fSmall)

    local bw = 320
    local bh = #menu.items * 58 + 36
    local bx = (W - bw) / 2
    local by = 210
    drawPanel(bx, by, bw, bh)

    love.graphics.setFont(fMed)
    for i, item in ipairs(menu.items) do
        local ty = by + 18 + (i - 1) * 58
        if i == menu.sel then
            rgb(C.sel)
            love.graphics.printf("> " .. item.label .. " <", bx, ty, bw, "center")
        else
            rgb(C.normal)
            love.graphics.printf(item.label, bx, ty, bw, "center")
        end
    end

    centered("[UP / DOWN]  Navigate     [ENTER]  Select", H - 36, C.dim, fSmall)
end

-- Name entry
local nameText = ""

local function drawNameEntry()
    centered("NAME YOUR BIRD", 160, C.title, fMed)
    local bw = 420
    local bx = (W - bw) / 2
    drawPanel(bx, 240, bw, 64)
    rgb(C.normal)
    love.graphics.setFont(fMed)
    local cursor = love.timer.getTime() % 1 < 0.5 and "|" or " "
    love.graphics.printf(nameText .. cursor, bx, 258, bw, "center")
    centered("[ENTER]  Confirm     [BACKSPACE]  Delete     [ESC]  Back", H - 36, C.dim, fSmall)
end

-- Gameplay
local gp = {
    sub       = "main",  -- main | training | shop | result | rate | gameover | champion
    trainSel  = 1,
    shopSel   = 1,
    result    = nil,     -- "win" | "lose" | "champion"
    rateLines = {},
}

-- Layout
local PAD     = 8
local TOP_Y   = 50
local CMD_H   = 58
local SIDE_W  = 195
local MID_X   = SIDE_W + PAD * 2
local MID_W   = W - SIDE_W * 2 - PAD * 4
local PANEL_H = H - TOP_Y - CMD_H - PAD * 3

local function moodStr(happiness)
    if happiness <= 1 then return "Awful"
    elseif happiness <= 3 then return "Bad"
    elseif happiness <= 5 then return "Normal"
    elseif happiness <= 7 then return "Good"
    else return "Great" end
end

local function drawBirdPanel()
    drawPanel(PAD, TOP_Y, SIDE_W, PANEL_H)
    local b = tools.getBird()
    love.graphics.setFont(fSmall)
    rgb(C.title)
    love.graphics.printf("BIRD STATUS", PAD, TOP_Y + 10, SIDE_W, "center")

    local lx = PAD + 10
    local ly = TOP_Y + 32
    local lh = 26
    local bw = 68

    rgb(C.normal)
    love.graphics.printf(b.name, PAD, ly, SIDE_W, "center")
    ly = ly + lh

    local function row(label, val, max)
        rgb(C.dim);    love.graphics.print(label, lx, ly)
        statBar(val, max, lx + 54, ly + 3, bw)
        rgb(C.normal); love.graphics.print(string.format("%.1f", val), lx + 128, ly)
        ly = ly + lh
    end

    row("STA", b.stamina,  10)
    row("SPD", b.speed,    25)
    row("RUN", b.running,  25)
    row("SWM", b.swimming, 25)
    row("FLY", b.flying,   25)

    local mood = moodStr(b.happiness)
    local moodCol = b.happiness <= 3 and C.red or (b.happiness >= 8 and C.green or C.title)
    rgb(C.dim);    love.graphics.print("MOOD", lx, ly)
    rgb(moodCol);  love.graphics.print(mood, lx + 54, ly)
    ly = ly + lh

    rgb(C.dim);   love.graphics.print("GOLD", lx, ly)
    rgb(C.title); love.graphics.print(tostring(b.money), lx + 54, ly)
end

local function drawRacePanel()
    local rx = W - SIDE_W - PAD
    drawPanel(rx, TOP_Y, SIDE_W, PANEL_H)
    local rd = track.getRaceData()
    love.graphics.setFont(fSmall)
    rgb(C.title)
    love.graphics.printf("NEXT RACE", rx, TOP_Y + 10, SIDE_W, "center")

    local lx = rx + 10
    local ly = TOP_Y + 32
    local lh = 24

    local function row(label, val, col)
        rgb(C.dim);        love.graphics.print(label, lx, ly)
        rgb(col or C.normal); love.graphics.print(tostring(val), lx + 56, ly)
        ly = ly + lh
    end

    local stages = { "Race 1", "Race 2", "Final" }
    row("STAGE", stages[rd.stage] or "?", C.title)
    local dayCol = rd.daysLeft <= 2 and C.red or (rd.daysLeft <= 5 and C.title or C.green)
    row("DAYS",  rd.daysLeft, dayCol)
    row("DIST",  rd.distance .. "m")
    row("RUN",   string.format("%.0f%%", rd.running))
    row("SWM",   string.format("%.0f%%", rd.swimming))
    row("FLY",   string.format("%.0f%%", rd.flying))

    ly = ly + 4
    rgb(C.dim)
    love.graphics.print("NAME", lx, ly); ly = ly + 16
    rgb(C.normal)
    love.graphics.printf(rd.name, lx, ly, SIDE_W - 20, "left")
end

local function drawLogPanel()
    drawPanel(MID_X, TOP_Y, MID_W, PANEL_H)
    love.graphics.setFont(fSmall)
    rgb(C.title)
    love.graphics.printf("LOG", MID_X, TOP_Y + 8, MID_W, "center")

    local lineH    = 17
    local visCount = math.floor((PANEL_H - 28) / lineH)
    local start    = math.max(1, #gameLog - visCount + 1)

    for i = start, #gameLog do
        local ly   = TOP_Y + 26 + (i - start) * lineH
        local line = gameLog[i]
        local col  = C.normal
        if line:find("GAME OVER") or line:find("LAST PLACE") then col = C.red
        elseif line:find("CHAMPION") or line:find("1ST PLACE") or line:find("won ") then col = C.green
        elseif line:find("Stamina restored") or line:find("earned") or line:find("restored") then col = C.blue
        elseif line:find("===") or line:find("---") then col = C.dim
        end
        rgb(col)
        love.graphics.print(line, MID_X + 8, ly)
    end
end

local cmdDefs = {
    { key = "F", label = "Feed"  },
    { key = "T", label = "Train" },
    { key = "P", label = "Play"  },
    { key = "R", label = "Rest"  },
    { key = "S", label = "Shop"  },
    { key = "V", label = "Rate"  },
    { key = "I", label = "Info"  },
    { key = "Q", label = "Quit"  },
}

local function drawCmdBar()
    local cy   = H - CMD_H - PAD
    local cw   = W - PAD * 2
    drawPanel(PAD, cy, cw, CMD_H)

    local count = #cmdDefs
    local btnW  = math.floor((cw - (count + 1) * 6) / count)

    love.graphics.setFont(fSmall)
    for i, cmd in ipairs(cmdDefs) do
        local bx = PAD + 6 + (i - 1) * (btnW + 6)
        local by = cy + 8
        rgb(C.border)
        love.graphics.rectangle("fill", bx, by, btnW, 40, 4, 4)
        rgb(C.title)
        love.graphics.printf("[" .. cmd.key .. "]", bx, by + 5, btnW, "center")
        rgb(C.normal)
        love.graphics.printf(cmd.label, bx, by + 22, btnW, "center")
    end
end

local function drawGameplayBase()
    love.graphics.setFont(fSmall)
    local rd     = track.getRaceData()
    local stages = { "Race 1", "Race 2", "Final Race" }
    rgb(C.dim)
    love.graphics.printf("FEATHERRACE  ·  " .. (stages[rd.stage] or "?") .. "  ·  " .. rd.daysLeft .. " days left", 0, 16, W, "center")
    drawBirdPanel()
    drawLogPanel()
    drawRacePanel()
    drawCmdBar()
end

-- Training
local trainOpts = {
    { label = "Speed",    fn = tools.trainSpeed    },
    { label = "Running",  fn = tools.trainRunning  },
    { label = "Swimming", fn = tools.trainSwimming },
    { label = "Flying",   fn = tools.trainFlying   },
    { label = "Back",     fn = nil                 },
}

local function drawTrainingOverlay()
    local bw = 340
    local bh = #trainOpts * 52 + 72
    local bx = (W - bw) / 2
    local by = (H - bh) / 2
    drawPanel(bx, by, bw, bh)
    centered("TRAINING", by + 14, C.title, fMed)
    love.graphics.setFont(fSmall)
    rgb(C.dim)
    love.graphics.printf("Costs 1 stamina + 1 happiness  |  Max: 25", bx, by + 44, bw, "center")
    love.graphics.setFont(fMed)
    for i, opt in ipairs(trainOpts) do
        local ty = by + 66 + (i - 1) * 52
        if i == gp.trainSel then
            rgb(C.sel); love.graphics.printf("> " .. opt.label .. " <", bx, ty, bw, "center")
        else
            rgb(C.normal); love.graphics.printf(opt.label, bx, ty, bw, "center")
        end
    end
    centered("[UP / DOWN]  Navigate     [ENTER]  Select     [ESC]  Back", H - 36, C.dim, fSmall)
end

-- Shop
local shopOpts = {
    { label = "Flippers   — Swim ×1.25  (race booster)", id = 1,  key = "flippers",  price = 25 },
    { label = "Jetpack    — Fly  ×1.25  (race booster)", id = 2,  key = "jetpack",   price = 25 },
    { label = "Run Shoes  — Run  ×1.25  (race booster)", id = 3,  key = "shoes",     price = 25 },
    { label = "Energy Drink — restore stamina",           id = 4,  key = nil,         price = 20 },
    { label = "Treats      — restore happiness",          id = 5,  key = nil,         price = 20 },
    { label = "Pool       — Swim training ×1.1",         id = 6,  key = "pool",      price = 50 },
    { label = "Giant Fan  — Fly  training ×1.1",         id = 7,  key = "fan",       price = 50 },
    { label = "Treadmill  — Run  training ×1.1",         id = 8,  key = "treadmill", price = 50 },
    { label = "Playroom   — Play effectiveness ×1.1",    id = 9,  key = "playroom",  price = 50 },
    { label = "Better Bed — Rest +1",                    id = 10, key = "bed",       price = 50 },
    { label = "Leave Shop",                              id = 0,  key = nil,         price = 0  },
}

local function drawShopOverlay()
    local b  = tools.getBird()
    local bw = 540
    local bh = #shopOpts * 30 + 84
    local bx = (W - bw) / 2
    local by = math.max(8, (H - bh) / 2)
    drawPanel(bx, by, bw, bh)
    centered("SHOP", by + 10, C.title, fMed)
    love.graphics.setFont(fSmall)
    rgb(C.dim)
    love.graphics.printf("Coins: " .. b.money, bx, by + 38, bw, "center")

    for i, item in ipairs(shopOpts) do
        local ty    = by + 60 + (i - 1) * 30
        local owned = item.key and shopMod.has(item.key)
        local txt
        if item.id == 0 then
            txt = item.label
        elseif owned then
            txt = "[OWNED] " .. item.label
        else
            txt = item.label .. "  (" .. item.price .. "g)"
        end
        local col = owned and C.dim or C.normal
        if i == gp.shopSel then
            rgb(C.sel); love.graphics.printf("> " .. txt .. " <", bx, ty, bw, "center")
        else
            rgb(col);   love.graphics.printf(txt, bx, ty, bw, "center")
        end
    end
    centered("[UP / DOWN]  Navigate     [ENTER]  Buy     [ESC]  Leave", H - 36, C.dim, fSmall)
end

-- Race result
local function drawResultOverlay()
    local bw, bh = 540, 310
    local bx = (W - bw) / 2
    local by = (H - bh) / 2
    drawPanel(bx, by, bw, bh)

    love.graphics.setFont(fMed)
    if gp.result == "champion" then
        rgb(C.title); love.graphics.printf("FEATHERRACE CHAMPION!", bx, by + 16, bw, "center")
    elseif gp.result == "win" then
        rgb(C.green); love.graphics.printf("1ST PLACE!", bx, by + 16, bw, "center")
    else
        rgb(C.red);   love.graphics.printf("LAST PLACE  (8th of 8)", bx, by + 16, bw, "center")
    end

    -- Show race log lines, skipping decorator lines
    love.graphics.setFont(fSmall)
    local lineH    = 19
    local visCount = math.floor((bh - 78) / lineH)
    local start    = math.max(1, #gameLog - visCount + 1)
    for i = start, #gameLog do
        local line = gameLog[i]
        local ly   = by + 56 + (i - start) * lineH
        local col
        if line:find("===") or line:find("---") then
            col = C.dim
        elseif line:find("1ST PLACE") or line:find("CHAMPION") or line:find("earned") then
            col = C.green
        elseif line:find("LAST PLACE") or line:find("GAME OVER") then
            col = C.red
        elseif line:find("covered") or line:find("Needed") or line:find("performed") then
            col = C.blue
        else
            col = C.normal
        end
        rgb(col)
        love.graphics.printf(line, bx + 14, ly, bw - 28, "left")
    end
    centered("[ENTER]  Continue", by + bh - 26, C.dim, fSmall)
end

-- Rate overlay
local function drawRateOverlay()
    local bw, bh = 500, 290
    local bx = (W - bw) / 2
    local by = (H - bh) / 2
    drawPanel(bx, by, bw, bh)

    love.graphics.setFont(fMed)
    rgb(C.title)
    love.graphics.printf("TRAINER REPORT", bx, by + 14, bw, "center")

    love.graphics.setFont(fSmall)
    local ly = by + 52
    for _, line in ipairs(gp.rateLines) do
        if not (line:find("^===") or line:find("^---")) then
            local col = C.normal
            if line:find("%%") then col = C.title
            elseif line:find("Bad outlook") or line:find("not") then col = C.red
            elseif line:find("race%-ready") or line:find("Strong") then col = C.green
            end
            rgb(col)
            love.graphics.printf(line, bx + 16, ly, bw - 32, "left")
            ly = ly + 20
        end
    end

    centered("[ENTER] or [ESC]  Close", by + bh - 28, C.dim, fSmall)
end

-- Game over full screen
local function drawGameOverScreen()
    rgb({ 0.12, 0.02, 0.02 })
    love.graphics.rectangle("fill", 0, 0, W, H)

    local b = tools.getBird()

    love.graphics.setFont(fLarge)
    rgb(C.red)
    love.graphics.printf("GAME  OVER", 0, H / 2 - 100, W, "center")

    love.graphics.setFont(fMed)
    rgb(C.normal)
    love.graphics.printf(b.name .. "'s racing journey ends here.", 0, H / 2 - 20, W, "center")

    love.graphics.setFont(fSmall)
    rgb(C.dim)
    local statLine = string.format("Stamina: %d   Speed: %.1f   Run: %.1f   Swim: %.1f   Fly: %.1f",
        b.stamina, b.speed, b.running, b.swimming, b.flying)
    love.graphics.printf(statLine, 0, H / 2 + 40, W, "center")
    love.graphics.printf("[ENTER]  Return to Main Menu", 0, H / 2 + 100, W, "center")
end

-- Champion full screen
local function drawChampionScreen()
    rgb({ 0.08, 0.08, 0.02 })
    love.graphics.rectangle("fill", 0, 0, W, H)

    local b = tools.getBird()

    love.graphics.setFont(fLarge)
    rgb(C.title)
    love.graphics.printf("CHAMPION!", 0, H / 2 - 110, W, "center")

    love.graphics.setFont(fMed)
    rgb(C.green)
    love.graphics.printf(b.name, 0, H / 2 - 30, W, "center")

    love.graphics.setFont(fSmall)
    rgb(C.normal)
    love.graphics.printf("FeatherRace Champion  —  All 3 races conquered!", 0, H / 2 + 30, W, "center")
    rgb(C.dim)
    love.graphics.printf("[ENTER]  Return to Main Menu", 0, H / 2 + 90, W, "center")
end

-- Action runner
local function runAction(fn)
    if tools.isGameOver() then
        gp.sub = "gameover"
        return
    end

    fn()

    local raceReady = track.advanceDay()

    if raceReady then
        local prelen = #gameLog
        track.runRaceDay(tools.getBird())

        local logStr = ""
        for i = prelen + 1, #gameLog do
            logStr = logStr .. gameLog[i]:upper() .. " "
        end

        if logStr:find("CHAMPION") then
            gp.result = "champion"
        elseif logStr:find("GAME OVER") or logStr:find("LAST PLACE") then
            gp.result = "lose"
        else
            gp.result = "win"
        end
        gp.sub = "result"
    else
        if tools.isGameOver() then
            gp.sub = "gameover"
        end
    end
end

-- LÖVE callbacks
function love.load()
    love.window.setMode(W, H, { resizable = false })
    love.window.setTitle("FeatherRace")
    love.graphics.setBackgroundColor(C.bg)

    fLarge = love.graphics.newFont(52)
    fMed   = love.graphics.newFont(22)
    fSmall = love.graphics.newFont(13)

    buildMenu()
end

function love.update(dt)
end

function love.keypressed(key)
    if state == "menu" then
        if key == "up" then
            menu.sel = math.max(1, menu.sel - 1)
        elseif key == "down" then
            menu.sel = math.min(#menu.items, menu.sel + 1)
        elseif key == "return" or key == "kpenter" then
            local id = menu.items[menu.sel].id
            if id == "continue" then
                if doLoad() then
                    gameLog = {}
                    gp.sub  = "main"
                    state   = "gameplay"
                end
            elseif id == "newgame" then
                nameText = ""
                state    = "nameentry"
            elseif id == "deletesave" then
                os.remove("savegame.json")
                buildMenu()
            end
        end

    elseif state == "nameentry" then
        if key == "return" or key == "kpenter" then
            if #nameText > 0 then
                tools.createBird(nameText)
                track.startRaceCycle()
                gameLog = {}
                gp.sub  = "main"
                state   = "gameplay"
            end
        elseif key == "backspace" then
            nameText = nameText:sub(1, -2)
        elseif key == "escape" then
            state = "menu"
        end

    elseif state == "gameplay" then
        local sub = gp.sub

        if sub == "main" then
            if     key == "f" then runAction(tools.feed)
            elseif key == "p" then runAction(tools.play)
            elseif key == "r" then runAction(tools.rest)
            elseif key == "t" then gp.sub = "training"; gp.trainSel = 1
            elseif key == "s" then gp.sub = "shop";     gp.shopSel  = 1
            elseif key == "i" then tools.showStats(); track.showRaceStatus()
            elseif key == "q" then doSave(); love.event.quit()
            elseif key == "v" then
                local prelen = #gameLog
                trainer.rateDuck(tools.getBird(), track.getRaceData())
                gp.rateLines = {}
                for i = prelen + 1, #gameLog do
                    table.insert(gp.rateLines, gameLog[i])
                end
                gp.sub = "rate"
            end

        elseif sub == "training" then
            if key == "up" then
                gp.trainSel = math.max(1, gp.trainSel - 1)
            elseif key == "down" then
                gp.trainSel = math.min(#trainOpts, gp.trainSel + 1)
            elseif key == "return" or key == "kpenter" then
                local opt = trainOpts[gp.trainSel]
                if opt.fn then
                    runAction(opt.fn)
                    if gp.sub == "training" then gp.sub = "main" end
                else
                    gp.sub = "main"
                end
            elseif key == "escape" then
                gp.sub = "main"
            end

        elseif sub == "shop" then
            if key == "up" then
                gp.shopSel = math.max(1, gp.shopSel - 1)
            elseif key == "down" then
                gp.shopSel = math.min(#shopOpts, gp.shopSel + 1)
            elseif key == "return" or key == "kpenter" then
                local item = shopOpts[gp.shopSel]
                if item.id == 0 then
                    gp.sub = "main"
                else
                    shopMod.handlePurchase(item.id)
                end
            elseif key == "escape" then
                gp.sub = "main"
            end

        elseif sub == "rate" then
            if key == "return" or key == "kpenter" or key == "escape" or key == "v" then
                gp.sub = "main"
            end

        elseif sub == "result" then
            if key == "return" or key == "kpenter" then
                if gp.result == "champion" then
                    gp.sub = "champion"
                elseif gp.result == "lose" then
                    gp.sub = "gameover"
                else
                    gp.sub = "main"
                end
            end

        elseif sub == "gameover" or sub == "champion" then
            if key == "return" or key == "kpenter" then
                os.remove("savegame.json")
                buildMenu()
                state = "menu"
            end
        end
    end
end

function love.textinput(t)
    if state == "nameentry" and #nameText < 18 then
        nameText = nameText .. t
    end
end

function love.draw()
    if state == "menu" then
        drawMenu()
    elseif state == "nameentry" then
        drawNameEntry()
    elseif state == "gameplay" then
        local sub = gp.sub
        if sub == "gameover" then
            drawGameOverScreen()
        elseif sub == "champion" then
            drawChampionScreen()
        else
            drawGameplayBase()
            if sub == "training" then drawTrainingOverlay() end
            if sub == "shop"     then drawShopOverlay()     end
            if sub == "result"   then drawResultOverlay()   end
            if sub == "rate"     then drawRateOverlay()     end
        end
    end
end
