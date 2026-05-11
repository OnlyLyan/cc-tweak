-- ================================================
-- STOCK MONITOR
-- Monitora o inventario do Stock Ticker do Create
-- Mostra o que esta passando pela bandeja de requests
-- ================================================

local TICKER_NAME = "create:stock_ticker_0"
local INTERVALO   = 2
local HIST_MAX    = 5

-- ===== DETECTAR PERIFERICOS =====================

-- Tenta encontrar o ticker por tipo, fallback pelo nome direto
local tickerSide, ticker

for _, nome in pairs(peripheral.getNames()) do
    local tipos = {peripheral.getType(nome)}
    for _, t in pairs(tipos) do
        if t == "create:stock_ticker" then
            ticker     = peripheral.wrap(nome)
            tickerSide = nome
            break
        end
    end
    if ticker then break end
end

-- Fallback: tenta pelo nome fixo
if not ticker and peripheral.isPresent(TICKER_NAME) then
    ticker     = peripheral.wrap(TICKER_NAME)
    tickerSide = TICKER_NAME
end

if not ticker then
    printError("Stock Ticker nao encontrado!")
    print()
    print("Perifericos disponiveis:")
    for _, n in pairs(peripheral.getNames()) do
        local t = {peripheral.getType(n)}
        print("  " .. n .. " -> " .. table.concat(t, ", "))
    end
    return
end

local mon  = peripheral.find("monitor")
local tela = mon or term
if mon then mon.setTextScale(0.5); mon.setBackgroundColor(colors.black) end

-- ===== ESTADO ===================================

local snapshots = {}   -- lista de snapshots {time, itens[]}
local visto     = {}   -- {[nome] = {count, firstSeen, lastSeen}}

-- ===== UTILS ====================================

local function ts() return textutils.formatTime(os.time(), true) end

local function nomeItem(n, display)
    if display and #display > 0 then return display end
    if not n then return "???" end
    return (n:gsub("^[%w_%-]+:",""):gsub("_"," ")):gsub("^%l", string.upper)
end

local function formatN(n)
    if n >= 1000000 then return string.format("%.1fM", n/1e6)
    elseif n >= 1000 then return string.format("%.1fk", n/1e3)
    else return tostring(n) end
end

-- ===== LEITURA ==================================

local function lerInventario()
    local raw = {}
    local ok, lista = pcall(ticker.list)
    if not ok or not lista then return nil end

    for slot, item in pairs(lista) do
        if item and item.name then
            -- tenta pegar displayName via getItemDetail
            local det = nil
            pcall(function() det = ticker.getItemDetail(slot) end)
            local nome = nomeItem(item.name, det and det.displayName)
            -- agrega por nome
            if raw[nome] then
                raw[nome].count = raw[nome].count + (item.count or 1)
            else
                raw[nome] = {name = nome, raw = item.name, count = item.count or 1}
            end
        end
    end

    local itens = {}
    for _, v in pairs(raw) do table.insert(itens, v) end
    table.sort(itens, function(a,b) return a.count > b.count end)
    return itens
end

local function registrarSnapshot(itens)
    local snap = {time = ts(), itens = itens, n = #itens}
    table.insert(snapshots, 1, snap)
    while #snapshots > HIST_MAX do table.remove(snapshots) end

    -- Atualiza "visto"
    local agora = os.clock()
    for _, it in ipairs(itens) do
        if not visto[it.name] then
            visto[it.name] = {count=it.count, firstSeen=agora, lastSeen=agora, total=it.count}
        else
            visto[it.name].lastSeen = agora
            visto[it.name].count    = it.count
            visto[it.name].total    = (visto[it.name].total or 0) + it.count
        end
    end
end

-- ===== DESENHO ==================================

local function desenhar(itens)
    tela.clear()
    local w, h = tela.getSize()

    -- Header
    tela.setCursorPos(1,1)
    tela.setBackgroundColor(colors.blue)
    tela.setTextColor(colors.white)
    tela.clearLine()
    tela.write(" STOCK TICKER MONITOR")
    local hr = ts()
    tela.setCursorPos(w-#hr, 1); tela.write(hr)
    tela.setBackgroundColor(colors.black)

    -- Sub-header: ticker e tamanho
    local ok2, sz = pcall(ticker.size)
    local subTxt = " " .. tickerSide .. "  slots:" .. (ok2 and tostring(sz) or "?")
    tela.setCursorPos(1,2); tela.setTextColor(colors.lightGray); tela.write(subTxt)

    -- Separador
    tela.setCursorPos(1,3); tela.setTextColor(colors.gray)
    tela.write(string.rep("-", w))

    if not itens then
        tela.setCursorPos(1,5); tela.setTextColor(colors.red)
        tela.write(" Erro ao ler inventario!")
        return
    end

    if #itens == 0 then
        -- Bandeja vazia: mostra o historico do que passou
        tela.setCursorPos(1,4); tela.setTextColor(colors.yellow)
        tela.write(" Bandeja vazia agora.")
        tela.setCursorPos(1,5); tela.setTextColor(colors.gray)
        tela.write(" Historico recente:")

        local y = 7
        for _, snap in ipairs(snapshots) do
            if y >= h-1 then break end
            if snap.n > 0 then
                tela.setCursorPos(1, y)
                tela.setTextColor(colors.cyan)
                tela.write(" [" .. snap.time .. "] " .. snap.n .. " item(s):")
                y = y + 1
                for _, it in ipairs(snap.itens) do
                    if y >= h-1 then break end
                    tela.setCursorPos(3, y)
                    tela.setTextColor(colors.white)
                    local txt = it.name .. " x" .. it.count
                    if #txt > w-4 then txt = txt:sub(1,w-5).."." end
                    tela.write(txt)
                    y = y + 1
                end
            end
        end

        if #snapshots == 0 then
            tela.setCursorPos(1,7); tela.setTextColor(colors.gray)
            tela.write(" Nenhum item passou ainda.")
        end
    else
        -- Mostra o que ta na bandeja agora
        tela.setCursorPos(1,4); tela.setTextColor(colors.lime)
        tela.write(string.format(" %d item(s) na bandeja agora:", #itens))

        -- Cabecalho
        tela.setCursorPos(1,5); tela.setTextColor(colors.cyan)
        tela.write(" Item")
        tela.setCursorPos(w-10,5); tela.write("Qtd")

        tela.setCursorPos(1,6); tela.setTextColor(colors.gray)
        tela.write(string.rep(".", w))

        local y = 7
        for _, it in ipairs(itens) do
            if y >= h-1 then break end
            tela.setCursorPos(1, y)
            tela.setTextColor(colors.white)
            local maxN = w - 12
            local nome = it.name
            if #nome > maxN then nome = nome:sub(1,maxN-1).."." end
            tela.write(" " .. nome)

            local cnt = formatN(it.count)
            tela.setCursorPos(w-#cnt-1, y)
            tela.setTextColor(colors.lime)
            tela.write(cnt)
            y = y + 1
        end
    end

    -- Footer
    tela.setCursorPos(1,h)
    tela.setBackgroundColor(colors.gray)
    tela.setTextColor(colors.white)
    tela.clearLine()
    tela.write(" Atualiza: " .. INTERVALO .. "s   [Q] Sair")
    tela.setBackgroundColor(colors.black)
end

-- ===== LOOPS ====================================

local running = true

local function updateLoop()
    while running do
        local itens = lerInventario()
        if itens then registrarSnapshot(itens) end
        desenhar(itens)
        sleep(INTERVALO)
    end
end

local function inputLoop()
    while running do
        local _, key = os.pullEvent("key")
        if key == keys.q then running = false end
    end
end

-- ===== INICIO ===================================

term.clear(); term.setCursorPos(1,1)
term.setTextColor(colors.cyan); print("Stock Ticker Monitor")
term.setTextColor(colors.lightGray)
print("Ticker  : " .. tickerSide)
print("Monitor : " .. (mon and "OK" or "terminal"))
print()

-- Teste inicial
local teste = lerInventario()
if teste then
    term.setTextColor(colors.lime)
    print("OK! " .. #teste .. " item(s) na bandeja.")
else
    term.setTextColor(colors.red)
    print("Aviso: list() retornou nil. Verifique a conexao.")
end
sleep(1.2)

desenhar(teste or {})
parallel.waitForAny(updateLoop, inputLoop)
tela.clear(); tela.setCursorPos(1,1)
print("Monitor off.")
