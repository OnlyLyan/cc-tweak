-- gps-pocket.lua
-- GPS por minimos quadrados com todos os pares de hosts
-- Mais robusto que trilateration com 4 hosts fixos
-- [Q] para sair

local GPS_CHANNEL     = 65534
local PING_TIMEOUT    = 1.5
local UPDATE_INTERVAL = 2

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then printError("Modem wireless nao encontrado."); return end

local replyChannel = os.getComputerID() % 65000
modem.open(replyChannel)

-- Determinante 3x3
local function det3(m)
    return m[1][1]*(m[2][2]*m[3][3]-m[2][3]*m[3][2])
         - m[1][2]*(m[2][1]*m[3][3]-m[2][3]*m[3][1])
         + m[1][3]*(m[2][1]*m[3][2]-m[2][2]*m[3][1])
end

-- Minimos quadrados usando TODOS os pares de hosts
-- Cada par (i,j) gera uma equacao linear em x,y,z (elimina termos quadraticos)
-- Sistema sobredeterminado: Ax = b → resolve com (AtA)x = Atb
local function locate(responses)
    local n = #responses
    if n < 4 then return nil end

    local A, b = {}, {}
    for i = 1, n-1 do
        for j = i+1, n do
            local hi, hj = responses[i], responses[j]
            -- (xi²-xj²) + (yi²-yj²) + (zi²-zj²) + dj²-di² = 2(xi-xj)x + 2(yi-yj)y + 2(zi-zj)z
            A[#A+1] = {
                2*(hi[1]-hj[1]),
                2*(hi[2]-hj[2]),
                2*(hi[3]-hj[3])
            }
            b[#b+1] = hj[4]^2 - hi[4]^2
                    + hi[1]^2 - hj[1]^2
                    + hi[2]^2 - hj[2]^2
                    + hi[3]^2 - hj[3]^2
        end
    end

    -- Monta AtA (3x3) e Atb (3x1)
    local AtA = {{0,0,0},{0,0,0},{0,0,0}}
    local Atb = {0, 0, 0}
    for i = 1, #A do
        for r = 1, 3 do
            Atb[r] = Atb[r] + A[i][r] * b[i]
            for c = 1, 3 do
                AtA[r][c] = AtA[r][c] + A[i][r] * A[i][c]
            end
        end
    end

    -- Resolve AtA * x = Atb por regra de Cramer
    local D = det3(AtA)
    if math.abs(D) < 1e-6 then return nil end

    local x = det3({{Atb[1],AtA[1][2],AtA[1][3]},
                    {Atb[2],AtA[2][2],AtA[2][3]},
                    {Atb[3],AtA[3][2],AtA[3][3]}}) / D

    local y = det3({{AtA[1][1],Atb[1],AtA[1][3]},
                    {AtA[2][1],Atb[2],AtA[2][3]},
                    {AtA[3][1],Atb[3],AtA[3][3]}}) / D

    local z = det3({{AtA[1][1],AtA[1][2],Atb[1]},
                    {AtA[2][1],AtA[2][2],Atb[2]},
                    {AtA[3][1],AtA[3][2],Atb[3]}}) / D

    return x, y, z
end

-- Coleta respostas de todos os hosts via PING
local function ping()
    modem.transmit(GPS_CHANNEL, replyChannel, "PING")
    local resp = {}
    local tid  = os.startTimer(PING_TIMEOUT)
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
        elseif ev[1] == "timer" and ev[2] == tid then
            break
        end
    end
    return resp
end

local function draw(x, y, z, n)
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Localizacao GPS ===")
    print()
    if x then
        print(string.format("  X: %d", math.floor(x)))
        print(string.format("  Y: %d", math.floor(y)))
        print(string.format("  Z: %d", math.floor(z)))
        print()
        term.setTextColor(colors.green)
        print(string.format("  [OK] %d hosts / %d equacoes",
            n, n*(n-1)/2))
        term.setTextColor(colors.white)
    else
        term.setTextColor(colors.red)
        if n and n > 0 then
            print(string.format("  [ERRO] Apenas %d host(s)", n))
            print("  Precisa de pelo menos 4.")
        else
            print("  [ERRO] Sem sinal GPS")
        end
        term.setTextColor(colors.white)
    end
    print()
    print("  [Q] Sair")
end

-- Loop principal
local tid = os.startTimer(0)
while true do
    local ev = {os.pullEvent()}
    if ev[1] == "timer" and ev[2] == tid then
        local resp = ping()
        local x, y, z = locate(resp)
        draw(x, y, z, #resp)
        tid = os.startTimer(UPDATE_INTERVAL)
    elseif ev[1] == "key" and ev[2] == keys.q then
        break
    elseif ev[1] == "char" and ev[2] == "q" then
        break
    end
end

modem.close(replyChannel)
term.clear()
term.setCursorPos(1, 1)
