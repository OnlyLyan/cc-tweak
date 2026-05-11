-- gps-diag.lua
-- Diagnostico de hosts GPS
-- Calcula posicao por minimos quadrados, depois verifica
-- qual host tem distancia medida vs esperada inconsistente.
-- Host com residuo alto = coordenada errada no startup.lua

local GPS_CHANNEL = 65534

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then printError("Modem wireless nao encontrado."); return end

local replyChannel = os.getComputerID() % 65000

term.clear()
term.setCursorPos(1, 1)
print("=== GPS Diagnostico ===")
print("Coletando respostas... 2s")
print()

modem.open(replyChannel)
modem.transmit(GPS_CHANNEL, replyChannel, "PING")

local resp = {}
local tid = os.startTimer(2)
while true do
    local ev = {os.pullEvent()}
    if ev[1] == "modem_message" and ev[3] == replyChannel then
        local msg, dist = ev[5], ev[6]
        if type(msg) == "table" and #msg == 3 and type(dist) == "number" then
            local dup = false
            for _, r in ipairs(resp) do
                if r[1]==msg[1] and r[2]==msg[2] and r[3]==msg[3] then dup=true; break end
            end
            if not dup then resp[#resp+1] = {msg[1], msg[2], msg[3], dist} end
        end
    elseif ev[1] == "timer" and ev[2] == tid then break end
end
modem.close(replyChannel)

print(string.format("Hosts encontrados: %d", #resp))
print()

if #resp < 4 then
    term.setTextColor(colors.red)
    print("[ERRO] Precisa de pelo menos 4 hosts.")
    term.setTextColor(colors.white)
    return
end

-- Minimos quadrados com todos os pares
local function det3(m)
    return m[1][1]*(m[2][2]*m[3][3]-m[2][3]*m[3][2])
         - m[1][2]*(m[2][1]*m[3][3]-m[2][3]*m[3][1])
         + m[1][3]*(m[2][1]*m[3][2]-m[2][2]*m[3][1])
end

local function solve(responses)
    local n = #responses
    local A, b = {}, {}
    for i = 1, n-1 do
        for j = i+1, n do
            local hi, hj = responses[i], responses[j]
            A[#A+1] = {2*(hi[1]-hj[1]), 2*(hi[2]-hj[2]), 2*(hi[3]-hj[3])}
            b[#b+1] = hj[4]^2 - hi[4]^2
                    + hi[1]^2 - hj[1]^2
                    + hi[2]^2 - hj[2]^2
                    + hi[3]^2 - hj[3]^2
        end
    end
    local AtA = {{0,0,0},{0,0,0},{0,0,0}}
    local Atb = {0,0,0}
    for i = 1, #A do
        for r = 1, 3 do
            Atb[r] = Atb[r] + A[i][r] * b[i]
            for c = 1, 3 do AtA[r][c] = AtA[r][c] + A[i][r]*A[i][c] end
        end
    end
    local D = det3(AtA)
    if math.abs(D) < 1e-6 then return nil end
    local x = det3({{Atb[1],AtA[1][2],AtA[1][3]},{Atb[2],AtA[2][2],AtA[2][3]},{Atb[3],AtA[3][2],AtA[3][3]}}) / D
    local y = det3({{AtA[1][1],Atb[1],AtA[1][3]},{AtA[2][1],Atb[2],AtA[2][3]},{AtA[3][1],Atb[3],AtA[3][3]}}) / D
    local z = det3({{AtA[1][1],AtA[1][2],Atb[1]},{AtA[2][1],AtA[2][2],Atb[2]},{AtA[3][1],AtA[3][2],Atb[3]}}) / D
    return x, y, z
end

local px, py, pz = solve(resp)
if not px then
    term.setTextColor(colors.red)
    print("[ERRO] Nao foi possivel calcular posicao.")
    term.setTextColor(colors.white)
    return
end

print(string.format("Posicao calculada: (%d, %d, %d)", math.floor(px), math.floor(py), math.floor(pz)))
print()
print("--- Residuo por host ---")
print("(alto = coordenada errada no startup.lua)")
print()

local THRESHOLD = 5  -- blocos de tolerancia

for i, h in ipairs(resp) do
    local dx = px - h[1]
    local dy = py - h[2]
    local dz = pz - h[3]
    local esperado = math.sqrt(dx*dx + dy*dy + dz*dz)
    local medido   = h[4]
    local residuo  = math.abs(esperado - medido)

    if residuo > THRESHOLD then
        term.setTextColor(colors.red)
        local flag = " << SUSPEITO"
        print(string.format("Host %d (%d,%d,%d)", i, h[1], h[2], h[3]))
        print(string.format("  medido=%.1f  esperado=%.1f  erro=%.1f blocos%s",
            medido, esperado, residuo, flag))
    else
        term.setTextColor(colors.green)
        print(string.format("Host %d (%d,%d,%d)", i, h[1], h[2], h[3]))
        print(string.format("  medido=%.1f  esperado=%.1f  erro=%.1f blocos  OK",
            medido, esperado, residuo))
    end
    term.setTextColor(colors.white)
end

print()
print("Pressione qualquer tecla para sair.")
os.pullEvent("key")
