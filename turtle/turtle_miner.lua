-- ================================================================
-- turtle_miner.lua  —  Tartaruga Mineradora com Controle Remoto
-- ================================================================

-- ==================== CONFIGURAÇÃO ===========================
local FUEL_MIN   = 100   -- volta para casa abaixo desse nível
local FUEL_COAL  = 300   -- usa carvão do inv abaixo desse nível
local BRANCH_EVERY = 3   -- galeria lateral a cada N blocos
local BRANCH_LEN   = 6   -- comprimento das galerias laterais

local ORE_PRIO = {
  ["minecraft:ancient_debris"]             = 1,
  ["minecraft:diamond_ore"]                = 1,
  ["minecraft:deepslate_diamond_ore"]      = 1,
  ["minecraft:emerald_ore"]                = 2,
  ["minecraft:deepslate_emerald_ore"]      = 2,
  ["minecraft:gold_ore"]                   = 2,
  ["minecraft:deepslate_gold_ore"]         = 2,
  ["minecraft:nether_gold_ore"]            = 2,
  ["minecraft:iron_ore"]                   = 3,
  ["minecraft:deepslate_iron_ore"]         = 3,
  ["minecraft:lapis_ore"]                  = 3,
  ["minecraft:deepslate_lapis_ore"]        = 3,
  ["minecraft:redstone_ore"]               = 3,
  ["minecraft:deepslate_redstone_ore"]     = 3,
  ["minecraft:coal_ore"]                   = 4,
  ["minecraft:deepslate_coal_ore"]         = 4,
  ["minecraft:copper_ore"]                 = 4,
  ["minecraft:deepslate_copper_ore"]       = 4,
  ["minecraft:quartz_ore"]                 = 3,
  ["minecraft:nether_quartz_ore"]          = 3,
}

local minPrio = 3
-- =============================================================

local pos     = { x = 0, y = 0, z = 0 }
local facing  = 0
local home    = { x = 0, y = 0, z = 0, facing = 0 }
local state   = "aguardando"

local DX = { [0]=0,  [1]=1, [2]=0,  [3]=-1 }
local DZ = { [0]=1,  [1]=0, [2]=-1, [3]=0  }

-- Modem
local modemName = nil
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "modem" then
    modemName = name
    break
  end
end
if not modemName then error("Modem nao encontrado!") end
rednet.open(modemName)

local function log(msg)
  print(msg)
  rednet.broadcast(msg, "miner_log")
end

local function freeSlots()
  local n = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then n = n + 1 end
  end
  return n
end

-- ===== Movimento =====
local function tLeft()  turtle.turnLeft();  facing = (facing + 3) % 4 end
local function tRight() turtle.turnRight(); facing = (facing + 1) % 4 end

local function faceDir(target)
  local diff = (target - facing + 4) % 4
  if     diff == 1 then tRight()
  elseif diff == 2 then tRight(); tRight()
  elseif diff == 3 then tLeft()
  end
end

local function digLoop(detect, dig)
  for _ = 1, 8 do
    if not detect() then return end
    dig(); sleep(0.25)
  end
end

local function stepForward()
  digLoop(turtle.detect, turtle.dig)
  if turtle.forward() then
    pos.x = pos.x + DX[facing]
    pos.z = pos.z + DZ[facing]
    return true
  end
  return false
end

local function stepUp()
  digLoop(turtle.detectUp, turtle.digUp)
  if turtle.up() then pos.y = pos.y + 1; return true end
  return false
end

local function stepDown()
  digLoop(turtle.detectDown, turtle.digDown)
  if turtle.down() then pos.y = pos.y - 1; return true end
  return false
end

-- ===== Combustível =====
local function autoRefuel()
  if turtle.getFuelLevel() >= FUEL_COAL then return end
  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item and (item.name:find("coal") or item.name:find("charcoal")) then
      turtle.select(i)
      turtle.refuel()
      turtle.select(1)
      log("Reabastecido -> " .. turtle.getFuelLevel())
      return
    end
  end
end

-- ===== Mineração =====
local function tryMine(inspect_fn, dig_fn)
  local ok, block = inspect_fn()
  if not ok then return end
  local p = ORE_PRIO[block.name]
  if p and p <= minPrio then
    log("[P" .. p .. "] " .. block.name)
    dig_fn(); sleep(0.2)
  end
end

local function scanSurroundings()
  tryMine(turtle.inspectUp,   turtle.digUp)
  tryMine(turtle.inspectDown, turtle.digDown)
  tLeft();  tryMine(turtle.inspect, turtle.dig); tRight()
  tRight(); tryMine(turtle.inspect, turtle.dig); tLeft()
end

local function mineBranch(length)
  for _ = 1, length do
    tryMine(turtle.inspectUp,   turtle.digUp)
    tryMine(turtle.inspectDown, turtle.digDown)
    stepForward()
  end
  tRight(); tRight()
  for _ = 1, length do stepForward() end
  tRight(); tRight()
end

-- ===== Retorno =====
local function goHome()
  state = "voltando"
  log(string.format("Voltando... pos=%d,%d,%d home=%d,%d,%d",
    pos.x, pos.y, pos.z, home.x, home.y, home.z))

  autoRefuel()

  -- Corrige Y primeiro (sobe/desce antes de navegar horizontal)
  while pos.y > home.y do
    autoRefuel()
    stepDown()
  end
  while pos.y < home.y do
    autoRefuel()
    stepUp()
  end

  -- Corrige Z
  if pos.z > home.z then
    faceDir(2)
    while pos.z > home.z do
      autoRefuel()
      stepForward()
    end
  elseif pos.z < home.z then
    faceDir(0)
    while pos.z < home.z do
      autoRefuel()
      stepForward()
    end
  end

  -- Corrige X
  if pos.x > home.x then
    faceDir(3)
    while pos.x > home.x do
      autoRefuel()
      stepForward()
    end
  elseif pos.x < home.x then
    faceDir(1)
    while pos.x < home.x do
      autoRefuel()
      stepForward()
    end
  end

  faceDir(home.facing)
  state = "aguardando"
  log("Chegou em casa! Fuel: " .. turtle.getFuelLevel())
end

-- ===== Processa comandos =====
local function handleCmd(id, msg)
  if msg == "iniciar" then
    if state == "aguardando" or state == "pausado" then
      state = "minerando"
      log("Mineracao iniciada!")
    end

  elseif msg == "pausar" then
    if state == "minerando" then
      state = "pausado"
      log("Pausado.")
    end

  elseif msg == "continuar" then
    if state == "pausado" then
      state = "minerando"
      log("Continuando.")
    end

  elseif msg == "voltar" then
    log("Comando: voltar para casa")
    return true  -- sinaliza para parar o loop de mineração

  elseif msg == "sethome" then
    home.x = pos.x
    home.y = pos.y
    home.z = pos.z
    home.facing = facing
    log(string.format("Home definido: %d,%d,%d", home.x, home.y, home.z))

  elseif msg == "status" then
    local s = string.format(
      "pos=%d,%d,%d | home=%d,%d,%d | fuel=%d | inv=%d/16 | prio=%d | %s",
      pos.x, pos.y, pos.z,
      home.x, home.y, home.z,
      turtle.getFuelLevel(),
      16 - freeSlots(),
      minPrio, state)
    rednet.send(id, s, "miner_status")

  else
    local n = msg:match("^prio:(%d)$")
    if n then
      minPrio = tonumber(n)
      log("Prioridade: <=" .. minPrio)
    end
  end
  return false
end

-- ===== Heartbeat =====
local function heartbeatLoop()
  while true do
    rednet.broadcast(
      string.format("pos=%d,%d,%d|fuel=%d|inv=%d|%s",
        pos.x, pos.y, pos.z,
        turtle.getFuelLevel(),
        16 - freeSlots(),
        state),
      "miner_hb"
    )
    sleep(3)
  end
end

-- ===== Loop principal =====
local function mainLoop()
  log("Pronto! Aguardando 'iniciar' do PC de controle.")
  while state == "aguardando" do
    local id, msg = rednet.receive("miner_cmd", 1)
    if msg then handleCmd(id, msg) end
  end

  local step = 0
  while state == "minerando" or state == "pausado" do
    local id, msg = rednet.receive("miner_cmd", 0.05)
    if msg then
      local stop = handleCmd(id, msg)
      if stop then break end
    end

    if state == "pausado" then
      sleep(0.3)
    elseif state == "minerando" then
      autoRefuel()

      if turtle.getFuelLevel() < FUEL_MIN then
        log("Combustivel baixo! (" .. turtle.getFuelLevel() .. ") Voltando...")
        break
      end
      if freeSlots() == 0 then
        log("Inventario cheio! Voltando...")
        break
      end

      scanSurroundings()

      if step > 0 and step % BRANCH_EVERY == 0 then
        local d = facing
        tLeft();  mineBranch(BRANCH_LEN); faceDir(d)
        tRight(); mineBranch(BRANCH_LEN); faceDir(d)
      end

      stepForward()
      step = step + 1
    end
  end

  goHome()
end

-- ===== MAIN =====
term.clear(); term.setCursorPos(1,1)
print("=== TARTARUGA MINERADORA ===")
print("Prio: <=" .. minPrio .. " | FuelMin: " .. FUEL_MIN)
autoRefuel()
print("Fuel: " .. turtle.getFuelLevel())
print("Modem: " .. modemName)
print("Dica: use [7] no controle para definir o home")
print("Aguardando PC de controle...")

parallel.waitForAny(heartbeatLoop, mainLoop)
