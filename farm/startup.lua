-- ================================================
-- FARM MONITOR v5
-- Arraste apenas este arquivo. Auto-detecta:
--   Pocket          -> dashboard compacto via wireless
--   PC Central      -> monitor 3x3, visao completa
--   PC Zona/Farm    -> monitor pequeno, dados locais
-- ================================================

local VERSAO    = "5.0"
local PROTOCOLO = "farm_monitor"
local INTERVALO = 3          -- segundos entre atualizacoes

-- ===== DETECCAO DE AMBIENTE =====================

local function isPocket()
    local w = term.getSize()
    return pocket ~= nil or w <= 26
end

local function encontrarMonitor()
    for _, s in pairs({"top","bottom","left","right","front","back"}) do
        local tipos = {peripheral.getType(s)}
        for _, t in pairs(tipos) do
            if t == "monitor" then return peripheral.wrap(s), s end
        end
    end
    for _, nome in pairs(peripheral.getNames()) do
        local tipos = {peripheral.getType(nome)}
        for _, t in pairs(tipos) do
            if t == "monitor" then return peripheral.wrap(nome), nome end
        end
    end
    return nil, nil
end

local function encontrarWireless()
    for _, nome in pairs(peripheral.getNames()) do
        local tipos = {peripheral.getType(nome)}
        for _, t in pairs(tipos) do
            if t == "modem" then
                local p = peripheral.wrap(nome)
                if p and p.isWireless and p.isWireless() then
                    return nome
                end
            end
        end
    end
    return nil
end

-- ===== UTILITARIOS ==============================

local function safe(fn, ...)
    local ok, r = pcall(fn, ...)
    return ok and r or nil
end

local function nomeItem(n)
    if not n then return "???" end
    -- Remove prefixo de mod (ex: minecraft:, create:, storagedrawers:)
    n = n:gsub("^[%w_%-]+:", ""):gsub("_", " ")
    return n:sub(1,1):upper() .. n:sub(2)
end

local function corSt(s)
    if s == "OK"   then return colors.lime
    elseif s == "WARN" then return colors.yellow
    else return colors.red end
end

-- Escrita no terminal ou monitor
local function esc(t, x, y, txt, cor)
    t.setCursorPos(x, y)
    t.setTextColor(cor or colors.white)
    t.write(txt)
end

local function cen(t, y, txt, cor)
    local w = t.getSize()
    esc(t, math.max(1, math.floor((w - #txt) / 2) + 1), y, txt, cor)
end

local function lin(t, y, ch, cor)
    local w = t.getSize()
    t.setCursorPos(1, y)
    t.setTextColor(cor or colors.gray)
    t.write(string.rep(ch or "-", w))
end

local function bar(t, x, y, larg, pct)
    local p   = math.floor((pct / 100) * larg)
    local cor = pct > 90 and colors.red or (pct > 70 and colors.yellow or colors.lime)
    t.setCursorPos(x, y); t.setBackgroundColor(colors.gray)
    t.write(string.rep(" ", larg))
    t.setCursorPos(x, y); t.setBackgroundColor(cor)
    if p > 0 then t.write(string.rep(" ", math.min(p, larg))) end
    t.setBackgroundColor(colors.black)
end

-- ===== LEITURA DE PERIFERICOS ===================

local function lerSpeed(nome)
    if not nome then return nil, nil end
    local p = peripheral.wrap(nome)
    if not p then return nil, "OFFLINE" end
    local v = safe(p.getSpeed)
    if v == nil then return nil, "ERRO" end
    return math.abs(v), v < 0 and "Anti-hor." or "Horario"
end

local function lerStress(nome)
    if not nome then return nil end
    local p = peripheral.wrap(nome)
    if not p then return {stress=0, capacity=0, pct=0, status="OFFLINE"} end
    local s   = safe(p.getStress)         or 0
    local c   = safe(p.getStressCapacity) or 0
    local pct = c > 0 and (s / c * 100) or 0
    return {
        stress   = s,
        capacity = c,
        pct      = pct,
        status   = pct > 90 and "CRIT" or (pct > 70 and "WARN" or "OK"),
    }
end

local function lerInv(nome)
    if not nome then return {} end
    local p = peripheral.wrap(nome)
    if not p then return nil end
    return safe(p.list) or {}
end

-- ===== CONFIG AUTO ==============================

local farmControls = {}

-- Retorna true para inventarios persistentes (drawers/chests), false para transitorios (belts)
local function isDrawer(nome, tipos)
    for _, t in ipairs(tipos) do
        local tl = t:lower()
        if tl:find("belt") or tl:find("chute") or tl:find("funnel") or
           tl:find("tunnel") or tl:find("spout") then
            return false
        end
    end
    local nl = nome:lower()
    if nl:find("belt") or nl:find("chute") or nl:find("funnel") then return false end
    return true
end

local function gerarConfig()
    print("Escaneando perifericos...")
    local speeds, stresses, drawers = {}, {}, {}
    local nTransient = 0
    for _, nome in pairs(peripheral.getNames()) do
        local tipos = {peripheral.getType(nome)}
        for _, t in pairs(tipos) do
            if     t == "Create_Speedometer"  then table.insert(speeds,   nome)
            elseif t == "Create_Stressometer" then table.insert(stresses, nome)
            elseif t == "inventory" then
                if isDrawer(nome, tipos) then
                    table.insert(drawers, nome)
                else
                    nTransient = nTransient + 1
                end
            end
        end
    end

    local cfg = 'return {\n'
    cfg = cfg .. '  zoneName    = "Zona ' .. os.getComputerID() .. '",\n'
    cfg = cfg .. '  isCentral   = false,\n'
    cfg = cfg .. '  stressometer = ' .. (#stresses > 0 and '"'..stresses[1]..'"' or 'nil') .. ',\n'
    cfg = cfg .. '  farms = {\n'

    local function escreveOutputs(farmDrawers)
        if #farmDrawers == 0 then
            return '      output = nil,\n'
        end
        local s = '      output = "' .. farmDrawers[1] .. '",\n'
        if #farmDrawers > 1 then
            s = s .. '      outputs = {\n'
            for _, d in ipairs(farmDrawers) do
                s = s .. '        "' .. d .. '",\n'
            end
            s = s .. '      },\n'
        end
        return s
    end

    if #speeds > 0 then
        -- Distribui drawers em round-robin entre as farms
        for i, sp in ipairs(speeds) do
            local farmDrawers = {}
            for j = i, #drawers, #speeds do
                table.insert(farmDrawers, drawers[j])
            end
            cfg = cfg .. '    {\n'
            cfg = cfg .. '      name   = "Farm ' .. i .. '",\n'
            cfg = cfg .. '      speed  = "' .. sp .. '",\n'
            cfg = cfg .. escreveOutputs(farmDrawers)
            cfg = cfg .. '      input  = nil,\n'
            cfg = cfg .. '      alerts = { minInput=16, maxOutputPct=90 },\n'
            cfg = cfg .. '    },\n'
        end
    elseif #drawers > 0 then
        -- Sem speedometer: uma farm com todos os drawers
        cfg = cfg .. '    {\n'
        cfg = cfg .. '      name   = "Farm 1",\n'
        cfg = cfg .. '      speed  = nil,\n'
        cfg = cfg .. escreveOutputs(drawers)
        cfg = cfg .. '      input  = nil,\n'
        cfg = cfg .. '      alerts = { minInput=16, maxOutputPct=90 },\n'
        cfg = cfg .. '    },\n'
    end

    cfg = cfg .. '  },\n}'
    local f = fs.open("farms.cfg", "w"); f.write(cfg); f.close()
    print(string.format("farms.cfg gerado! %d drawer(s), %d speed(s), %d ignorados",
        #drawers, #speeds, nTransient))
end

local function salvarConfig(config)
    local cfg = 'return {\n'
    cfg = cfg .. '  zoneName     = "' .. (config.zoneName or "Zona") .. '",\n'
    cfg = cfg .. '  isCentral    = ' .. (config.isCentral and 'true' or 'false') .. ',\n'
    cfg = cfg .. '  isFonte      = ' .. (config.isFonte  and 'true' or 'false') .. ',\n'
    cfg = cfg .. '  stressometer = ' .. (config.stressometer and '"'..config.stressometer..'"' or 'nil') .. ',\n'
    cfg = cfg .. '  farms = {\n'
    for _, farm in ipairs(config.farms) do
        cfg = cfg .. '    {\n'
        cfg = cfg .. '      name   = "' .. farm.name .. '",\n'
        cfg = cfg .. '      speed  = ' .. (farm.speed  and '"'..farm.speed..'"'  or 'nil') .. ',\n'
        cfg = cfg .. '      output = ' .. (farm.output and '"'..farm.output..'"' or 'nil') .. ',\n'
        if farm.outputs and #farm.outputs > 0 then
            cfg = cfg .. '      outputs = {\n'
            for _, o in ipairs(farm.outputs) do
                cfg = cfg .. '        "' .. o .. '",\n'
            end
            cfg = cfg .. '      },\n'
        end
        cfg = cfg .. '      input  = ' .. (farm.input  and '"'..farm.input..'"'  or 'nil') .. ',\n'
        if farm.control then
            cfg = cfg .. '      control = "' .. farm.control .. '",\n'
        end
        if farm.alerts then
            cfg = cfg .. '      alerts = { minInput=' .. (farm.alerts.minInput or 16)
                      .. ', maxOutputPct=' .. (farm.alerts.maxOutputPct or 90) .. ' },\n'
        end
        cfg = cfg .. '    },\n'
    end
    cfg = cfg .. '  },\n}'
    local f = fs.open("farms.cfg", "w"); f.write(cfg); f.close()
end

local function carregarConfig()
    if not fs.exists("farms.cfg") then gerarConfig() end
    local fn, err = loadfile("farms.cfg")
    if not fn then
        printError("farms.cfg invalido: " .. tostring(err))
        print("Regenerando automaticamente...")
        sleep(1)
        gerarConfig()
        fn, err = loadfile("farms.cfg")
        if not fn then printError("Falha ao regenerar: " .. tostring(err)); return nil end
    end
    return fn()
end

local function getFarmLigada(farm)
    if not farm.control then return true end
    return not (farmControls[farm.name] or false)
end

local function toggleFarm(farm)
    if not farm.control then return false end
    farmControls[farm.name] = not (farmControls[farm.name] or false)
    redstone.setOutput(farm.control, farmControls[farm.name])
    return true
end

local function lerFarm(farm)
    local d = {
        name       = farm.name,
        status     = "OK",
        alertas    = {},
        rpm        = nil,
        rpmDir     = nil,
        items      = {},
        ligada     = getFarmLigada(farm),
        temControle = farm.control ~= nil,
    }

    if not d.ligada then
        d.status = "OFF"
        table.insert(d.alertas, "Desligada")
    end

    if farm.speed then
        local rpm, info = lerSpeed(farm.speed)
        if rpm == nil then
            d.status = info or "ERRO"
            table.insert(d.alertas, "Speed: " .. (info or "ERRO"))
        elseif rpm == 0 and d.ligada then
            d.status = "PARADO"
            table.insert(d.alertas, "Eixo parado!")
        else
            d.rpm    = rpm
            d.rpmDir = info
        end
    end

    -- outputs[] tem prioridade; fallback para output string simples
    local outputList = {}
    if farm.outputs and #farm.outputs > 0 then
        outputList = farm.outputs
    elseif farm.output then
        outputList = {farm.output}
    end

    local nOffline = 0
    for _, outNome in ipairs(outputList) do
        local raw = lerInv(outNome)
        if raw then
            for _, item in pairs(raw) do
                if item and item.name then
                    local nomeI = nomeItem(item.name)
                    local found = false
                    for _, ex in ipairs(d.items) do
                        if ex.name == nomeI then
                            ex.count = ex.count + item.count
                            found = true; break
                        end
                    end
                    if not found then
                        table.insert(d.items, {name=nomeI, count=item.count})
                    end
                end
            end
        else
            nOffline = nOffline + 1
        end
    end
    if #outputList > 0 then
        if nOffline == #outputList then
            if d.status == "OK" then d.status = "WARN" end
            table.insert(d.alertas, "Output offline")
        elseif nOffline > 0 then
            table.insert(d.alertas, nOffline .. " drawer(s) offline")
        end
    end

    if farm.input then
        local raw = lerInv(farm.input)
        if raw then
            local tot = 0
            for _, item in pairs(raw) do tot = tot + (item.count or 0) end
            if farm.alerts and farm.alerts.minInput and tot < farm.alerts.minInput then
                if d.status == "OK" then d.status = "WARN" end
                table.insert(d.alertas, "Input baixo: " .. tot)
            end
        end
    end

    return d
end

local function coletarTudo(config)
    local farms = {}
    for _, farm in pairs(config.farms) do
        table.insert(farms, lerFarm(farm))
    end
    return farms, lerStress(config.stressometer)
end

-- ===== PACOTE WIRELESS ==========================

local function criarPacote(config, farms, stress)
    local pkt = {
        type      = "status",
        zone      = config.zoneName,
        timestamp = os.time(),
        day       = os.day(),
        stress    = stress,
        farms     = {},
    }
    for _, d in pairs(farms) do
        local f = {
            name       = d.name,
            status     = d.status,
            rpm        = d.rpm,
            rpmDir     = d.rpmDir,
            alertas    = d.alertas,
            ligada     = d.ligada,
            temControle = d.temControle,
            items      = d.items,   -- ja normalizados em lerFarm
        }
        table.insert(pkt.farms, f)
    end
    return pkt
end

-- ===== SISTEMA DE BOTOES ========================

local botoes = {}

local function limparBotoes() botoes = {} end

local function addBtn(t, x, y, larg, txt, cor, corTxt, id)
    local pad = math.max(0, larg - #txt)
    local esq = math.floor(pad / 2)
    t.setCursorPos(x, y)
    t.setBackgroundColor(cor)
    t.setTextColor(corTxt or colors.white)
    t.write(string.rep(" ", esq) .. txt .. string.rep(" ", pad - esq))
    t.setBackgroundColor(colors.black)
    table.insert(botoes, {x1=x, y1=y, x2=x+larg-1, y2=y, id=id})
end

local function esperarEv()
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "mouse_click" or ev[1] == "monitor_touch" then
            for _, b in pairs(botoes) do
                if ev[3]>=b.x1 and ev[3]<=b.x2 and ev[4]>=b.y1 and ev[4]<=b.y2 then
                    return b.id
                end
            end
        elseif ev[1] == "key" then
            return ev[2]
        end
    end
end

-- ===== MODO POCKET (compacto, local ou wireless) ==

local function modoPocket(worSide)
    local config = carregarConfig()
    if worSide then rednet.open(worSide) end

    local dados, semDados, running = nil, true, true
    local tela, sel, listOffset = "resumo", 1, 0

    local function desenhar()
        term.clear(); limparBotoes()
        local w, h = term.getSize()

        -- ---- TELA: RESUMO ----
        if tela == "resumo" then
            term.setCursorPos(1,1)
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.white)
            term.clearLine()
            term.write(" FARMS")
            if worSide then
                local hr = textutils.formatTime(os.time(), true)
                term.setCursorPos(w - #hr, 1); term.write(hr)
            else
                esc(term, w-6, 1, "LOCAL", colors.yellow)
            end
            term.setBackgroundColor(colors.black)

            if semDados then
                term.setCursorPos(1,4); term.setTextColor(colors.yellow)
                if worSide then
                    print(" Aguardando central..."); print(" Central deve estar ativo")
                else
                    print(" Sem config local."); print(" Crie farms.cfg.")
                end
            else
                esc(term, 1, 3, " " .. (dados.zone or "?"), colors.cyan)

                local st = type(dados.stress) == "table" and dados.stress or nil
                if st and st.status and st.status ~= "OFFLINE" then
                    term.setCursorPos(1,5); term.setTextColor(colors.lightGray); term.write(" TOC:")
                    term.setTextColor(corSt(st.status))
                    term.write(string.format(" %.0f%%", st.pct or 0))
                    term.setTextColor(colors.lightGray)
                    term.write(string.format(" %.0fSU", st.stress or 0))
                end

                local ok,wa,er = 0,0,0
                local fl = dados.farms or {}
                for _,f in pairs(fl) do
                    if f.status=="OK" then ok=ok+1 elseif f.status=="WARN" then wa=wa+1 else er=er+1 end
                end
                term.setCursorPos(1,7)
                term.setTextColor(colors.lime);   term.write(" "..ok.."OK ")
                term.setTextColor(colors.yellow); term.write(wa.."W ")
                term.setTextColor(colors.red);    term.write(er.."E")

                esc(term, 1, 9, " -- Alertas --", colors.cyan)
                local y, tem = 10, false
                for _,f in pairs(fl) do
                    if f.status ~= "OK" and y < h-1 then
                        tem = true
                        term.setCursorPos(1,y); term.setTextColor(corSt(f.status))
                        local txt = " "..f.name
                        if f.alertas and #f.alertas > 0 then txt = txt..": "..f.alertas[1] end
                        term.write(txt:sub(1,w)); y=y+1
                    end
                end
                if not tem then esc(term,1,10," Tudo OK!",colors.lime) end
            end

            term.setCursorPos(1,h); term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white); term.clearLine(); term.write("[L]Lista [Q]Sair")
            term.setBackgroundColor(colors.black)

        -- ---- TELA: LISTA (rolavel) ----
        elseif tela == "lista" then
            term.setCursorPos(1,1); term.setBackgroundColor(colors.green)
            term.setTextColor(colors.white); term.clearLine(); term.write(" FARMS")
            term.setBackgroundColor(colors.black)

            local fl = (dados and dados.farms) or {}
            local visivel = h - 4

            if #fl == 0 then
                esc(term,1,4," Sem dados",colors.yellow)
            else
                local y = 3
                for i = listOffset+1, math.min(#fl, listOffset+visivel) do
                    local f = fl[i]
                    if y >= h-1 then break end
                    term.setCursorPos(1,y)
                    if i == sel then
                        term.setBackgroundColor(colors.blue); term.clearLine()
                        term.write(" > ")
                    else
                        term.setBackgroundColor(colors.black); term.write("   ")
                    end
                    term.setTextColor(corSt(f.status))
                    term.write(f.status=="OK" and "*" or (f.status=="WARN" and "!" or "X"))
                    term.setTextColor(colors.white); term.write(" "..f.name)
                    if f.rpm then
                        local rs = f.rpm.."RPM"
                        esc(term, w-#rs+1, y, rs, colors.lightGray)
                    end
                    term.setBackgroundColor(colors.black); y=y+1
                end
            end

            term.setCursorPos(1,h); term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white); term.clearLine()
            local fl2 = (dados and dados.farms) or {}
            local footerTxt = "[^v][Ent]Ver [B]Volta"
            if #fl2 > h-4 then footerTxt = footerTxt..string.format(" %d/%d",sel,#fl2) end
            term.write(footerTxt)
            term.setBackgroundColor(colors.black)

        -- ---- TELA: DETALHE ----
        elseif tela == "detalhe" then
            local fl = (dados and dados.farms) or {}
            if fl[sel] then
                local f = fl[sel]
                term.setCursorPos(1,1); term.setBackgroundColor(corSt(f.status))
                term.setTextColor(colors.white); term.clearLine(); term.write(" "..f.name)
                term.setBackgroundColor(colors.black)

                esc(term,1,3," Status: ",colors.lightGray)
                esc(term,10,3,f.status,corSt(f.status))

                esc(term,1,4," RPM:    ",colors.lightGray)
                local rpmTxt = tostring(f.rpm or "N/A")
                esc(term,10,4,rpmTxt,(f.rpm and f.rpm>0) and colors.white or colors.red)
                if f.rpmDir then esc(term,10+#rpmTxt+1,4,f.rpmDir,colors.lightGray) end

                local y = 6
                if f.items and #f.items > 0 then
                    esc(term,1,y," -- Itens --",colors.cyan); y=y+1
                    for _,item in pairs(f.items) do
                        if y >= h-3 then break end
                        local cs = "x"..item.count
                        esc(term,1,y,"  "..item.name,colors.white)
                        esc(term,w-#cs,y,cs,colors.lime); y=y+1
                    end
                end
                if f.alertas and #f.alertas > 0 then
                    y=y+1
                    if y < h-1 then esc(term,1,y," ! "..f.alertas[1],colors.yellow) end
                end
            end

            term.setCursorPos(1,h); term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white); term.clearLine(); term.write("[B]Voltar")
            term.setBackgroundColor(colors.black)
        end
    end

    -- recvLoop: so atualiza dados, sem redesenhar
    local function recvLoop()
        while running do
            if worSide then
                rednet.broadcast(textutils.serialise({type="request"}), PROTOCOLO)
                local s,m = rednet.receive(PROTOCOLO, 5)
                if s and m then
                    local d = textutils.unserialise(m)
                    if d and d.type == "status" then dados = d; semDados = false end
                end
            else
                -- Offline: coleta dados locais
                if config then
                    local farms, stress = coletarTudo(config)
                    dados = {type="status", zone=config.zoneName or "Local",
                             farms=farms, stress=stress}
                    semDados = false
                end
                sleep(INTERVALO)
            end
        end
    end

    -- drawLoop: redesenha em intervalo fixo (sem piscar)
    local function drawLoop()
        while running do
            desenhar()
            sleep(1)
        end
    end

    local function inputLoop()
        while running do
            local key = esperarEv()
            local fl = (dados and dados.farms) or {}
            local _w, h = term.getSize()
            local visivel = h - 4

            if tela == "resumo" then
                if key==keys.l then tela="lista"; sel=1; listOffset=0; desenhar()
                elseif key==keys.q then running=false end
            elseif tela == "lista" then
                if key==keys.up then
                    sel = math.max(1, sel-1)
                    if sel < listOffset+1 then listOffset = sel-1 end
                    desenhar()
                elseif key==keys.down then
                    sel = math.min(math.max(1,#fl), sel+1)
                    if sel > listOffset+visivel then listOffset = sel-visivel end
                    desenhar()
                elseif key==keys.enter then tela="detalhe"; desenhar()
                elseif key==keys.b then tela="resumo"; desenhar()
                elseif key==keys.q then running=false end
            elseif tela == "detalhe" then
                if key==keys.b then tela="lista"; desenhar()
                elseif key==keys.q then running=false end
            end
        end
    end

    desenhar()
    parallel.waitForAny(recvLoop, drawLoop, inputLoop)
    term.clear(); term.setCursorPos(1,1); print("Pocket off.")
end

-- ===== DESENHO: MONITOR CENTRAL (compacto, paginado) =

local function desenharCentral(mon, config, farms, stress, wireless, nZonas, nMsgs, pagAtual, botoesMon, fonteData)
    if botoesMon then while #botoesMon > 0 do table.remove(botoesMon) end end
    mon.clear()
    local w, h = mon.getSize()

    -- Header (sem relogio: mostra % TOC e Fonte no lugar)
    lin(mon, 1, "=", colors.cyan)
    cen(mon, 2, " FARM MONITOR v"..VERSAO.." | "..(config.zoneName or ""), colors.cyan)

    -- Direita do header: F:XX% T:XX%  (fonte e/ou TOC)
    do
        local hr = w
        if stress and stress.status and stress.status ~= "N/A" and stress.status ~= "OFFLINE" then
            local txt = string.format("T:%.0f%%", stress.pct or 0)
            hr = hr - #txt
            esc(mon, hr, 2, txt, corSt(stress.status))
            hr = hr - 1
        elseif stress and stress.status == "OFFLINE" then
            local txt = "T:OFF"
            hr = hr - #txt
            esc(mon, hr, 2, txt, colors.red)
            hr = hr - 1
        end
        if fonteData and (fonteData.capacity or 0) > 0 then
            local fpct = fonteData.pct or ((fonteData.stress or 0) / fonteData.capacity * 100)
            local txt = string.format("F:%.0f%% ", fpct)
            hr = hr - #txt
            esc(mon, hr, 2, txt, corSt(fonteData.status or "OK"))
        end
    end

    lin(mon, 3, "=", colors.cyan)

    -- Barra de status
    local ok,wa,er = 0,0,0
    for _,d in pairs(farms) do
        if d.status=="OK" then ok=ok+1 elseif d.status=="WARN" then wa=wa+1 else er=er+1 end
    end
    local okTxt = ok.." OK"; local waTxt = wa.." WARN"; local erTxt = er.." ERRO"
    esc(mon,2,4,okTxt,colors.lime)
    esc(mon,3+#okTxt,4,waTxt,colors.yellow)
    esc(mon,4+#okTxt+#waTxt,4,erTxt,colors.red)
    local wst = (wireless and "Wi:ON" or "Wi:OFF").." Z:"..(nZonas or 0).." M:"..(nMsgs or 0)
    esc(mon, w-#wst, 4, wst, wireless and colors.lime or colors.red)

    local y = 5

    -- Cabecalho farms + paginacao
    lin(mon, y, "-", colors.gray); y=y+1

    local footerH   = 3
    local ncols     = w >= 130 and 3 or (w >= 70 and 2 or 1)
    local colW      = math.floor(w / ncols)
    local lFarm     = 3  -- linhas por farm: nome + resumo + separador
    local farmsStartY = y + 1  -- linha apos "FARMS (N)"
    local availH    = h - farmsStartY - footerH + 1
    local rowsPerCol = math.max(1, math.floor(availH / lFarm))
    local farmasPag = ncols * rowsPerCol
    local totalPags = math.max(1, math.ceil(#farms / farmasPag))
    pagAtual = math.max(1, math.min(pagAtual or 1, totalPags))

    local startI = (pagAtual-1)*farmasPag + 1
    local endI   = math.min(startI+farmasPag-1, #farms)

    local farmHdr = "FARMS ("..#farms..")"
    if totalPags > 1 then farmHdr = farmHdr.."  ["..pagAtual.."/"..totalPags.."]" end
    esc(mon, 2, y, farmHdr, colors.cyan); y=y+1
    -- y == farmsStartY

    -- Renderiza farms em ordem coluna-por-coluna (preenche col 0, depois col 1, ...)
    for i = startI, endI do
        local d = farms[i]
        local relI = i - startI
        local col  = math.floor(relI / rowsPerCol)
        local row  = relI % rowsPerCol
        local xOff = 1 + col * colW
        local yA   = farmsStartY + row * lFarm

        if yA > h - footerH then break end

        local si, sc
        if     d.status=="OK"     then si="[ OK ]"; sc=colors.lime
        elseif d.status=="WARN"   then si="[WARN]"; sc=colors.yellow
        elseif d.status=="OFF"    then si="[ OFF]"; sc=colors.gray
        elseif d.status=="PARADO" then si="[STP]";  sc=colors.red
        else                           si="[ERR]";  sc=colors.red end

        local dn = d.displayName or d.name
        local maxNome = colW - #si - 2
        if #dn > maxNome then dn = dn:sub(1, maxNome-1).."." end
        esc(mon, xOff, yA, dn, colors.white)
        esc(mon, xOff+colW-#si-1, yA, si, sc)
        yA = yA+1

        -- Linha de resumo: RPM + item principal
        if yA <= h - footerH then
            local parts = {}
            if d.rpm then table.insert(parts, d.rpm.."RPM") end
            if #d.items > 0 then
                local top = d.items[1]
                local nm  = top.name:sub(1, math.min(#top.name, 12))
                local ext = #d.items > 1 and " +"..(#d.items-1) or ""
                table.insert(parts, nm.." x"..top.count..ext)
            elseif #d.alertas > 0 then
                table.insert(parts, "! "..d.alertas[1])
            else
                table.insert(parts, "---")
            end
            local l2 = table.concat(parts, " | ")
            local maxL = colW - 3
            if #l2 > maxL then l2 = l2:sub(1, maxL-1).."." end
            local c2 = (#d.alertas > 0 and d.status ~= "OK") and colors.yellow or colors.lightGray
            esc(mon, xOff+2, yA, l2, c2)
            yA = yA+1
        end

        if yA <= h - footerH then
            esc(mon, xOff, yA, string.rep(".", colW-1), colors.gray)
        end
    end

    -- Footer
    lin(mon, h-2, "=", colors.cyan)
    if totalPags > 1 then
        local prevTxt = " [<<] "; local nextTxt = " [>>] "
        local pagTxt  = string.format("  %d / %d  ", pagAtual, totalPags)
        local fx = math.max(1, math.floor((w - #prevTxt - #pagTxt - #nextTxt)/2) + 1)
        local px = fx
        esc(mon, px, h-1, prevTxt, pagAtual>1 and colors.white or colors.gray)
        if botoesMon and pagAtual>1 then
            table.insert(botoesMon,{x1=px,y1=h-1,x2=px+#prevTxt-1,y2=h-1,id="prev"})
        end
        px=px+#prevTxt
        esc(mon, px, h-1, pagTxt, colors.cyan)
        px=px+#pagTxt
        esc(mon, px, h-1, nextTxt, pagAtual<totalPags and colors.white or colors.gray)
        if botoesMon and pagAtual<totalPags then
            table.insert(botoesMon,{x1=px,y1=h-1,x2=px+#nextTxt-1,y2=h-1,id="next"})
        end
        cen(mon, h, "Toque <<>> p/ paginar  v"..VERSAO, colors.gray)
    else
        cen(mon, h-1, "Atualiza: "..INTERVALO.."s", colors.gray)
        cen(mon, h, "v"..VERSAO, colors.gray)
    end

    return totalPags, pagAtual
end

-- ===== DESENHO: MONITOR ZONA (compacto, local) ===

-- toques: tabela opcional {y1,y2,nome} preenchida para cada farm (monitor_touch)
local function desenharZona(mon, config, farms, stress, toques)
    mon.clear()
    local w, h = mon.getSize()

    lin(mon, 1, "=", colors.cyan)
    cen(mon, 2, config.zoneName or "ZONA", colors.cyan)
    local hora = textutils.formatTime(os.time(), true)
    esc(mon, w-#hora, 2, hora, colors.lightGray)
    lin(mon, 3, "=", colors.cyan)

    local y = 4

    -- Stress/TOC compacto
    if stress and stress.status and stress.status ~= "OFFLINE" then
        local sc   = corSt(stress.status)
        local stTxt = string.format("TOC: %.0f/%.0f SU  %.1f%%", stress.stress, stress.capacity, stress.pct)
        esc(mon, 2, y, stTxt, sc); y=y+1
        bar(mon, 2, y, w-2, stress.pct); y=y+2
    elseif stress and stress.status == "OFFLINE" then
        esc(mon, 2, y, "TOC: offline", colors.red); y=y+2
    end

    lin(mon, y, "-"); y=y+1

    for _, d in pairs(farms) do
        if y >= h then break end
        local yFarm = y   -- marca inicio da linha desta farm para o toque

        -- Badge de status (farms com controle mostram ON/OFF tocavel)
        local si, sc
        if d.temControle then
            si = d.ligada and "[ ON ]" or "[OFF]"
            sc = d.ligada and colors.lime or colors.red
        elseif d.status=="OK"     then si="[ OK ]"; sc=colors.lime
        elseif d.status=="WARN"   then si="[ !  ]"; sc=colors.yellow
        elseif d.status=="PARADO" then si="[STP ]"; sc=colors.red
        else                           si="[ERR ]"; sc=colors.red end

        esc(mon, 2, y, d.name, colors.white)
        -- Badge com fundo colorido para farms controlaveis
        if d.temControle then
            mon.setCursorPos(w-#si-1, y)
            mon.setBackgroundColor(d.ligada and colors.green or colors.red)
            mon.setTextColor(colors.white); mon.write(si)
            mon.setBackgroundColor(colors.black)
        else
            esc(mon, w-#si-1, y, si, sc)
        end
        y=y+1

        if d.rpm and y < h then
            local dir = d.rpmDir and " ("..d.rpmDir..")" or ""
            esc(mon, 4, y, "RPM: "..d.rpm..dir, colors.lightGray); y=y+1
        end

        local maxI = 4
        for i=1, math.min(#d.items, maxI) do
            if y >= h then break end
            local item   = d.items[i]
            local cntStr = "x"..item.count
            local maxN   = w - #cntStr - 6
            local nTxt   = item.name
            if #nTxt > maxN then nTxt=nTxt:sub(1,maxN) end
            esc(mon, 4, y, nTxt, colors.white)
            esc(mon, w-#cntStr-1, y, cntStr, colors.lime); y=y+1
        end
        if #d.items > maxI and y < h then
            esc(mon, 4, y, "+"..( #d.items-maxI).." itens", colors.gray); y=y+1
        end

        if #d.alertas > 0 and y < h then
            esc(mon, 4, y, "! "..d.alertas[1], colors.yellow); y=y+1
        end

        -- Registra area tocavel desta farm
        if toques then
            table.insert(toques, {y1=yFarm, y2=y-1, nome=d.name})
        end

        if y < h then lin(mon, y, "-"); y=y+1 end
    end

    if h-y >= 1 then
        local hint = toques and "Toque na farm p/ toggle" or ("v"..VERSAO)
        esc(mon, 2, h, hint, colors.gray)
    end
end

-- ===== MENU TERMINAL (modo Central) =============

local function menuTerminal(config, getGlobalData, onReload)
    local running = true
    while running do
        limparBotoes()
        term.clear(); term.setCursorPos(1,1)
        term.setTextColor(colors.cyan)
        print("=== Farm Monitor v"..VERSAO.." ===")
        print(config and (config.zoneName or "") or "Sem config")
        term.setTextColor(colors.white); print()
        local w,_ = term.getSize()
        local bw = w-4; local y = 5
        addBtn(term,3,y,bw,"[1] Ver status",         colors.blue,  colors.white,"status"); y=y+2
        addBtn(term,3,y,bw,"[2] Editar farms.cfg",   colors.gray,  colors.white,"editar"); y=y+2
        addBtn(term,3,y,bw,"[3] Regenerar auto-cfg", colors.yellow,colors.black,"regen");  y=y+2
        addBtn(term,3,y,bw,"[4] Recarregar config",  colors.green, colors.white,"reload"); y=y+2
        addBtn(term,3,y,bw,"[Q] SAIR",               colors.red,   colors.white,"sair")
        local _,th = term.getSize()
        esc(term, 1, th, "Clique ou use as teclas 1-4, Q", colors.gray)

        local acao = esperarEv()

        if acao == "status" or acao == keys.one then
            term.clear(); term.setCursorPos(1,1)
            local farms, stress = getGlobalData()
            term.setTextColor(colors.cyan); print("=== STATUS ==="); print()
            if stress and stress.status and stress.status ~= "N/A" then
                term.setTextColor(colors.yellow)
                print(string.format("TOC: %.0f/%.0f SU (%.1f%%) [%s]",
                    stress.stress, stress.capacity, stress.pct, stress.status))
                print()
            end
            for _,d in pairs(farms) do
                term.setTextColor(corSt(d.status))
                print(string.format("[%s] %s | RPM: %s",
                    d.status, d.displayName or d.name, d.rpm or "N/A"))
                for _,a in pairs(d.alertas) do
                    term.setTextColor(colors.yellow); print("   ! "..a)
                end
                for _,item in pairs(d.items) do
                    term.setTextColor(colors.lightGray)
                    print("   "..item.name.." x"..item.count)
                end
            end
            print(); term.setTextColor(colors.gray); print("Qualquer tecla...")
            os.pullEvent("key")

        elseif acao == "editar" or acao == keys.two then
            shell.run("edit", "farms.cfg")
            if onReload then config = onReload() end

        elseif acao == "regen" or acao == keys.three then
            gerarConfig()
            if onReload then config = onReload() end

        elseif acao == "reload" or acao == keys.four then
            if onReload then config = onReload() end
            term.setTextColor(colors.lime); print("Config recarregada!"); sleep(0.8)

        elseif acao == "sair" or acao == keys.q then
            running = false
        end
    end
end

-- ===== MENU ZONA (PC de farm) ====================

local function menuZona(config, worSide, getLocalData, onReload)
    local running = true

    local function desenhar()
        term.clear(); limparBotoes()
        local w, h = term.getSize()
        local farms, stress = getLocalData()
        local farm     = farms and farms[1]
        local nomeFarm = config.farms and config.farms[1] and config.farms[1].name
                         or config.zoneName or "Farm"

        -- Header: nome da farm centralizado
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.setCursorPos(1, 1); term.clearLine()
        local hdr = nomeFarm:upper()
        term.setCursorPos(math.max(1, math.floor((w - #hdr) / 2) + 1), 1)
        term.write(hdr)
        term.setBackgroundColor(colors.black)

        local y = 3

        -- Status geral
        if farm then
            esc(term, 1, y, "Status: ", colors.lightGray)
            esc(term, 9, y, farm.status, corSt(farm.status)); y = y + 1
        end

        -- TOC / Stress
        if stress and stress.capacity and stress.capacity > 0 then
            local sc = corSt(stress.status)
            esc(term, 1, y, "TOC:   ", colors.lightGray)
            esc(term, 8, y, string.format("%.0f/%.0fSU", stress.stress, stress.capacity), colors.white)
            esc(term, w - 4, y, string.format("%3.0f%%", stress.pct), sc); y = y + 1
            bar(term, 1, y, w, stress.pct); y = y + 1
        end

        -- Velocidade
        if farm and farm.rpm then
            local dir = farm.rpmDir and " " .. farm.rpmDir or ""
            esc(term, 1, y, "Vel:   ", colors.lightGray)
            esc(term, 8, y, farm.rpm .. " RPM" .. dir, colors.cyan); y = y + 1
        end

        y = y + 1

        -- Wireless
        if worSide then
            esc(term, 1, y, "Wi: Conectado", colors.lime)
        else
            esc(term, 1, y, "Wi: Offline",   colors.orange)
        end
        y = y + 2

        lin(term, y, "-"); y = y + 1

        local bw = w - 2
        addBtn(term, 2, y, bw, "[1] Status",     colors.blue, colors.white, "status"); y = y + 2
        addBtn(term, 2, y, bw, "[2] Configurar", colors.gray, colors.white, "cfg");    y = y + 2
        addBtn(term, 2, y, bw, "[Q] Sair",       colors.red,  colors.white, "sair")
    end

    local function telaStatus()
        term.clear(); term.setCursorPos(1, 1)
        local farms, stress = getLocalData()
        local farm = farms and farms[1]

        term.setTextColor(colors.cyan); print("=== STATUS ==="); print()

        if stress and stress.capacity and stress.capacity > 0 then
            term.setTextColor(corSt(stress.status))
            print(string.format("TOC: %.0f/%.0fSU  %.0f%%  [%s]",
                stress.stress, stress.capacity, stress.pct, stress.status))
            print()
        end

        if farm then
            term.setTextColor(corSt(farm.status))
            print("[" .. farm.status .. "] " .. farm.name)
            if farm.rpm then
                term.setTextColor(colors.lightGray)
                print("  RPM: " .. farm.rpm .. (farm.rpmDir and " | " .. farm.rpmDir or ""))
            end
            if #farm.items > 0 then
                print(); term.setTextColor(colors.cyan); print("  Itens:")
                for _, item in pairs(farm.items) do
                    term.setTextColor(colors.white)
                    print("   " .. item.name .. " x" .. item.count)
                end
            end
            if #farm.alertas > 0 then
                print()
                for _, a in pairs(farm.alertas) do
                    term.setTextColor(colors.yellow); print("  ! " .. a)
                end
            end
        end

        print(); term.setTextColor(colors.gray); print("Qualquer tecla...")
        os.pullEvent("key")
    end

    local function telaConfig()
        local subRunning = true
        while subRunning do
            term.clear(); limparBotoes()
            local w = term.getSize()

            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.setCursorPos(1, 1); term.clearLine(); term.write(" CONFIGURAR")
            term.setBackgroundColor(colors.black)

            local nomeFarm = config.farms and config.farms[1] and config.farms[1].name or "?"
            esc(term, 1, 3, "Farm: " .. nomeFarm, colors.lightGray)

            local y = 5; local bw = w - 2
            addBtn(term, 2, y, bw, "[1] Editar nome",      colors.blue,   colors.white, "nome");   y = y + 2
            addBtn(term, 2, y, bw, "[2] Regenerar config", colors.yellow, colors.black, "regen");  y = y + 2
            addBtn(term, 2, y, bw, "[3] Editar farms.cfg", colors.gray,   colors.white, "editar"); y = y + 2
            addBtn(term, 2, y, bw, "[4] Recarregar",       colors.green,  colors.white, "reload"); y = y + 2
            addBtn(term, 2, y, bw, "[V] Voltar",           colors.red,    colors.white, "voltar")

            local acao = esperarEv()

            if acao == "nome" or acao == keys.one then
                term.clear(); term.setCursorPos(1, 1)
                term.setTextColor(colors.cyan); print("=== Editar Nome ==="); print()
                local atual = config.farms and config.farms[1] and config.farms[1].name or "?"
                term.setTextColor(colors.lightGray); print("Atual: " .. atual); print()
                term.setTextColor(colors.white); write("Novo nome: ")
                local novo = read()
                if novo and #novo > 0 and config.farms and config.farms[1] then
                    local antigo = config.farms[1].name
                    if farmControls[antigo] ~= nil then
                        farmControls[novo] = farmControls[antigo]
                        farmControls[antigo] = nil
                    end
                    config.farms[1].name = novo
                    salvarConfig(config)
                    term.setTextColor(colors.lime); print('Salvo: "' .. novo .. '"')
                else
                    term.setTextColor(colors.gray); print("Cancelado.")
                end
                sleep(1.2)

            elseif acao == "regen" or acao == keys.two then
                gerarConfig()
                local novo = onReload(); if novo then config = novo end
                sleep(1)

            elseif acao == "editar" or acao == keys.three then
                shell.run("edit", "farms.cfg")
                local novo = onReload(); if novo then config = novo end

            elseif acao == "reload" or acao == keys.four then
                local novo = onReload(); if novo then config = novo end
                term.setTextColor(colors.lime); print("Recarregado!"); sleep(0.8)

            elseif acao == "voltar" or acao == keys.v then
                subRunning = false
            end
        end
    end

    desenhar()
    while running do
        local acao = esperarEv()
        if     acao == "status" or acao == keys.one then telaStatus(); desenhar()
        elseif acao == "cfg"    or acao == keys.two then telaConfig(); desenhar()
        elseif acao == "sair"   or acao == keys.q   then running = false
        end
    end
end

-- ===== MODO CENTRAL (PC principal, monitor 3x3) ==

local function modoCentral(mon, monSide, worSide)
    local config = carregarConfig()
    if not config then return end

    mon.setTextScale(0.5); mon.setBackgroundColor(colors.black)
    if worSide then rednet.open(worSide) end

    local running      = true
    local globalFarms  = {}
    local globalStress = {stress=0,capacity=0,pct=0,status="N/A"}
    local remoteCache  = {}
    local totalMsgs    = 0
    local paginaAtual  = 1
    local totalPagsAtual = 1
    local nZonasAtual  = 0
    local botoesMon    = {}
    local fonteCache   = nil   -- dados da fonte de energia remota

    local function aggLoop()
        while running do
            local lFarms, lStress = coletarTudo(config)
            local tFarms = {}
            local tStress = {
                stress   = lStress and lStress.stress   or 0,
                capacity = lStress and lStress.capacity or 0,
            }
            for _,f in pairs(lFarms) do f.displayName=f.name; table.insert(tFarms,f) end

            if worSide then
                rednet.broadcast(textutils.serialise({type="zone_request"}), PROTOCOLO)
                local tend = os.clock() + 1.5
                while os.clock() < tend do
                    local s,m = rednet.receive(PROTOCOLO, math.max(0.05, tend-os.clock()))
                    if s and m then
                        totalMsgs = totalMsgs + 1
                        local req = textutils.unserialise(m)
                        if req then
                            if (req.type == "zone_status" or req.type == "status") and req.zone then
                                remoteCache[req.zone] = {
                                    farms      = req.farms or {},
                                    stress     = req.stress,
                                    lastUpdate = os.clock(),
                                }
                            elseif req.type == "fonte_status" then
                                fonteCache = {
                                    stress     = req.stress,
                                    capacity   = req.capacity,
                                    status     = req.status,
                                    lastUpdate = os.clock(),
                                }
                            end
                        end
                    end
                end
            else
                sleep(INTERVALO)
            end

            for zName, cache in pairs(remoteCache) do
                if os.clock()-cache.lastUpdate < 10 then
                    for _,f in pairs(cache.farms) do
                        f.displayName = zName.." | "..f.name
                        table.insert(tFarms, f)
                    end
                    if cache.stress and (cache.stress.capacity or 0) > 0 then
                        tStress.stress   = (tStress.stress   or 0) + (cache.stress.stress   or 0)
                        tStress.capacity = (tStress.capacity or 0) + (cache.stress.capacity or 0)
                    end
                else
                    remoteCache[zName] = nil
                end
            end

            tStress.pct    = (tStress.capacity or 0)>0 and (tStress.stress/tStress.capacity*100) or 0
            tStress.status = (tStress.capacity or 0)==0 and "N/A" or
                             (tStress.pct>90 and "CRIT" or (tStress.pct>70 and "WARN" or "OK"))

            globalFarms  = tFarms
            globalStress = tStress

            -- Expira fonteCache apos 10s sem update
            if fonteCache and os.clock()-fonteCache.lastUpdate > 10 then fonteCache = nil end

            nZonasAtual = 0; for _ in pairs(remoteCache) do nZonasAtual = nZonasAtual + 1 end
            local np, pa = desenharCentral(mon, config, globalFarms, globalStress,
                worSide, nZonasAtual, totalMsgs, paginaAtual, botoesMon, fonteCache)
            totalPagsAtual = np; paginaAtual = pa
        end
    end

    local function respLoop()
        if not worSide then return end
        while running do
            local s,m = rednet.receive(PROTOCOLO, 1)
            if s and m then
                totalMsgs = totalMsgs + 1
                local req = textutils.unserialise(m)
                if req then
                    if req.type == "request" then
                        local pkt = {type="status",zone="GLOBAL",timestamp=os.time(),
                            day=os.day(),stress=globalStress,farms=globalFarms}
                        rednet.send(s, textutils.serialise(pkt), PROTOCOLO)
                    elseif (req.type == "zone_status" or req.type == "status") and req.zone then
                        remoteCache[req.zone] = {
                            farms      = req.farms or {},
                            stress     = req.stress,
                            lastUpdate = os.clock(),
                        }
                    elseif req.type == "fonte_status" then
                        fonteCache = {
                            stress     = req.stress,
                            capacity   = req.capacity,
                            status     = req.status,
                            lastUpdate = os.clock(),
                        }
                    elseif req.type == "toggle" and req.farmName then
                        for _,farm in pairs(config.farms) do
                            if farm.name == req.farmName then toggleFarm(farm); break end
                        end
                    end
                end
            end
        end
    end

    -- Toque no monitor: navegacao entre paginas
    local function monTouchLoop()
        while running do
            local _, _, tx, ty = os.pullEvent("monitor_touch")
            for _, b in pairs(botoesMon) do
                if tx>=b.x1 and tx<=b.x2 and ty>=b.y1 and ty<=b.y2 then
                    if b.id=="prev" and paginaAtual>1 then
                        paginaAtual = paginaAtual - 1
                    elseif b.id=="next" and paginaAtual<totalPagsAtual then
                        paginaAtual = paginaAtual + 1
                    end
                    local np, pa = desenharCentral(mon, config, globalFarms, globalStress,
                        worSide, nZonasAtual, totalMsgs, paginaAtual, botoesMon, fonteCache)
                    totalPagsAtual = np; paginaAtual = pa
                    break
                end
            end
        end
    end

    local function menuLoop()
        menuTerminal(config,
            function() return globalFarms, globalStress end,
            function() config=carregarConfig(); return config end)
        running = false
    end

    local loops = {aggLoop, menuLoop, monTouchLoop}
    if worSide then table.insert(loops, respLoop) end
    parallel.waitForAny(table.unpack(loops))
    mon.clear(); cen(mon, 2, "Sistema desligado", colors.yellow)
end

-- ===== MODO ZONA (PC de farm, monitor compacto) ==

local function modoZona(mon, monSide, worSide)
    local config = carregarConfig()
    if not config then return end

    if mon then mon.setTextScale(0.5); mon.setBackgroundColor(colors.black) end
    if worSide then rednet.open(worSide) end

    local running  = true
    local monToques = {}   -- areas tocaveis no monitor: {y1,y2,nome}

    -- Coleta, desenha e envia dados periodicamente
    local function sendLoop()
        while running do
            local farms, stress = coletarTudo(config)
            if mon then
                monToques = {}   -- rebulida a cada frame
                desenharZona(mon, config, farms, stress, monToques)
            end
            if worSide then
                local pkt = criarPacote(config, farms, stress)
                rednet.broadcast(textutils.serialise(pkt), PROTOCOLO)
            end
            sleep(INTERVALO)
        end
    end

    -- Toque no monitor -> toggle da farm correspondente
    local function monitorTouchLoop()
        if not mon then return end
        while running do
            local _, _, _, ty = os.pullEvent("monitor_touch")
            for _, area in pairs(monToques) do
                if ty >= area.y1 and ty <= area.y2 then
                    -- Procura a farm pelo nome e faz toggle
                    for _, farm in pairs(config.farms) do
                        if farm.name == area.nome then
                            if toggleFarm(farm) then
                                -- Feedback visual rapido: redesenha imediatamente
                                local farms, stress = coletarTudo(config)
                                monToques = {}
                                desenharZona(mon, config, farms, stress, monToques)
                            end
                            break
                        end
                    end
                    break
                end
            end
        end
    end

    -- Responde requisicoes da central
    local function respLoop()
        if not worSide then return end
        while running do
            local s,m = rednet.receive(PROTOCOLO, 1)
            if s and m then
                local req = textutils.unserialise(m)
                if req then
                    if req.type=="request" or req.type=="zone_request" then
                        local farms, stress = coletarTudo(config)
                        local pkt = criarPacote(config, farms, stress)
                        pkt.type = "zone_status"
                        rednet.send(s, textutils.serialise(pkt), PROTOCOLO)
                    elseif req.type=="toggle" and req.farmName then
                        for _,farm in pairs(config.farms) do
                            if farm.name==req.farmName then toggleFarm(farm); break end
                        end
                    end
                end
            end
        end
    end

    local function menuLoop()
        menuZona(
            config,
            worSide,
            function() return coletarTudo(config) end,
            function() config = carregarConfig() or config; return config end
        )
        running = false
    end

    local loops = {sendLoop, menuLoop}
    if worSide then table.insert(loops, respLoop) end
    if mon     then table.insert(loops, monitorTouchLoop) end
    parallel.waitForAny(table.unpack(loops))
    if mon then mon.clear(); cen(mon, 2, "Zona desligada", colors.yellow) end
end

-- ===== MODO FONTE (PC no gerador de energia) =====

local function modoFonte(mon, monSide, worSide)
    local config = carregarConfig()
    if not config then return end

    if mon then mon.setTextScale(0.5); mon.setBackgroundColor(colors.black) end
    if worSide then rednet.open(worSide) end

    local running = true

    local function desenharFonteMon(stress)
        if not mon then return end
        mon.clear()
        local w, h = mon.getSize()
        lin(mon, 1, "=", colors.cyan)
        cen(mon, 2, " FONTE | "..(config.zoneName or ""), colors.cyan)
        lin(mon, 3, "=", colors.cyan)

        if stress and stress.status ~= "OFFLINE" then
            local sc  = corSt(stress.status)
            local si  = stress.status=="OK" and "[ OK ]" or (stress.status=="WARN" and "[WARN]" or "[CRIT]")
            local rst = math.max(0, (stress.capacity or 0) - (stress.stress or 0))

            esc(mon, 2, 5, "Geracao:",  colors.lightGray)
            esc(mon, 12, 5, string.format("%.0f SU", stress.capacity), colors.lime)
            esc(mon, w-#si-1, 5, si, sc)

            esc(mon, 2, 6, "Consumo:",  colors.lightGray)
            esc(mon, 12, 6, string.format("%.0f SU  (%.1f%%)", stress.stress, stress.pct), sc)

            esc(mon, 2, 7, "Restante:", colors.lightGray)
            esc(mon, 12, 7, string.format("%.0f SU", rst), rst > 0 and colors.lime or colors.red)

            lin(mon, 9, "-", colors.gray)
            esc(mon, 2, 10, "Carga:", colors.lightGray)
            local bW = math.max(1, w - 14)
            bar(mon, 10, 10, bW, stress.pct)
            esc(mon, 11+bW, 10, string.format("%.0f%%", stress.pct), sc)
        else
            esc(mon, 2, 5, "Stressometer offline", colors.red)
        end

        lin(mon, h-1, "=", colors.cyan)
        cen(mon, h, "v"..VERSAO.."  Wi:"..(worSide and "ON" or "OFF"), colors.gray)
    end

    local function desenharFonteTerm(stress)
        term.clear(); term.setCursorPos(1,1)
        local _w, h = term.getSize()
        term.setTextColor(colors.cyan)
        print("=== FONTE: "..(config.zoneName or "").." ==="); print()
        if stress and stress.status ~= "OFFLINE" then
            local sc  = corSt(stress.status)
            local rst = math.max(0, (stress.capacity or 0) - (stress.stress or 0))
            term.setTextColor(colors.lightGray); term.write("Geracao: ")
            term.setTextColor(colors.lime);      print(string.format("%.0f SU", stress.capacity))
            term.setTextColor(colors.lightGray); term.write("Consumo: ")
            term.setTextColor(sc);               print(string.format("%.0f SU  %.1f%%  [%s]",
                                                     stress.stress, stress.pct, stress.status))
            term.setTextColor(colors.lightGray); term.write("Restante:")
            term.setTextColor(rst>0 and colors.lime or colors.red)
            print(string.format(" %.0f SU", rst))
        else
            term.setTextColor(colors.red); print("Stressometer nao encontrado!")
        end
        print()
        term.setTextColor(worSide and colors.lime or colors.orange)
        print("Wi: "..(worSide and "Conectado" or "Offline"))
        esc(term, 1, h, "[Q] Sair", colors.gray)
    end

    local function sendLoop()
        while running do
            local stress = lerStress(config.stressometer)
            desenharFonteMon(stress)
            desenharFonteTerm(stress)
            if worSide and stress then
                rednet.broadcast(textutils.serialise({
                    type     = "fonte_status",
                    zone     = config.zoneName or "Fonte",
                    stress   = stress.stress,
                    capacity = stress.capacity,
                    status   = stress.status,
                    pct      = stress.pct,
                }), PROTOCOLO)
            end
            sleep(INTERVALO)
        end
    end

    local function inputLoop()
        while running do
            local _, key = os.pullEvent("key")
            if key == keys.q then running = false end
        end
    end

    parallel.waitForAny(sendLoop, inputLoop)
    if mon then mon.clear() end
    term.clear(); term.setCursorPos(1,1); print("Fonte off.")
end

-- ===== DETECCAO E INICIALIZACAO =================

term.clear(); term.setCursorPos(1,1)
term.setTextColor(colors.cyan)
print("Farm Monitor v"..VERSAO)
print("Detectando ambiente...")
print()

-- Lista todos os perifericos para diagnostico
term.setTextColor(colors.lightGray)
local nomes = peripheral.getNames()
if #nomes == 0 then
    print("Perifericos: nenhum")
else
    print("Perifericos encontrados:")
    for _, n in pairs(nomes) do
        local tipos = {peripheral.getType(n)}
        print("  "..n.." -> "..table.concat(tipos, ", "))
    end
end
print()

-- Pre-carrega farms.cfg para checar isCentral / isFonte
local preConfig = nil
do
    local fn = loadfile("farms.cfg")
    if fn then pcall(function() preConfig = fn() end) end
end

local worSide = encontrarWireless()
local modo, mon, monSide

if isPocket() then
    modo = "pocket"
elseif preConfig and preConfig.isFonte then
    modo = "fonte"
    mon, monSide = encontrarMonitor()
    if mon then mon.setTextScale(0.5) end
    term.setTextColor(colors.yellow)
    print("Modo FONTE (isFonte=true em farms.cfg)")
else
    mon, monSide = encontrarMonitor()
    if mon then
        mon.setTextScale(0.5)
        local mw, mh = mon.getSize()
        if preConfig and preConfig.isCentral then
            modo = "central"
            term.setTextColor(colors.cyan)
            print(string.format("Monitor: %s  %dx%d -> CENTRAL (forcado)", monSide, mw, mh))
        else
            modo = mw >= 70 and "central" or "zona"
            term.setTextColor(colors.lightGray)
            print(string.format("Monitor: %s  %dx%d -> %s", monSide, mw, mh, modo:upper()))
            if modo == "zona" then
                term.setTextColor(colors.yellow)
                print("  Dica: adicione 'isCentral = true' em farms.cfg para forcar CENTRAL")
            end
        end
    else
        modo = "zona"
        term.setTextColor(colors.red)
        print("Monitor: nao encontrado")
    end
end

term.setTextColor(colors.lime)
print("Modo:     " .. modo:upper())
print("Wireless: " .. (worSide or "N/A (opcional)"))
print("Monitor:  " .. (monSide or "N/A"))
print()
term.setTextColor(colors.white)
print("Iniciando em 2s...")
sleep(2)

if     modo == "pocket"  then modoPocket(worSide)
elseif modo == "central" then modoCentral(mon, monSide, worSide)
elseif modo == "fonte"   then modoFonte(mon, monSide, worSide)
else                          modoZona(mon, monSide, worSide)
end
