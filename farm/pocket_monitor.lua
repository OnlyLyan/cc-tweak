-- ==========================================
-- POCKET MONITOR v1
-- Dashboard portatil + alertas sonoros
-- ==========================================

local PROTOCOLO = "farm_monitor"
local INTERVALO_PEDIDO = 5

-- ======= ESTADO =======
local dados = nil
local tela = "resumo"  -- resumo, lista, detalhe
local farmSelecionada = 1
local scroll = 0
local running = true
local ultimoUpdate = 0
local semDados = true

-- ======= INIT WIRELESS =======
local function initWireless()
    for _, side in pairs({"top","bottom","left","right","front","back"}) do
        if peripheral.getType(side) == "modem" then
            local p = peripheral.wrap(side)
            if p.isWireless and p.isWireless() then
                rednet.open(side)
                return side
            end
        end
    end
    -- Pocket computers tem modem embutido como "back"
    if peripheral.find("modem") then
        local m = peripheral.find("modem")
        if m.isWireless and m.isWireless() then
            -- Tenta todos os lados
            for _, side in pairs(rs.getSides()) do
                if peripheral.getType(side) == "modem" then
                    rednet.open(side)
                    return side
                end
            end
        end
    end
    return nil
end

-- ======= ALERTA SONORO =======
local function alerta(tipo)
    local speaker = peripheral.find("speaker")
    if not speaker then return end

    if tipo == "erro" then
        safe(function()
            speaker.playNote("bit", 1, 5)
            sleep(0.1)
            speaker.playNote("bit", 1, 3)
            sleep(0.1)
            speaker.playNote("bit", 1, 1)
        end)
    elseif tipo == "warn" then
        safe(function()
            speaker.playNote("bell", 0.8, 10)
            sleep(0.2)
            speaker.playNote("bell", 0.8, 10)
        end)
    end
end

local function safe(func, ...)
    local ok, result = pcall(func, ...)
    if ok then return result end
    return nil
end

-- ======= CORES =======
local function corStatus(status)
    if status == "OK" then return colors.lime
    elseif status == "WARN" then return colors.yellow
    else return colors.red end
end

-- ======= TELA: RESUMO =======
local function desenharResumo()
    term.clear()
    local w, h = term.getSize()

    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" FARM MONITOR")
    local hora = textutils.formatTime(os.time(), true)
    term.setCursorPos(w - #hora, 1)
    term.write(hora)
    term.setBackgroundColor(colors.black)

    if semDados then
        term.setCursorPos(1, 4)
        term.setTextColor(colors.yellow)
        print(" Aguardando dados...")
        print(" Certifique que o")
        print(" servidor central esta")
        print(" ligado e com wireless")
        term.setCursorPos(1, h)
        term.setTextColor(colors.gray)
        term.write("[Q]Sair")
        return
    end

    -- Zona
    term.setCursorPos(1, 3)
    term.setTextColor(colors.cyan)
    print(" " .. (dados.zone or "???"))

    -- Stress
    term.setCursorPos(1, 5)
    term.setTextColor(colors.lightGray)
    term.write(" TOC: ")
    local st = dados.stress
    if st then
        local sCor = corStatus(st.status)
        term.setTextColor(sCor)
        term.write(string.format("%.0f%%", st.pct or 0))
        term.setTextColor(colors.lightGray)
        term.write(string.format(" (%.0f SU)", st.stress or 0))
    end

    -- Contagem
    local ok, warn, err = 0, 0, 0
    if dados.farms then
        for _, f in pairs(dados.farms) do
            if f.status == "OK" then ok = ok + 1
            elseif f.status == "WARN" then warn = warn + 1
            else err = err + 1 end
        end
    end

    term.setCursorPos(1, 7)
    term.setTextColor(colors.lime)
    term.write(" " .. ok)
    term.setTextColor(colors.white)
    term.write(" OK ")
    term.setTextColor(colors.yellow)
    term.write(warn .. "")
    term.setTextColor(colors.white)
    term.write(" WARN ")
    term.setTextColor(colors.red)
    term.write(err .. "")
    term.setTextColor(colors.white)
    term.write(" ERR")

    -- Alertas recentes
    term.setCursorPos(1, 9)
    term.setTextColor(colors.cyan)
    print(" --- Alertas ---")
    local y = 10
    local temAlerta = false
    if dados.farms then
        for _, f in pairs(dados.farms) do
            if f.status ~= "OK" and f.alertas then
                temAlerta = true
                term.setCursorPos(1, y)
                term.setTextColor(corStatus(f.status))
                local txt = " " .. f.name
                if #f.alertas > 0 then
                    txt = txt .. ": " .. f.alertas[1]
                end
                term.write(txt:sub(1, w))
                y = y + 1
                if y >= h - 1 then break end
            end
        end
    end
    if not temAlerta then
        term.setCursorPos(1, y)
        term.setTextColor(colors.lime)
        term.write(" Tudo OK!")
    end

    -- Footer
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("[L]Lista [Q]Sair")
    term.setBackgroundColor(colors.black)
end

-- ======= TELA: LISTA =======
local function desenharLista()
    term.clear()
    local w, h = term.getSize()

    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" FARMS")
    term.setBackgroundColor(colors.black)

    if not dados or not dados.farms then
        term.setCursorPos(1, 3)
        term.setTextColor(colors.yellow)
        print(" Sem dados")
        return
    end

    local y = 3
    for i, f in pairs(dados.farms) do
        if y >= h - 1 then break end

        term.setCursorPos(1, y)

        -- Cursor
        if i == farmSelecionada then
            term.setBackgroundColor(colors.blue)
            term.clearLine()
            term.setTextColor(colors.white)
            term.write(" > ")
        else
            term.setTextColor(colors.white)
            term.write("   ")
        end

        -- Status icon
        term.setTextColor(corStatus(f.status))
        if f.status == "OK" then term.write("*")
        elseif f.status == "WARN" then term.write("!")
        else term.write("X") end

        term.setTextColor(colors.white)
        term.write(" " .. f.name)

        if f.rpm then
            term.setCursorPos(w - 6, y)
            term.setTextColor(colors.lightGray)
            term.write(f.rpm .. "RPM")
        end

        term.setBackgroundColor(colors.black)
        y = y + 1
    end

    -- Footer
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("[^v]Nav [Enter]Det [B]Volta")
    term.setBackgroundColor(colors.black)
end

-- ======= TELA: DETALHE =======
local function desenharDetalhe()
    term.clear()
    local w, h = term.getSize()

    if not dados or not dados.farms or not dados.farms[farmSelecionada] then
        term.setCursorPos(1, 3)
        term.setTextColor(colors.yellow)
        print(" Farm nao encontrada")
        return
    end

    local f = dados.farms[farmSelecionada]

    -- Header com nome
    term.setCursorPos(1, 1)
    term.setBackgroundColor(corStatus(f.status))
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" " .. f.name)
    term.setBackgroundColor(colors.black)

    -- Status
    term.setCursorPos(1, 3)
    term.setTextColor(colors.lightGray)
    term.write(" Status: ")
    term.setTextColor(corStatus(f.status))
    print(f.status)

    -- RPM
    term.setCursorPos(1, 4)
    term.setTextColor(colors.lightGray)
    term.write(" RPM:    ")
    if f.rpm then
        term.setTextColor(f.rpm == 0 and colors.red or colors.white)
        print(f.rpm)
    else
        term.setTextColor(colors.red)
        print("N/A")
    end

    -- Fluido
    local y = 5
    if f.fluido then
        term.setCursorPos(1, y)
        term.setTextColor(colors.lightGray)
        term.write(" Fluido: ")
        term.setTextColor(colors.cyan)
        print(f.fluidoNome or "???")
        y = y + 1
        term.setCursorPos(1, y)
        term.setTextColor(colors.lightGray)
        term.write(" Tank:   ")
        term.setTextColor(colors.white)
        print(f.fluido .. " mB")
        y = y + 1
    end

    -- Itens
    y = y + 1
    term.setCursorPos(1, y)
    term.setTextColor(colors.cyan)
    print(" --- Itens ---")
    y = y + 1

    if f.items and #f.items > 0 then
        for _, item in pairs(f.items) do
            if y >= h - 3 then break end
            term.setCursorPos(1, y)
            term.setTextColor(colors.white)
            term.write("  " .. item.name)
            term.setCursorPos(w - #tostring(item.count) - 1, y)
            term.setTextColor(colors.lime)
            print("x" .. item.count)
            y = y + 1
        end
    else
        term.setCursorPos(1, y)
        term.setTextColor(colors.gray)
        print("  Sem itens")
    end

    -- Alertas
    if f.alertas and #f.alertas > 0 then
        y = y + 1
        term.setCursorPos(1, y)
        term.setTextColor(colors.red)
        print(" --- Alertas ---")
        y = y + 1
        for _, a in pairs(f.alertas) do
            if y >= h - 1 then break end
            term.setCursorPos(1, y)
            term.setTextColor(colors.yellow)
            print("  ! " .. a)
            y = y + 1
        end
    end

    -- Footer
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("[B]Voltar [R]Atualizar")
    term.setBackgroundColor(colors.black)
end

-- ======= DESENHAR =======
local function desenhar()
    if tela == "resumo" then
        desenharResumo()
    elseif tela == "lista" then
        desenharLista()
    elseif tela == "detalhe" then
        desenharDetalhe()
    end
end

-- ======= RECEBER DADOS =======
local function receberLoop()
    while running do
        -- Pede dados
        rednet.broadcast(textutils.serialise({type = "request"}), PROTOCOLO)

        -- Espera resposta
        local sender, msg, proto = rednet.receive(PROTOCOLO, INTERVALO_PEDIDO)
        if sender and msg then
            local novoDados = textutils.unserialise(msg)
            if novoDados and novoDados.type == "status" then
                local dadosAntigos = dados
                dados = novoDados
                semDados = false
                ultimoUpdate = os.clock()

                -- Verificar alertas novos pra som
                if dados.farms then
                    local temErro = false
                    local temWarn = false
                    for _, f in pairs(dados.farms) do
                        if f.status == "PARADO" or f.status == "OFFLINE" or f.status == "ERRO" then
                            temErro = true
                        elseif f.status == "WARN" then
                            temWarn = true
                        end
                    end
                    if temErro then alerta("erro")
                    elseif temWarn then alerta("warn") end
                end

                desenhar()
            end
        else
            -- Timeout, redesenha mesmo assim
            desenhar()
        end
    end
end

-- ======= INPUT =======
local function inputLoop()
    while running do
        local event, key = os.pullEvent("key")

        if tela == "resumo" then
            if key == keys.l then
                tela = "lista"
                farmSelecionada = 1
                desenhar()
            elseif key == keys.q then
                running = false
            elseif key == keys.r then
                -- Forca atualizacao
                rednet.broadcast(textutils.serialise({type = "request"}), PROTOCOLO)
            end

        elseif tela == "lista" then
            if key == keys.up then
                farmSelecionada = math.max(1, farmSelecionada - 1)
                desenhar()
            elseif key == keys.down then
                local max = dados and dados.farms and #dados.farms or 1
                farmSelecionada = math.min(max, farmSelecionada + 1)
                desenhar()
            elseif key == keys.enter then
                tela = "detalhe"
                desenhar()
            elseif key == keys.b then
                tela = "resumo"
                desenhar()
            elseif key == keys.q then
                running = false
            end

        elseif tela == "detalhe" then
            if key == keys.b then
                tela = "lista"
                desenhar()
            elseif key == keys.r then
                rednet.broadcast(textutils.serialise({type = "request"}), PROTOCOLO)
            elseif key == keys.q then
                running = false
            end
        end
    end
end

-- ======= INICIO =======
term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.cyan)
print("Pocket Farm Monitor v1")
print()

local modemSide = initWireless()
if modemSide then
    term.setTextColor(colors.lime)
    print("Wireless: OK")
else
    term.setTextColor(colors.red)
    print("ERRO: Sem wireless!")
    print("Crafta o Pocket com")
    print("Wireless Modem!")
    return
end

print()
term.setTextColor(colors.white)
print("Conectando ao server...")
sleep(1)

desenhar()
parallel.waitForAny(receberLoop, inputLoop)

term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.yellow)
print("Pocket Monitor off.")
