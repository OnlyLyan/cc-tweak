-- ==========================================
-- FARM MONITOR CENTRAL v3
-- Config + Monitor + Wireless pro Pocket
-- ==========================================

local PROTOCOLO = "farm_monitor"
local INTERVALO = 3

-- ======= CARREGAR CONFIG =======
local function carregarConfig()
    if not fs.exists("farms.cfg") then
        printError("Arquivo farms.cfg nao encontrado!")
        printError("Crie o arquivo com as configuracoes das farms.")
        return nil
    end
    local fn, err = loadfile("farms.cfg")
    if not fn then
        printError("Erro ao ler farms.cfg: " .. err)
        return nil
    end
    return fn()
end

-- ======= ESTADO =======
local config = nil
local mon = nil
local modemSide = nil
local dadosFarms = {}
local stressData = {}
local running = true
local ultimoUpdate = 0

-- ======= UTILS =======
local function safe(func, ...)
    local ok, result = pcall(func, ...)
    if ok then return result end
    return nil
end

local function nomeItem(nome)
    nome = nome:gsub("^%w+:", "")
    nome = nome:sub(1,1):upper() .. nome:sub(2)
    nome = nome:gsub("_", " ")
    return nome
end

local function corStatus(status)
    if status == "OK" then return colors.lime
    elseif status == "WARN" then return colors.yellow
    elseif status == "ERRO" or status == "PARADO" or status == "OFFLINE" then return colors.red
    else return colors.white end
end

-- ======= DETECTAR HARDWARE =======
local function detectarHardware()
    -- Monitor
    for _, side in pairs({"top","bottom","left","right","front","back"}) do
        if peripheral.getType(side) == "monitor" then
            mon = peripheral.wrap(side)
            mon.setTextScale(0.5)
            mon.setBackgroundColor(colors.black)
            break
        end
    end
    -- Tambem busca por nome na rede
    if not mon then
        local m = peripheral.find("monitor")
        if m then
            mon = m
            mon.setTextScale(0.5)
            mon.setBackgroundColor(colors.black)
        end
    end

    -- Wireless Modem
    for _, side in pairs({"top","bottom","left","right","front","back"}) do
        local tipos = {peripheral.getType(side)}
        for _, t in pairs(tipos) do
            if t == "modem" then
                local p = peripheral.wrap(side)
                if p and p.isWireless and p.isWireless() then
                    modemSide = side
                    rednet.open(side)
                    break
                end
            end
        end
        if modemSide then break end
    end
end

-- ======= LER DADOS DAS FARMS =======
local function lerFarm(farm)
    local dados = {
        name = farm.name,
        status = "OK",
        alertas = {},
        rpm = nil,
        rpmDir = nil,
        items = {},
        inputItems = {},
        fluido = nil,
        fluidoMax = nil,
        fluidoNome = nil,
    }

    -- Speed
    if farm.speed then
        local p = peripheral.wrap(farm.speed)
        if p then
            local val = safe(p.getSpeed)
            if val ~= nil then
                dados.rpm = math.abs(val)
                dados.rpmDir = val < 0 and "ACH" or "H"
                if dados.rpm == 0 then
                    dados.status = "PARADO"
                    table.insert(dados.alertas, "Eixo parado!")
                end
            else
                dados.status = "ERRO"
                table.insert(dados.alertas, "Erro ao ler speed")
            end
        else
            dados.status = "OFFLINE"
            table.insert(dados.alertas, "Speedometer offline")
        end
    end

    -- Output
    if farm.output then
        local p = peripheral.wrap(farm.output)
        if p then
            local items = safe(p.list)
            if items then
                dados.items = items
                -- Verificar se output ta cheio
                local size = safe(p.size)
                if size then
                    local used = 0
                    for _ in pairs(items) do used = used + 1 end
                    local pct = (used / size) * 100
                    if farm.alerts and farm.alerts.maxOutputPct and pct >= farm.alerts.maxOutputPct then
                        if dados.status == "OK" then dados.status = "WARN" end
                        table.insert(dados.alertas, "Output " .. string.format("%.0f%%", pct) .. " cheio")
                    end
                end
            end
        else
            if dados.status == "OK" then dados.status = "WARN" end
            table.insert(dados.alertas, "Output offline")
        end
    end

    -- Input
    if farm.input then
        local p = peripheral.wrap(farm.input)
        if p then
            local items = safe(p.list)
            if items then
                dados.inputItems = items
                local total = 0
                for _, item in pairs(items) do total = total + item.count end
                if farm.alerts and farm.alerts.minInput and total < farm.alerts.minInput then
                    if dados.status == "OK" then dados.status = "WARN" end
                    table.insert(dados.alertas, "Input baixo: " .. total)
                end
            end
        end
    end

    -- Fluido
    if farm.fluid then
        local p = peripheral.wrap(farm.fluid)
        if p then
            local tanks = safe(p.tanks)
            if tanks and #tanks > 0 then
                dados.fluidoNome = nomeItem(tanks[1].name or "???")
                dados.fluido = tanks[1].amount or 0
                -- Tentar pegar capacidade
                local cap = 0
                for _, t in pairs(tanks) do
                    cap = cap + (t.amount or 0)
                end
                dados.fluidoMax = cap
                if farm.alerts and farm.alerts.minFluid and dados.fluido < farm.alerts.minFluid then
                    if dados.status == "OK" then dados.status = "WARN" end
                    table.insert(dados.alertas, "Fluido baixo: " .. dados.fluido .. "mB")
                end
            end
        end
    end

    return dados
end

local function lerStress()
    if not config.stressometer then return end
    local p = peripheral.wrap(config.stressometer)
    if p then
        stressData.stress = safe(p.getStress) or 0
        stressData.capacity = safe(p.getStressCapacity) or 0
        stressData.status = "OK"
        if stressData.capacity > 0 then
            stressData.pct = (stressData.stress / stressData.capacity) * 100
            if stressData.pct > 90 then stressData.status = "ERRO"
            elseif stressData.pct > 70 then stressData.status = "WARN" end
        else
            stressData.pct = 0
        end
    else
        stressData.status = "OFFLINE"
        stressData.stress = 0
        stressData.capacity = 0
        stressData.pct = 0
    end
end

local function coletarDados()
    dadosFarms = {}
    for _, farm in pairs(config.farms) do
        table.insert(dadosFarms, lerFarm(farm))
    end
    lerStress()
    ultimoUpdate = os.clock()
end

-- ======= BROADCAST PRO POCKET =======
local function broadcast()
    if not modemSide then return end

    local pacote = {
        type = "status",
        zone = config.zoneName,
        timestamp = os.time(),
        day = os.day(),
        stress = {
            stress = stressData.stress,
            capacity = stressData.capacity,
            pct = stressData.pct,
            status = stressData.status,
        },
        farms = {},
    }

    for _, d in pairs(dadosFarms) do
        local farmPkt = {
            name = d.name,
            status = d.status,
            rpm = d.rpm,
            alertas = d.alertas,
            items = {},
        }
        for slot, item in pairs(d.items) do
            table.insert(farmPkt.items, {
                name = nomeItem(item.name),
                count = item.count,
            })
        end
        if d.fluido then
            farmPkt.fluido = d.fluido
            farmPkt.fluidoNome = d.fluidoNome
        end
        table.insert(pacote.farms, farmPkt)
    end

    rednet.broadcast(textutils.serialise(pacote), PROTOCOLO)
end

-- ======= RESPONDER POCKET =======
local function responderPocket()
    while running do
        local sender, msg, proto = rednet.receive(PROTOCOLO, 1)
        if sender and msg then
            local pedido = textutils.unserialise(msg)
            if pedido and pedido.type == "request" then
                -- Pocket pediu dados, envia
                broadcast()
            end
        end
    end
end

-- ======= MONITOR UI =======
local function escrever(t, x, y, texto, cor)
    t.setCursorPos(x, y)
    t.setTextColor(cor or colors.white)
    t.write(texto)
end

local function centro(t, y, texto, cor)
    local w = t.getSize()
    local x = math.floor((w - #texto) / 2) + 1
    t.setCursorPos(x, y)
    t.setTextColor(cor or colors.white)
    t.write(texto)
end

local function linha(t, y, char, cor)
    local w = t.getSize()
    t.setCursorPos(1, y)
    t.setTextColor(cor or colors.gray)
    t.write(string.rep(char or "-", w))
end

local function barraPct(t, x, y, largura, pct)
    local preenchido = math.floor((pct / 100) * largura)
    local cor = colors.lime
    if pct > 90 then cor = colors.red
    elseif pct > 70 then cor = colors.yellow end

    t.setCursorPos(x, y)
    t.setBackgroundColor(colors.gray)
    t.write(string.rep(" ", largura))
    t.setCursorPos(x, y)
    t.setBackgroundColor(cor)
    if preenchido > 0 then
        t.write(string.rep(" ", math.min(preenchido, largura)))
    end
    t.setBackgroundColor(colors.black)
end

local function desenharMonitor()
    if not mon then return end
    mon.clear()
    local w, h = mon.getSize()

    -- Header
    linha(mon, 1, "=", colors.cyan)
    centro(mon, 2, "FARM MONITOR - " .. (config.zoneName or ""), colors.cyan)
    local hora = textutils.formatTime(os.time(), true)
    escrever(mon, w - #hora, 2, hora, colors.lightGray)
    linha(mon, 3, "=", colors.cyan)

    -- Contagem
    local ok, warn, err = 0, 0, 0
    for _, d in pairs(dadosFarms) do
        if d.status == "OK" then ok = ok + 1
        elseif d.status == "WARN" then warn = warn + 1
        else err = err + 1 end
    end
    local total = #dadosFarms
    local resumo = string.format("  %d OK   %d WARN   %d ERR   Total: %d", ok, warn, err, total)
    escrever(mon, 2, 4, tostring(ok), colors.lime)
    escrever(mon, 2 + #tostring(ok), 4, " OK  ", colors.lime)
    escrever(mon, 9, 4, tostring(warn), colors.yellow)
    escrever(mon, 9 + #tostring(warn), 4, " WARN  ", colors.yellow)
    escrever(mon, 18, 4, tostring(err), colors.red)
    escrever(mon, 18 + #tostring(err), 4, " ERR", colors.red)
    escrever(mon, 30, 4, "Total: " .. total, colors.lightGray)

    local y = 6

    -- Stress
    if stressData.status then
        linha(mon, y, "-")
        y = y + 1
        escrever(mon, 2, y, "STRESS TOC", colors.cyan)

        if stressData.status == "OFFLINE" then
            escrever(mon, 18, y, "[OFFLINE]", colors.red)
            y = y + 1
        else
            local sCor = corStatus(stressData.status)
            local sIcon = stressData.status == "OK" and "[ OK ]" or (stressData.status == "WARN" and "[WARN]" or "[CRIT]")
            escrever(mon, 18, y, string.format("%.0f/%.0f SU", stressData.stress, stressData.capacity), colors.white)
            escrever(mon, 40, y, sIcon, sCor)
            y = y + 1
            escrever(mon, 2, y, "Stress:", colors.lightGray)
            barraPct(mon, 11, y, 28, stressData.pct)
            escrever(mon, 41, y, string.format("%.0f%%", stressData.pct), sCor)
            y = y + 1
        end
        y = y + 1
    end

    -- Farms
    linha(mon, y, "-")
    y = y + 1
    escrever(mon, 2, y, "FARMS", colors.cyan)
    y = y + 1

    for _, d in pairs(dadosFarms) do
        if y >= h - 2 then break end

        local statusIcon, statusCor
        if d.status == "OK" then
            statusIcon = "[ OK ]"
            statusCor = colors.lime
        elseif d.status == "WARN" then
            statusIcon = "[WARN]"
            statusCor = colors.yellow
        elseif d.status == "PARADO" then
            statusIcon = "[STOP]"
            statusCor = colors.red
        else
            statusIcon = "[ERR!]"
            statusCor = colors.red
        end

        escrever(mon, 3, y, d.name, colors.white)

        if d.rpm then
            escrever(mon, 22, y, d.rpm .. " RPM", colors.lightGray)
        end

        escrever(mon, 35, y, statusIcon, statusCor)

        -- Mostrar alertas
        if #d.alertas > 0 then
            escrever(mon, 43, y, d.alertas[1], colors.orange or colors.yellow)
        end

        -- Itens de output na linha de baixo
        local itemStr = ""
        for slot, item in pairs(d.items) do
            local iName = nomeItem(item.name)
            if #itemStr > 0 then itemStr = itemStr .. ", " end
            itemStr = itemStr .. iName .. " x" .. item.count
        end
        if #itemStr > 0 then
            y = y + 1
            if y < h - 2 then
                escrever(mon, 5, y, itemStr, colors.lime)
            end
        end

        y = y + 1
    end

    -- Footer
    linha(mon, h - 1, "=", colors.cyan)
    local wireless = modemSide and "Wireless: ON" or "Wireless: OFF"
    escrever(mon, 2, h, wireless, modemSide and colors.lime or colors.red)
    escrever(mon, 25, h, "Atualiza: " .. INTERVALO .. "s", colors.gray)
end

-- ======= MENU TERMINAL =======
local function desenharMenu()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("==================================")
    print("  FARM MONITOR CENTRAL v3")
    print("  " .. (config.zoneName or ""))
    print("==================================")
    term.setTextColor(colors.white)
    print()
    print("  Farms: " .. #config.farms)
    print("  Monitor: " .. (mon and "OK" or "N/A"))
    print("  Wireless: " .. (modemSide or "N/A"))
    print()
    print("  [1] Ver status das farms")
    print("  [2] Editar farms.cfg")
    print("  [3] Recarregar config")
    print("  [4] Forcar broadcast")
    print()
    term.setTextColor(colors.red)
    print("  [Q] Sair")
    term.setTextColor(colors.gray)
    print()
    print("Monitor atualiza automaticamente")
end

local function verStatus()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== STATUS DAS FARMS ===")
    print()

    -- Stress
    term.setTextColor(colors.yellow)
    print(string.format("TOC: %.0f/%.0f SU (%.1f%%) [%s]",
        stressData.stress or 0,
        stressData.capacity or 0,
        stressData.pct or 0,
        stressData.status or "?"))
    print()

    for _, d in pairs(dadosFarms) do
        term.setTextColor(corStatus(d.status))
        local rpmStr = d.rpm and (d.rpm .. " RPM") or "N/A"
        print(string.format("[%s] %s - %s", d.status, d.name, rpmStr))
        if #d.alertas > 0 then
            term.setTextColor(colors.orange or colors.yellow)
            for _, a in pairs(d.alertas) do
                print("   ! " .. a)
            end
        end
        -- Items
        for slot, item in pairs(d.items) do
            term.setTextColor(colors.lightGray)
            print("   " .. nomeItem(item.name) .. " x" .. item.count)
        end
    end

    print()
    term.setTextColor(colors.gray)
    print("Aperte qualquer tecla...")
    os.pullEvent("key")
end

local function menuLoop()
    while running do
        desenharMenu()
        local _, key = os.pullEvent("key")

        if key == keys.one then
            verStatus()
        elseif key == keys.two then
            shell.run("edit", "farms.cfg")
        elseif key == keys.three then
            config = carregarConfig()
            if config then
                coletarDados()
                term.setTextColor(colors.lime)
                print("Config recarregada! " .. #config.farms .. " farms")
                sleep(1)
            end
        elseif key == keys.four then
            coletarDados()
            broadcast()
            term.setTextColor(colors.lime)
            print("Broadcast enviado!")
            sleep(1)
        elseif key == keys.q then
            running = false
        end
    end
end

-- ======= LOOPS =======
local function monitorLoop()
    while running do
        coletarDados()
        desenharMonitor()
        broadcast()
        sleep(INTERVALO)
    end
end

-- ======= INICIO =======
term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.cyan)
print("Farm Monitor Central v3")
print("Carregando config...")

config = carregarConfig()
if not config then
    term.setTextColor(colors.red)
    print("Crie o arquivo farms.cfg!")
    return
end

term.setTextColor(colors.lime)
print("Zona: " .. config.zoneName)
print("Farms: " .. #config.farms)

detectarHardware()
print("Monitor: " .. (mon and "OK" or "N/A"))
print("Wireless: " .. (modemSide or "N/A"))

print()
print("Coletando dados...")
coletarDados()

print("Iniciando em 2s...")
sleep(2)

parallel.waitForAny(monitorLoop, menuLoop, responderPocket)

if mon then
    mon.clear()
    centro(mon, 1, "Sistema desligado", colors.yellow)
end

term.clear()
term.setCursorPos(1,1)
print("Farm Monitor encerrado.")
