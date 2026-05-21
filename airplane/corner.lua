-- airplane/corner.lua
-- Programa dos 4 computadores de canto.
-- Boot: detecta periféricos → carrega/cria config → 4 loops paralelos

local detect    = require("detect")
local stabilize = require("stabilize")
local comms     = require("comms")

-- ── Config ────────────────────────────────────────────────────────────────────

local CFG_FILE = "config"

local DEFAULTS = {
    base_speed   = 256,
    max_speed    = 512,
    kA           = 10,
    kP           = 5,
    kR           = 5,
    target_alt   = 80,   -- fallback se cockpit não responder
}

local function loadConfig()
    if not fs.exists(CFG_FILE) then return nil end
    local fn = loadfile(CFG_FILE)
    return fn and fn() or nil
end

local function saveConfig(cfg)
    local f = fs.open(CFG_FILE, "w")
    f.writeLine("return {")
    for k, v in pairs(cfg) do
        if type(v) == "string" then
            f.writeLine(string.format("  %s = %q,", k, v))
        elseif type(v) == "number" then
            f.writeLine(string.format("  %s = %g,", k, v))
        end
    end
    f.writeLine("}")
    f.close()
end

local function setupMenu(cfg)
    term.clear()
    term.setCursorPos(1, 1)
    print("=== AVIÃO — CONFIGURAÇÃO ===")
    print("")
    print("Qual é o seu canto?")
    print(" [1] Frente-Esquerda  (FL)")
    print(" [2] Frente-Direita   (FR)")
    print(" [3] Trás-Esquerda    (RL)")
    print(" [4] Trás-Direita     (RR)")
    print("")
    print("Pressione 1-4:")
    while true do
        local _, key = os.pullEvent("key")
        if     key == keys.one   then cfg.corner = "FL"; break
        elseif key == keys.two   then cfg.corner = "FR"; break
        elseif key == keys.three then cfg.corner = "RL"; break
        elseif key == keys.four  then cfg.corner = "RR"; break
        end
    end
    print("Configurado como: " .. cfg.corner)
    sleep(1)
    return cfg
end

-- ── Boot ──────────────────────────────────────────────────────────────────────

term.clear()
term.setCursorPos(1, 1)
print("Detectando periféricos...")

local hw, err = detect.detect()
if not hw then
    printError(err)
    print("\nPressione qualquer tecla para reiniciar.")
    os.pullEvent("key")
    os.reboot()
end

print("OK — Altitude: " .. tostring(hw.altSensor.getHeight()))
print("OK — SpeedCtrl: " .. hw.speedMethod)
print("OK — Router: " .. hw.routerName)
sleep(0.5)

local cfg = loadConfig()
if not cfg then
    cfg = {}
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
end
cfg.speed_method = hw.speedMethod  -- sempre atualiza do hardware

if not cfg.corner then
    cfg = setupMenu(cfg)
    saveConfig(cfg)
end

print("Canto: " .. cfg.corner)
sleep(0.3)

comms.open(hw.routerName)

-- ── Estado compartilhado ──────────────────────────────────────────────────────

local state = {
    target_alt = cfg.target_alt,
    enabled    = true,
    heights    = {},
    last_seen  = {},
}

-- ── Loop: enviar altura ───────────────────────────────────────────────────────

local function sendLoop()
    while true do
        local h = hw.altSensor.getHeight()
        state.heights[cfg.corner]   = h
        state.last_seen[cfg.corner] = os.clock()
        comms.broadcastStatus(cfg.corner, h)
        sleep(0.05)
    end
end

-- ── Loop: receber dados ───────────────────────────────────────────────────────

local function receiveLoop()
    while true do
        local protocol, data = comms.receive(0.1)
        if data then
            if protocol == comms.CHANNEL_STATUS then
                state.heights[data.corner]   = data.height
                state.last_seen[data.corner] = os.clock()
            elseif protocol == comms.CHANNEL_CMD then
                state.target_alt = data.target_alt
                state.enabled    = data.enabled
            end
        end
        -- Expirar cantos offline (sem mensagem há 2s)
        local now = os.clock()
        for corner, t in pairs(state.last_seen) do
            if now - t > comms.TIMEOUT_CORNER then
                state.heights[corner]   = nil
                state.last_seen[corner] = nil
            end
        end
    end
end

-- ── Loop: controle de velocidade ─────────────────────────────────────────────

local function controlLoop()
    while true do
        local rpm
        if state.enabled then
            local params = {
                base_speed = cfg.base_speed,
                max_speed  = cfg.max_speed,
                kA         = cfg.kA,
                kP         = cfg.kP,
                kR         = cfg.kR,
                target_alt = state.target_alt,
            }
            rpm = stabilize.calcSpeed(params, state.heights, cfg.corner)
        else
            rpm = cfg.base_speed
        end
        -- Chama o método detectado dinamicamente (setTargetSpeed, setRPM, etc.)
        hw.speedCtrl[cfg.speed_method](rpm)
        sleep(0.1)
    end
end

-- ── Loop: display ─────────────────────────────────────────────────────────────

local function displayLoop()
    while true do
        local h   = state.heights[cfg.corner]
        local sum, n = 0, 0
        for _, v in pairs(state.heights) do sum = sum + v; n = n + 1 end
        local avg = n > 0 and (sum / n) or 0

        term.clear()
        term.setCursorPos(1, 1)
        print(string.format("[ %s ]  Alt: %.1f  Alvo: %d",
            cfg.corner, h or 0, state.target_alt))
        print(string.format("Avg: %.1f  %s",
            avg, state.enabled and "ATIVO" or "INATIVO"))
        print(string.format("FL:%-5s FR:%-5s",
            state.heights.FL and string.format("%.1f", state.heights.FL) or "?",
            state.heights.FR and string.format("%.1f", state.heights.FR) or "?"))
        print(string.format("RL:%-5s RR:%-5s",
            state.heights.RL and string.format("%.1f", state.heights.RL) or "?",
            state.heights.RR and string.format("%.1f", state.heights.RR) or "?"))
        sleep(0.5)
    end
end

-- ── Iniciar ───────────────────────────────────────────────────────────────────

term.clear()
parallel.waitForAny(sendLoop, receiveLoop, controlLoop, displayLoop)
