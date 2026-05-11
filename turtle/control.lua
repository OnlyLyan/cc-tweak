-- ================================================================
-- control.lua  —  PC de Controle da Tartaruga Mineradora
-- ================================================================

local modemName = nil
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "modem" then
    modemName = name
    break
  end
end
if not modemName then error("Modem nao encontrado!") end
rednet.open(modemName)

local lastHeard  = -999
local lastHBData = "---"
local TIMEOUT    = 10

local function isConnected()
  return (os.time() - lastHeard) < TIMEOUT
end

local function send(msg)
  rednet.broadcast(msg, "miner_cmd")
end

-- ===== Cabeçalho =====
local STATUS_LINE = 4
local HB_LINE     = 5

local function drawHeader()
  term.clear(); term.setCursorPos(1,1)
  print("================================")
  print("    CONTROLE - TARTARUGA MINER  ")
  print("================================")
  if isConnected() then
    term.setTextColor(colors.green)
    print(" [CONECTADO]")
    term.setTextColor(colors.lightGray)
    print(" " .. lastHBData:sub(1, 32))
  else
    term.setTextColor(colors.red)
    print(" [DESCONECTADO]")
    term.setTextColor(colors.lightGray)
    print(" (inicie turtle_miner na tartaruga)")
  end
  term.setTextColor(colors.white)
  print("--------------------------------")
  print("[1] Iniciar mineracao")
  print("[2] Pausar")
  print("[3] Continuar")
  print("[4] Mandar voltar para casa")
  print("[5] Ver status completo")
  print("[6] Mudar prioridade de ores")
  print("[7] Definir home aqui")
  print("[0] Fechar")
  print("--------------------------------")
  io.write("> ")
end

-- Atualiza só as linhas de status sem redesenhar o menu todo
local function refreshStatus()
  local cx, cy = term.getCursorPos()
  term.setCursorPos(1, STATUS_LINE)
  term.clearLine()
  if isConnected() then
    term.setTextColor(colors.green)
    io.write(" [CONECTADO]   ")
  else
    term.setTextColor(colors.red)
    io.write(" [DESCONECTADO]")
  end
  term.setTextColor(colors.white)
  term.setCursorPos(1, HB_LINE)
  term.clearLine()
  term.setTextColor(colors.lightGray)
  if isConnected() then
    io.write(" " .. lastHBData:sub(1, 32))
  else
    io.write(" (inicie turtle_miner na tartaruga)")
  end
  term.setTextColor(colors.white)
  term.setCursorPos(cx, cy)
end

-- ===== Leitura com auto-refresh do status =====
local function readOpt()
  while true do
    local ev, p1 = os.pullEvent()
    if ev == "char" then
      return p1
    elseif ev == "turtle_hb" then
      refreshStatus()
    end
  end
end

-- ===== Status detalhado =====
local function getStatus()
  send("status")
  print(""); print("Aguardando resposta...")
  local id, msg = rednet.receive("miner_status", 4)
  if msg then
    print(""); print(">> " .. msg)
  else
    print("Sem resposta.")
    if isConnected() then print("Ultimo HB: " .. lastHBData) end
  end
  print(""); print("ENTER para continuar..."); io.read()
end

-- ===== Prioridade =====
local function showPrioMenu()
  term.clear(); term.setCursorPos(1,1)
  print("=== PRIORIDADE DE MINERACAO ===")
  print("")
  print("P1  Ancient Debris, Diamante")
  print("P2  Esmeralda, Ouro")
  print("P3  Ferro, Lapiz, Redstone, Quartzo")
  print("P4  Carvao, Cobre")
  print("P5  Qualquer minerio listado")
  print("")
  print("Minera tudo com prioridade <= escolha")
  print("Exemplo: 3 = mina P1 + P2 + P3")
  print("")
  io.write("Novo nivel (1-5): ")
  local n = tonumber(io.read())
  if n and n >= 1 and n <= 5 then
    send("prio:" .. n)
    print("Enviado! Minerando ate P" .. n)
  else
    print("Valor invalido.")
  end
  sleep(1.5)
end

-- ===== Menu =====
local function menu()
  drawHeader()
  while true do
    local opt = readOpt()

    if opt == "1" then
      send("iniciar")
      print(""); print("Comando enviado: iniciar!"); sleep(1)
      drawHeader()

    elseif opt == "2" then
      send("pausar")
      print(""); print("Pausado."); sleep(1)
      drawHeader()

    elseif opt == "3" then
      send("continuar")
      print(""); print("Continuando."); sleep(1)
      drawHeader()

    elseif opt == "4" then
      send("voltar")
      print(""); print("Tartaruga voltando para casa!"); sleep(1.5)
      drawHeader()

    elseif opt == "5" then
      getStatus()
      drawHeader()

    elseif opt == "6" then
      showPrioMenu()
      drawHeader()

    elseif opt == "7" then
      send("sethome")
      print(""); print("Home definido na posicao atual da tartaruga!"); sleep(1.5)
      drawHeader()

    elseif opt == "0" then
      break
    end
  end
end

-- ===== Receptor paralelo =====
local function receiver()
  while true do
    local id, msg, proto = rednet.receive()

    if proto == "miner_hb" or proto == "miner_log" or proto == "miner_status" then
      lastHeard = os.time()
    end

    if proto == "miner_hb" then
      lastHBData = tostring(msg)
      os.queueEvent("turtle_hb")

    elseif proto == "miner_log" then
      local cx, cy = term.getCursorPos()
      local w, h   = term.getSize()
      term.setCursorPos(1, h)
      term.clearLine()
      term.setTextColor(colors.yellow)
      io.write("[T] " .. tostring(msg):sub(1, w - 4))
      term.setTextColor(colors.white)
      term.setCursorPos(cx, cy)
    end
  end
end

-- ===== MAIN =====
term.clear(); term.setCursorPos(1,1)
print("=== PC DE CONTROLE ===")
print("Modem: " .. modemName)
print("Aguardando tartaruga...")
sleep(1)

parallel.waitForAny(menu, receiver)
print("PC encerrado.")
