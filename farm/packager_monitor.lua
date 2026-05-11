local TIPO     = "create:packager"
local INTERVALO = 2
local LOG_MAX   = 30

local pkgSide, pkg
for _, n in pairs(peripheral.getNames()) do
    for _, t in pairs({peripheral.getType(n)}) do
        if t == TIPO then pkg = peripheral.wrap(n); pkgSide = n; break end
    end
    if pkg then break end
end

if not pkg then
    printError("Packager nao encontrado! Tipo: " .. TIPO)
    print("Perifericos:")
    for _, n in pairs(peripheral.getNames()) do
        print("  " .. n .. " -> " .. table.concat({peripheral.getType(n)}, ", "))
    end
    return
end

local mon  = peripheral.find("monitor")
local tela = mon or term
if mon then mon.setTextScale(0.5); mon.setBackgroundColor(colors.black) end

local log      = {}
local ultimo   = {}  -- ultimo snapshot do inventario
local totalPkg = 0

local function ts() return textutils.formatTime(os.time(), true) end

local function nomeItem(n, disp)
    if disp and #disp > 0 then return disp end
    if not n then return "???" end
    return (n:gsub("^[%w_%-]+:",""):gsub("_"," ")):gsub("^%l", string.upper)
end

local function addLog(txt, cor)
    table.insert(log, 1, {txt=txt, cor=cor or colors.white})
    while #log > LOG_MAX do table.remove(log) end
end

local function lerInv()
    local ok, lista = pcall(pkg.list)
    if not ok or not lista then return {} end
    local itens = {}
    for slot, item in pairs(lista) do
        if item and item.name then
            local det; pcall(function() det = pkg.getItemDetail(slot) end)
            local nome = nomeItem(item.name, det and det.displayName)
            local found = false
            for _, ex in ipairs(itens) do
                if ex.raw == item.name then ex.count = ex.count + item.count; found = true; break end
            end
            if not found then table.insert(itens, {raw=item.name, name=nome, count=item.count or 1}) end
        end
    end
    table.sort(itens, function(a,b) return a.count > b.count end)
    return itens
end

local function diffInv(old, new)
    local chegou, saiu = {}, {}
    local oldMap = {}
    for _, it in ipairs(old) do oldMap[it.raw] = it.count end
    local newMap = {}
    for _, it in ipairs(new) do newMap[it.raw] = it.count end

    for _, it in ipairs(new) do
        if not oldMap[it.raw] then
            table.insert(chegou, it)
        elseif it.count > oldMap[it.raw] then
            table.insert(chegou, {raw=it.raw, name=it.name, count=it.count - oldMap[it.raw]})
        end
    end
    for _, it in ipairs(old) do
        if not newMap[it.raw] then
            table.insert(saiu, it)
        elseif it.count > newMap[it.raw] then
            table.insert(saiu, {raw=it.raw, name=it.name, count=it.count - newMap[it.raw]})
        end
    end
    return chegou, saiu
end

local function desenhar(itens)
    tela.clear()
    local w, h = tela.getSize()

    tela.setCursorPos(1,1); tela.setBackgroundColor(colors.blue)
    tela.setTextColor(colors.white); tela.clearLine()
    tela.write(" PACKAGER  " .. pkgSide)
    local hr = ts(); tela.setCursorPos(w-#hr,1); tela.write(hr)
    tela.setBackgroundColor(colors.black)

    -- Inventario atual (metade esquerda)
    local colW = math.floor(w/2) - 1
    tela.setCursorPos(1,2); tela.setTextColor(colors.cyan)
    tela.write(string.format(" Dentro agora: %d", #itens))
    tela.setCursorPos(1,3); tela.setTextColor(colors.gray)
    tela.write(string.rep("-", colW))

    if #itens == 0 then
        tela.setCursorPos(1,4); tela.setTextColor(colors.gray); tela.write(" (vazio)")
    else
        for i, it in ipairs(itens) do
            local y = 3 + i; if y >= h-1 then break end
            tela.setCursorPos(1, y); tela.setTextColor(colors.white)
            local nm = it.name; if #nm > colW-6 then nm = nm:sub(1,colW-7).."." end
            tela.write(" "..nm)
            local cs = "x"..it.count
            tela.setCursorPos(colW-#cs, y); tela.setTextColor(colors.lime); tela.write(cs)
        end
    end

    -- Separador vertical
    for y = 2, h-1 do
        tela.setCursorPos(colW+1, y); tela.setTextColor(colors.gray); tela.write("|")
    end

    -- Log (metade direita)
    local rx = colW + 2
    tela.setCursorPos(rx, 2); tela.setTextColor(colors.cyan)
    tela.write(string.format("Log (%d pacotes)", totalPkg))
    tela.setCursorPos(rx, 3); tela.setTextColor(colors.gray)
    tela.write(string.rep("-", w - rx))

    for i, entry in ipairs(log) do
        local y = 3 + i; if y >= h-1 then break end
        tela.setCursorPos(rx, y); tela.setTextColor(entry.cor)
        local txt = entry.txt
        if #txt > w - rx then txt = txt:sub(1, w-rx-1).."." end
        tela.write(txt)
    end

    tela.setCursorPos(1,h); tela.setBackgroundColor(colors.gray)
    tela.setTextColor(colors.white); tela.clearLine()
    tela.write(" Packager Monitor  [Q] Sair")
    tela.setBackgroundColor(colors.black)
end

local running = true

local function updateLoop()
    local itens = lerInv()
    ultimo = itens
    desenhar(itens)

    while running do
        sleep(INTERVALO)
        local novo = lerInv()
        local chegou, saiu = diffInv(ultimo, novo)

        for _, it in ipairs(chegou) do
            totalPkg = totalPkg + 1
            addLog("[>>] "..ts().." +"..it.count.." "..it.name, colors.lime)
        end
        for _, it in ipairs(saiu) do
            addLog("[<<] "..ts().." -"..it.count.." "..it.name, colors.cyan)
        end

        ultimo = novo
        desenhar(novo)
    end
end

local function eventLoop()
    while running do
        local ev, a, b = os.pullEvent()
        if ev == "package_created" or ev == "package_received" then
            totalPkg = totalPkg + 1
            local seta = ev == "package_created" and ">>" or "<<"
            local cor  = ev == "package_created" and colors.yellow or colors.orange
            local pacote = (type(a)=="table") and a or (type(b)=="table") and b
            local addr = ""
            if pacote then
                pcall(function()
                    if type(pacote.getAddress)=="function" then
                        addr = " -> "..(pacote.getAddress() or "?")
                    end
                end)
            end
            addLog("["..seta.."] "..ts()..addr, cor)
        end
    end
end

local function inputLoop()
    while running do
        local _, k = os.pullEvent("key")
        if k == keys.q then running = false end
    end
end

term.clear(); term.setCursorPos(1,1)
print("Packager Monitor"); print("Lado: "..pkgSide)
local ini = lerInv()
print(#ini.." item(s) no packager agora."); sleep(1)

desenhar(ini)
parallel.waitForAny(updateLoop, eventLoop, inputLoop)
tela.clear(); tela.setCursorPos(1,1); print("Monitor off.")
