-- airplane/cockpit.lua
-- PC central. Define altitude alvo, mostra status dos cantos.

local comms = require("comms")

-- Detectar modem wireless
local routerName
for _, name in ipairs(peripheral.getNames()) do
    local ptype = peripheral.getType(name)
    local p     = peripheral.wrap(name)
    if ptype == "modem" and p.isWireless and p.isWireless() then
        routerName = name
        break
    end
end

if not routerName then
    printError("ERRO: Wireless modem nao encontrado.")
    return
end

comms.open(routerName)

-- ── Estado ────────────────────────────────────────────────────────────────────

local state = {
    target_alt = 80,
    enabled    = true,
    heights    = {},
    last_seen  = {},
}

-- Esperar 2s para coletar alturas iniciais dos cantos
print("Conectando aos cantos (2s)...")
local deadline = os.clock() + 2
while os.clock() < deadline do
    local proto, data = comms.receive(0.1)
    if data and proto == comms.CHANNEL_STATUS then
        state.heights[data.corner] = data.height
    end
end

-- Altitude alvo inicial = média dos cantos que responderam
local sum, n = 0, 0
for _, h in pairs(state.heights) do sum = sum + h; n = n + 1 end
if n > 0 then state.target_alt = math.floor(sum / n) end

-- ── Loops ─────────────────────────────────────────────────────────────────────

local function sendLoop()
    while true do
        comms.broadcastCmd(state.target_alt, state.enabled)
        sleep(0.2)
    end
end

local function receiveLoop()
    while true do
        local proto, data = comms.receive(0.1)
        if data and proto == comms.CHANNEL_STATUS then
            state.heights[data.corner]   = data.height
            state.last_seen[data.corner] = os.clock()
        end
        local now = os.clock()
        for corner, t in pairs(state.last_seen) do
            if now - t > comms.TIMEOUT_CORNER then
                state.heights[corner]   = nil
                state.last_seen[corner] = nil
            end
        end
    end
end

local function inputLoop()
    while true do
        local _, key = os.pullEvent("key")
        if     key == keys.up       then state.target_alt = state.target_alt + 1
        elseif key == keys.down     then state.target_alt = state.target_alt - 1
        elseif key == keys.pageUp   then state.target_alt = state.target_alt + 10
        elseif key == keys.pageDown then state.target_alt = state.target_alt - 10
        elseif key == keys.e        then state.enabled = not state.enabled
        elseif key == keys.q        then return
        end
    end
end

local function drawLoop()
    while true do
        local sum2, n2 = 0, 0
        for _, h in pairs(state.heights) do sum2 = sum2 + h; n2 = n2 + 1 end
        local avg = n2 > 0 and (sum2 / n2) or 0

        local FL = state.heights.FL
        local FR = state.heights.FR
        local RL = state.heights.RL
        local RR = state.heights.RR

        local pitch, roll = 0, 0
        if FL and FR and RL and RR then
            pitch = (FL + FR) / 2 - (RL + RR) / 2
            roll  = (FL + RL) / 2 - (FR + RR) / 2
        end

        local function fmt(h)
            return h and string.format("%5.1f", h) or "  OFF"
        end

        term.clear()
        term.setCursorPos(1, 1)
        print("+================================+")
        print("|   AVIAO - CONTROLE DE VOO     |")
        print("+================================+")
        print(string.format("| Altitude alvo:  %5d blocos   |", state.target_alt))
        print(string.format("| Altitude atual: %5.1f          |", avg))
        print(string.format("| Pitch: %+5.2f    Roll: %+5.2f   |", pitch, roll))
        print("+--------------------------------+")
        print(string.format("| FL:%s   FR:%s        |", fmt(FL), fmt(FR)))
        print(string.format("| RL:%s   RR:%s        |", fmt(RL), fmt(RR)))
        print("+--------------------------------+")
        print("| [^/v] +-1   [PgUp/Dn] +-10   |")
        print("| [E] On/Off  [Q] Sair          |")
        print(string.format("| Estabilizacao: %-12s  |",
            state.enabled and "ATIVA" or "INATIVA"))
        print("+================================+")

        sleep(0.5)
    end
end

parallel.waitForAny(sendLoop, receiveLoop, inputLoop, drawLoop)
print("Cockpit encerrado.")
