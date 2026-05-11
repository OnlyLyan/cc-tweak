-- ========================================
-- FARM MONITOR - Teste v1
-- Coloque como startup.lua no computador
-- ========================================

-- Perifericos
local mon = peripheral.wrap("right")
local speed = peripheral.wrap("Create_Speedometer_0")
local stress = peripheral.wrap("Create_Stressometer_0")
local drawer = peripheral.wrap("storagedrawers:standard_drawers_1_0")

-- Config do monitor
mon.setTextScale(0.5)
mon.setBackgroundColor(colors.black)

-- Cores do tema
local COR_TITULO = colors.cyan
local COR_OK = colors.lime
local COR_WARN = colors.yellow
local COR_ERR = colors.red
local COR_TEXTO = colors.white
local COR_CINZA = colors.lightGray
local COR_BARRA_BG = colors.gray
local COR_BARRA = colors.lime
local COR_BARRA_WARN = colors.yellow
local COR_BARRA_ERR = colors.red

-- Funcoes auxiliares
local function centro(mon, y, texto, cor)
    local w, _ = mon.getSize()
    local x = math.floor((w - #texto) / 2) + 1
    mon.setCursorPos(x, y)
    mon.setTextColor(cor or COR_TEXTO)
    mon.write(texto)
end

local function escrever(mon, x, y, texto, cor)
    mon.setCursorPos(x, y)
    mon.setTextColor(cor or COR_TEXTO)
    mon.write(texto)
end

local function linha(mon, y, char)
    local w, _ = mon.getSize()
    mon.setCursorPos(1, y)
    mon.setTextColor(COR_CINZA)
    mon.write(string.rep(char or "-", w))
end

local function barraPct(mon, x, y, largura, pct)
    local preenchido = math.floor((pct / 100) * largura)
    local cor = COR_BARRA
    if pct > 90 then cor = COR_BARRA_ERR
    elseif pct > 70 then cor = COR_BARRA_WARN end

    mon.setCursorPos(x, y)
    mon.setBackgroundColor(COR_BARRA_BG)
    mon.write(string.rep(" ", largura))

    mon.setCursorPos(x, y)
    mon.setBackgroundColor(cor)
    mon.write(string.rep(" ", math.min(preenchido, largura)))

    mon.setBackgroundColor(colors.black)
end

local function statusIcon(valor, limiteWarn, limiteErr)
    if valor >= limiteErr then return "[CRIT]", COR_ERR
    elseif valor >= limiteWarn then return "[WARN]", COR_WARN
    else return "[ OK ]", COR_OK end
end

-- Loop principal
while true do
    mon.clear()
    local w, h = mon.getSize()

    -- === HEADER ===
    linha(mon, 1, "=")
    centro(mon, 2, "FARM MONITOR SYSTEM", COR_TITULO)
    local hora = textutils.formatTime(os.time(), true)
    escrever(mon, w - #hora, 2, hora, COR_CINZA)
    linha(mon, 3, "=")

    -- === VELOCIDADE ===
    local rpm = speed.getSpeed()
    local rpmAbs = math.abs(rpm)
    local rpmIcon, rpmCor
    if rpmAbs == 0 then
        rpmIcon = "[PARADO]"
        rpmCor = COR_ERR
    else
        rpmIcon = "[ OK ]"
        rpmCor = COR_OK
    end

    escrever(mon, 2, 5, "EIXO PRINCIPAL", COR_TITULO)
    escrever(mon, 2, 7, "RPM:", COR_CINZA)
    escrever(mon, 8, 7, tostring(rpmAbs), COR_TEXTO)
    escrever(mon, 15, 7, rpmIcon, rpmCor)

    if rpm < 0 then
        escrever(mon, 2, 8, "Sentido: Anti-horario", COR_CINZA)
    else
        escrever(mon, 2, 8, "Sentido: Horario", COR_CINZA)
    end

    -- === STRESS ===
    linha(mon, 10, "-")
    escrever(mon, 2, 11, "STRESS DO TOC", COR_TITULO)

    local stressAtual = stress.getStress()
    local stressCap = stress.getStressCapacity()
    local stressPct = 0
    if stressCap > 0 then
        stressPct = (stressAtual / stressCap) * 100
    end

    local stressIcon, stressCor = statusIcon(stressPct, 70, 90)

    escrever(mon, 2, 13, "Uso:", COR_CINZA)
    escrever(mon, 8, 13, string.format("%.0f / %.0f SU", stressAtual, stressCap), COR_TEXTO)
    escrever(mon, 2, 14, "Pct:", COR_CINZA)
    escrever(mon, 8, 14, string.format("%.1f%%", stressPct), COR_TEXTO)
    escrever(mon, 20, 14, stressIcon, stressCor)

    escrever(mon, 2, 16, "Stress:", COR_CINZA)
    barraPct(mon, 11, 16, 30, stressPct)
    escrever(mon, 43, 16, string.format("%.0f%%", stressPct), stressCor)

    -- === INVENTARIO ===
    linha(mon, 18, "-")
    escrever(mon, 2, 19, "INVENTARIO (Drawer)", COR_TITULO)

    local y = 21
    local items = drawer.list()
    local temItem = false
    for slot, item in pairs(items) do
        temItem = true
        local nome = item.name
        -- Remove o prefixo "minecraft:" pra ficar mais limpo
        nome = nome:gsub("^%w+:", "")
        -- Capitaliza primeira letra
        nome = nome:sub(1,1):upper() .. nome:sub(2)
        nome = nome:gsub("_", " ")

        escrever(mon, 4, y, nome, COR_TEXTO)
        escrever(mon, 25, y, "x" .. tostring(item.count), COR_OK)
        y = y + 1
    end
    if not temItem then
        escrever(mon, 4, y, "Vazio!", COR_WARN)
    end

    -- === FOOTER ===
    linha(mon, h - 1, "=")
    centro(mon, h, "Atualiza a cada 3s", COR_CINZA)

    -- Espera 3 segundos
    sleep(3)
end
