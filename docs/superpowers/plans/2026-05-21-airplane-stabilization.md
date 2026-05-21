# Airplane Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sistema de estabilização automática de quadcopter em CC:Tweaked — 4 computadores de canto controlam Speed Controllers individualmente via lógica de pitch/roll/altitude, coordenados por um cockpit central via rednet.

**Architecture:** Cada canto roda o mesmo `corner.lua`, detecta periféricos automaticamente por métodos expostos, e executa três loops paralelos (enviar altitude, receber dados, controlar Speed Controller). O `cockpit.lua` no PC central coleta status e transmite altitude alvo. A matemática de estabilização é isolada em `stabilize.lua` como função pura testável.

**Tech Stack:** Lua 5.2 (CC:Tweaked), Create: Simulated (AltitudeSensor), Create Speed Controller (via CC peripheral), rednet wireless

---

## Estrutura de Arquivos

```
airplane/
  corner.lua          — programa principal dos 4 cantos
  cockpit.lua         — interface do piloto (PC central)
  detect.lua          — auto-detecção de periféricos por métodos
  stabilize.lua       — cálculo de RPM (função pura, testável)
  comms.lua           — helpers rednet (broadcast/receive)
  test_stabilize.lua  — testes in-game para stabilize.lua
```

Todos os `require()` são relativos ao mesmo diretório. No CC:Tweaked, rodar `/airplane/corner.lua` define o CWD como `/airplane/`, então `require("detect")` → `/airplane/detect.lua`.

---

## Task 1: stabilize.lua — Cálculo de velocidade (função pura)

**Files:**
- Create: `airplane/stabilize.lua`
- Create: `airplane/test_stabilize.lua`

- [ ] **Criar `airplane/stabilize.lua`**

```lua
-- airplane/stabilize.lua
-- Cálculo de RPM para estabilização. Sem efeitos colaterais.

local SIGNS = {
    FL = { pitch = -1, roll = -1 },
    FR = { pitch = -1, roll =  1 },
    RL = { pitch =  1, roll = -1 },
    RR = { pitch =  1, roll =  1 },
}

-- params: { base_speed, max_speed, kA, kP, kR, target_alt }
-- heights: { FL=n, FR=n, RL=n, RR=n }  (qualquer campo pode ser nil)
-- corner: "FL" | "FR" | "RL" | "RR"
-- Retorna: rpm (integer)
local function calcSpeed(params, heights, corner)
    local sign = SIGNS[corner]
    if not sign then return params.base_speed end

    local sum, count = 0, 0
    for _, h in pairs(heights) do
        sum   = sum + h
        count = count + 1
    end

    if count == 0 then return params.base_speed end

    local avg_all  = sum / count
    local alt_error = params.target_alt - avg_all

    -- Pitch (frente vs trás)
    local front_sum, front_n = 0, 0
    local rear_sum,  rear_n  = 0, 0
    if heights.FL then front_sum = front_sum + heights.FL; front_n = front_n + 1 end
    if heights.FR then front_sum = front_sum + heights.FR; front_n = front_n + 1 end
    if heights.RL then rear_sum  = rear_sum  + heights.RL; rear_n  = rear_n  + 1 end
    if heights.RR then rear_sum  = rear_sum  + heights.RR; rear_n  = rear_n  + 1 end

    local pitch_error = 0
    if front_n > 0 and rear_n > 0 then
        pitch_error = front_sum / front_n - rear_sum / rear_n
    end

    -- Roll (esquerda vs direita)
    local left_sum,  left_n  = 0, 0
    local right_sum, right_n = 0, 0
    if heights.FL then left_sum  = left_sum  + heights.FL; left_n  = left_n  + 1 end
    if heights.RL then left_sum  = left_sum  + heights.RL; left_n  = left_n  + 1 end
    if heights.FR then right_sum = right_sum + heights.FR; right_n = right_n + 1 end
    if heights.RR then right_sum = right_sum + heights.RR; right_n = right_n + 1 end

    local roll_error = 0
    if left_n > 0 and right_n > 0 then
        roll_error = left_sum / left_n - right_sum / right_n
    end

    local speed = params.base_speed
               + params.kA * alt_error
               + params.kP * sign.pitch * pitch_error
               + params.kR * sign.roll  * roll_error

    speed = math.max(0, math.min(params.max_speed, speed))
    return math.floor(speed)
end

return { calcSpeed = calcSpeed }
```

- [ ] **Criar `airplane/test_stabilize.lua`**

```lua
-- airplane/test_stabilize.lua
-- Rodar no CC: lua test_stabilize.lua
local stab   = require("stabilize")
local passed = 0
local failed = 0

local function test(name, got, expected, tol)
    tol = tol or 0
    if math.abs(got - expected) <= tol then
        passed = passed + 1
        print("PASS: " .. name)
    else
        failed = failed + 1
        print(string.format("FAIL: %s  got=%d  expected=%d", name, got, expected))
    end
end

local p = { base_speed=256, max_speed=512, kA=10, kP=5, kR=5, target_alt=80 }

-- Nivelado na altitude alvo → velocidade base
local flat = { FL=80, FR=80, RL=80, RR=80 }
test("flat FL", stab.calcSpeed(p, flat, "FL"), 256)
test("flat FR", stab.calcSpeed(p, flat, "FR"), 256)
test("flat RL", stab.calcSpeed(p, flat, "RL"), 256)
test("flat RR", stab.calcSpeed(p, flat, "RR"), 256)

-- 2 blocos abaixo do alvo → kA*2 = +20 em todos
local below = { FL=78, FR=78, RL=78, RR=78 }
test("below FL", stab.calcSpeed(p, below, "FL"), 276)
test("below RR", stab.calcSpeed(p, below, "RR"), 276)

-- Esquerda 2 blocos mais alta (roll_error=+2): esq. -kR*2=-10, dir. +kR*2=+10
-- avg=80 → alt_error=0
local rolled = { FL=81, FR=79, RL=81, RR=79 }
test("rolled FL", stab.calcSpeed(p, rolled, "FL"), 246)  -- 256-10
test("rolled FR", stab.calcSpeed(p, rolled, "FR"), 266)  -- 256+10
test("rolled RL", stab.calcSpeed(p, rolled, "RL"), 246)
test("rolled RR", stab.calcSpeed(p, rolled, "RR"), 266)

-- Frente 2 blocos mais alta (pitch_error=+2): frente -kP*2=-10, trás +kP*2=+10
local pitched = { FL=81, FR=81, RL=79, RR=79 }
test("pitched FL", stab.calcSpeed(p, pitched, "FL"), 246)
test("pitched FR", stab.calcSpeed(p, pitched, "FR"), 246)
test("pitched RL", stab.calcSpeed(p, pitched, "RL"), 266)
test("pitched RR", stab.calcSpeed(p, pitched, "RR"), 266)

-- Clamp mínimo: muito acima do alvo
local way_above = { FL=200, FR=200, RL=200, RR=200 }
test("clamp min FL", stab.calcSpeed(p, way_above, "FL"), 0)

-- Clamp máximo: muito abaixo do alvo
local way_below = { FL=0, FR=0, RL=0, RR=0 }
test("clamp max FL", stab.calcSpeed(p, way_below, "FL"), 512)

-- Apenas 2 cantos disponíveis (parcial)
local partial = { FL=80, FR=80 }
test("partial_2corners FL", stab.calcSpeed(p, partial, "FL"), 256)

print(string.format("\n%d passed, %d failed", passed, failed))
```

- [ ] **Rodar o teste no CC** (no PC de canto):
  ```
  cd airplane
  lua test_stabilize.lua
  ```
  Esperado: `17 passed, 0 failed`

- [ ] **Commit**
  ```
  git add airplane/stabilize.lua airplane/test_stabilize.lua
  git commit -m "feat(airplane): add stabilize.lua with unit tests"
  ```

---

## Task 2: detect.lua — Auto-detecção de periféricos

**Files:**
- Create: `airplane/detect.lua`

- [ ] **Criar `airplane/detect.lua`**

```lua
-- airplane/detect.lua
-- Varre periféricos conectados e classifica por métodos expostos.
-- Retorna: result, err
--   result = { altSensor, speedCtrl, speedMethod, router, routerName }

local function detect()
    local result = {}

    for _, name in ipairs(peripheral.getNames()) do
        local ptype = peripheral.getType(name)
        local p     = peripheral.wrap(name)
        local methods = peripheral.getMethods(name)

        -- Indexar métodos para lookup O(1)
        local mset = {}
        for _, m in ipairs(methods) do mset[m] = true end

        if mset["getHeight"] and not result.altSensor then
            -- Sensor de altitude (Create: Simulated)
            result.altSensor = p

        elseif ptype == "modem" and p.isWireless and p.isWireless() then
            -- Wireless modem / router
            result.router     = p
            result.routerName = name

        elseif not result.speedCtrl then
            -- Speed Controller: qualquer setter com "speed" ou "rpm"
            for _, m in ipairs(methods) do
                local lower = m:lower()
                if lower:find("set") and (lower:find("speed") or lower:find("rpm")) then
                    result.speedCtrl  = p
                    result.speedMethod = m
                    break
                end
            end
        end
    end

    local missing = {}
    if not result.altSensor then
        missing[#missing+1] = "Sensor de altitude  (precisa expor getHeight)"
    end
    if not result.speedCtrl then
        missing[#missing+1] = "Speed Controller    (precisa expor set*Speed ou set*RPM)"
    end
    if not result.router then
        missing[#missing+1] = "Wireless Modem"
    end

    if #missing > 0 then
        return nil, "Periféricos não encontrados:\n  - " .. table.concat(missing, "\n  - ")
    end

    return result
end

return { detect = detect }
```

- [ ] **Testar detecção manualmente no CC** (com tudo conectado):
  ```lua
  -- Rodar no CC via lua:
  local d = require("detect")
  local hw, err = d.detect()
  if err then print(err) else
    print("altSensor:", hw.altSensor)
    print("speedCtrl:", hw.speedMethod)
    print("router:",    hw.routerName)
    print("altura atual:", hw.altSensor.getHeight())
  end
  ```
  Esperado: mostra os 3 periféricos e uma leitura de altura numérica.

- [ ] **Commit**
  ```
  git add airplane/detect.lua
  git commit -m "feat(airplane): add detect.lua — peripheral auto-detection"
  ```

---

## Task 3: comms.lua — Helpers de comunicação rednet

**Files:**
- Create: `airplane/comms.lua`

- [ ] **Criar `airplane/comms.lua`**

```lua
-- airplane/comms.lua
-- Abstrações sobre rednet para o sistema de estabilização.

local CHANNEL_STATUS = "aviao_status"
local CHANNEL_CMD    = "aviao_cmd"
local TIMEOUT_CORNER = 2   -- segundos sem mensagem → canto offline

-- Abre o modem wireless para rednet
local function open(routerName)
    rednet.open(routerName)
end

-- Canto → todos: transmite altura atual
-- corner: "FL"|"FR"|"RL"|"RR"   height: number
local function broadcastStatus(corner, height)
    rednet.broadcast({ corner = corner, height = height }, CHANNEL_STATUS)
end

-- Cockpit → cantos: transmite altitude alvo e estado
-- target_alt: number   enabled: boolean
local function broadcastCmd(target_alt, enabled)
    rednet.broadcast({ target_alt = target_alt, enabled = enabled }, CHANNEL_CMD)
end

-- Recebe UMA mensagem com timeout.
-- Retorna: protocol (string), data (table), sender_id (number)
-- Retorna nil, nil, nil se timeout esgotar.
local function receive(timeout)
    local id, data, protocol = rednet.receive(nil, timeout)
    return protocol, data, id
end

return {
    open            = open,
    broadcastStatus = broadcastStatus,
    broadcastCmd    = broadcastCmd,
    receive         = receive,
    CHANNEL_STATUS  = CHANNEL_STATUS,
    CHANNEL_CMD     = CHANNEL_CMD,
    TIMEOUT_CORNER  = TIMEOUT_CORNER,
}
```

- [ ] **Testar comunicação entre 2 PCs** — em um PC (transmissor):
  ```lua
  local c = require("comms")
  c.open("back")   -- troque pelo lado do seu modem
  while true do
    c.broadcastStatus("FL", 80)
    sleep(1)
  end
  ```
  Em outro PC (receptor):
  ```lua
  local c = require("comms")
  c.open("back")
  while true do
    local proto, data = c.receive(2)
    if data then print(proto, data.corner, data.height) end
  end
  ```
  Esperado: receptor imprime `aviao_status   FL   80` a cada segundo.

- [ ] **Commit**
  ```
  git add airplane/comms.lua
  git commit -m "feat(airplane): add comms.lua — rednet broadcast/receive helpers"
  ```

---

## Task 4: corner.lua — Programa principal dos cantos

**Files:**
- Create: `airplane/corner.lua`

- [ ] **Criar `airplane/corner.lua`**

```lua
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
```

- [ ] **Copiar para o CC e executar** num PC de canto com tudo conectado:
  ```
  lua corner.lua
  ```
  - Na primeira vez: menu aparece pedindo o canto
  - Depois: display mostra altitude atual, "ATIVO", e `?` nos outros 3 cantos (ainda sem dados)

- [ ] **Verificar que o Speed Controller recebe comandos** — observar se o RPM do controlador muda quando o PC inicia. Deve fixar em `base_speed` (256).

- [ ] **Commit**
  ```
  git add airplane/corner.lua
  git commit -m "feat(airplane): add corner.lua — stabilization main loop"
  ```

---

## Task 5: cockpit.lua — Interface do piloto

**Files:**
- Create: `airplane/cockpit.lua`

- [ ] **Criar `airplane/cockpit.lua`**

```lua
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
    printError("ERRO: Wireless modem não encontrado.")
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
        elseif key == keys.q        then return  -- encerra o parallel
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
        print("╔══════════════════════════════╗")
        print("║   AVIÃO — CONTROLE DE VOO   ║")
        print("╠══════════════════════════════╣")
        print(string.format("║ Altitude alvo:  %5d blocos  ║", state.target_alt))
        print(string.format("║ Altitude atual: %5.1f         ║", avg))
        print(string.format("║ Pitch: %+5.2f°   Roll: %+5.2f°  ║", pitch, roll))
        print("╠══════════════════════════════╣")
        print(string.format("║ FL:%s   FR:%s       ║", fmt(FL), fmt(FR)))
        print(string.format("║ RL:%s   RR:%s       ║", fmt(RL), fmt(RR)))
        print("╠══════════════════════════════╣")
        print("║ [↑/↓] ±1    [PgUp/Dn] ±10   ║")
        print("║ [E] On/Off  [Q] Sair         ║")
        print(string.format("║ Estabilização: %-12s  ║",
            state.enabled and "ATIVA" or "INATIVA"))
        print("╚══════════════════════════════╝")

        sleep(0.2)
    end
end

parallel.waitForAny(sendLoop, receiveLoop, inputLoop, drawLoop)
print("Cockpit encerrado.")
```

- [ ] **Rodar `cockpit.lua` no PC central** com modem wireless conectado:
  ```
  lua cockpit.lua
  ```
  Esperado: interface aparece, aguarda 2s, mostra alturas dos cantos que já estão rodando `corner.lua`. `target_alt` é definido automaticamente como a altitude média recebida.

- [ ] **Commit**
  ```
  git add airplane/cockpit.lua
  git commit -m "feat(airplane): add cockpit.lua — pilot control interface"
  ```

---

## Task 6: Teste de integração in-game

Todos os 4 cantos + cockpit rodando ao mesmo tempo.

- [ ] **Iniciar `corner.lua` nos 4 PCs de canto**, configurando cada um no canto correto (FL, FR, RL, RR). Verificar que:
  - Cada PC mostra as alturas dos outros 3 cantos em ~1s
  - O Speed Controller de cada canto está recebendo RPM (deve mostrar movimento)

- [ ] **Iniciar `cockpit.lua` no PC central**. Verificar que:
  - Todos os 4 cantos aparecem com alturas reais
  - Pitch e Roll mostram ~0.0° (avião nivelado no chão)

- [ ] **Testar controle de altitude** — pressionar `↑` no cockpit várias vezes (alvo sobe de 80 para ~90). Verificar que os RPMs nos 4 cantos aumentam proporcionalmente.

- [ ] **Testar correção de roll** — colocar manualmente 1-2 blocos extra de um lado do avião (peso extra). Verificar que:
  - O lado mais pesado fica com menor `height` no cockpit
  - Roll ≠ 0° no display
  - O lado mais baixo aumenta RPM automaticamente

- [ ] **Testar tolerância a falha** — desligar 1 PC de canto. Verificar que:
  - Após 2s o canto desaparecido mostra `OFF` no cockpit
  - Os outros 3 cantos continuam funcionando com pitch/roll calculado parcialmente

- [ ] **Commit final**
  ```
  git add airplane/
  git commit -m "feat(airplane): complete stabilization system — all files"
  ```
