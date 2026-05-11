-- gps-validator.lua
-- Arraste para a pasta do computador CC no servidor e execute: gps-validator

local GPS_CHANNEL = 65534

-- 1. Detecta modem wireless
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)

if not modem then
    printError("Erro: nenhum modem wireless encontrado.")
    return
end

local replyChannel = os.getComputerID() % 65000

-- 2. Header
term.clear()
term.setCursorPos(1, 1)
print("=== GPS Validator ===")
print("PC ID: " .. os.getComputerID())
print("Procurando hosts... aguarde 2s")
print()

-- 3. Ping GPS e coleta respostas
modem.open(replyChannel)
modem.transmit(GPS_CHANNEL, replyChannel, "PING")

local hosts = {}
local timerId = os.startTimer(2)

while true do
    local ev = {os.pullEvent()}
    if ev[1] == "modem_message" and ev[3] == replyChannel then
        local msg = ev[5]
        if type(msg) == "table" and #msg == 3 then
            local dup = false
            for _, h in ipairs(hosts) do
                if h[1] == msg[1] and h[2] == msg[2] and h[3] == msg[3] then
                    dup = true; break
                end
            end
            if not dup then
                hosts[#hosts + 1] = {msg[1], msg[2], msg[3]}
            end
        end
    elseif ev[1] == "timer" and ev[2] == timerId then
        break
    end
end

modem.close(replyChannel)

-- 4. Exibe hosts encontrados
print("Hosts encontrados: " .. #hosts)
for i, h in ipairs(hosts) do
    print(string.format("  Host %d: (%d, %d, %d)", i, h[1], h[2], h[3]))
end
print()

if #hosts < 4 then
    term.setTextColor(colors.red)
    print("[ERRO] Precisa de pelo menos 4 hosts. Encontrados: " .. #hosts)
    term.setTextColor(colors.white)
    print("\nPressione qualquer tecla para sair.")
    os.pullEvent("key")
    return
end

-- 5. Matematica
local function sub(a, b)   return {a[1]-b[1], a[2]-b[2], a[3]-b[3]} end
local function dot(a, b)   return a[1]*b[1] + a[2]*b[2] + a[3]*b[3] end
local function cross(a, b) return {a[2]*b[3]-a[3]*b[2], a[3]*b[1]-a[1]*b[3], a[1]*b[2]-a[2]*b[1]} end
local function len(a)      return math.sqrt(dot(a, a)) end
local function det3(a, b, c)
    return a[1]*(b[2]*c[3]-b[3]*c[2])
         - a[2]*(b[1]*c[3]-b[3]*c[1])
         + a[3]*(b[1]*c[2]-b[2]*c[1])
end
local function tetraVol(a, b, c, d)
    return math.abs(det3(sub(b,a), sub(c,a), sub(d,a))) / 6
end

-- Gera todas as combinacoes de 4 a partir dos hosts encontrados
local function combinations(n, k)
    local result = {}
    local combo = {}
    local function gen(start, depth)
        if depth == k then result[#result+1] = {table.unpack(combo)}; return end
        for i = start, n-(k-depth)+1 do
            combo[depth+1] = i; gen(i+1, depth+1)
        end
    end
    gen(1, 0)
    return result
end

-- Escolhe a combinacao de 4 hosts com maior volume
local bestVol, bestIdx = 0, {1, 2, 3, 4}
for _, c in ipairs(combinations(#hosts, 4)) do
    local v = tetraVol(hosts[c[1]], hosts[c[2]], hosts[c[3]], hosts[c[4]])
    if v > bestVol then bestVol, bestIdx = v, c end
end

local h = {}
for i, idx in ipairs(bestIdx) do h[i] = hosts[idx] end
local vol = bestVol

-- Mostra qual combinacao foi escolhida (so se tiver mais de 4)
if #hosts > 4 then
    local used = table.concat(bestIdx, ", ")
    local ignored = {}
    for i = 1, #hosts do
        local found = false
        for _, idx in ipairs(bestIdx) do if idx == i then found = true; break end end
        if not found then ignored[#ignored+1] = i end
    end
    print(string.format("Melhor combinacao: Hosts %s", used))
    print(string.format("  (ignorando Host %s)", table.concat(ignored, ", ")))
    print()
end

print(string.format("Volume do tetraedro: %.0f blocos3", vol))
print()

-- 6. Rating
local rating, desc, color
if vol > 100000 then
    rating, desc, color = "BOM",      "GPS confiavel",  colors.green
elseif vol > 10000 then
    rating, desc, color = "RAZOAVEL", "GPS funcional",  colors.yellow
else
    rating, desc, color = "RUIM",     "GPS impreciso",  colors.red
end

term.setTextColor(color)
if vol == 0 then
    print("[RUIM] Hosts coplanares — GPS nao vai funcionar!")
else
    print(string.format("[%s] %s (volume: %.0f blocos3)", rating, desc, vol))
end
term.setTextColor(colors.white)

-- 7. Sugestao de onde mover (apenas quando RUIM)
if vol <= 10000 then
    print()

    local function othersOf(i)
        local o = {}
        for j = 1, 4 do if j ~= i then o[#o+1] = h[j] end end
        return o
    end

    -- Host com menor distancia perpendicular ao plano dos outros 3 = o mais redundante
    local worstIdx, worstDist = 1, math.huge
    for i = 1, 4 do
        local o = othersOf(i)
        local n = cross(sub(o[2], o[1]), sub(o[3], o[1]))
        local nLen = len(n)
        local d = nLen > 0 and math.abs(dot(sub(h[i], o[1]), n)) / nLen or 0
        if d < worstDist then worstDist, worstIdx = d, i end
    end

    local bad = h[worstIdx]
    local o   = othersOf(worstIdx)

    -- Centroide dos outros 3
    local cx = (o[1][1]+o[2][1]+o[3][1]) / 3
    local cy = (o[1][2]+o[2][2]+o[3][2]) / 3
    local cz = (o[1][3]+o[2][3]+o[3][3]) / 3

    -- Normal ao plano dos outros 3
    local n    = cross(sub(o[2], o[1]), sub(o[3], o[1]))
    local nLen = len(n)

    term.setTextColor(colors.orange)
    print(string.format("Host problemático: Host %d (%d, %d, %d)", worstIdx, bad[1], bad[2], bad[3]))
    term.setTextColor(colors.white)

    if nLen > 0 then
        local scale = 100 / nLen
        local sx = cx + n[1]*scale
        local sy = cy + n[2]*scale
        local sz = cz + n[3]*scale

        -- Inverte direcao se Y for invalido
        if sy < 0 or sy > 320 then
            sx = cx - n[1]*scale
            sy = cy - n[2]*scale
            sz = cz - n[3]*scale
        end

        if sy >= 0 and sy <= 320 then
            print(string.format("Sugestao: mova para (%d, %d, %d)", math.floor(sx), math.floor(sy), math.floor(sz)))
            print("  ~100 blocos perpendicular ao plano dos outros 3")
        else
            print("Sugestao: posicione em altitude bem diferente dos demais.")
        end
    else
        print("Os outros 3 hosts estao em linha reta.")
        print("Reposicione pelo menos 2 deles para formarem um triangulo.")
    end
end

print()
print("Pressione qualquer tecla para sair.")
os.pullEvent("key")
