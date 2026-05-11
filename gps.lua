-- gps.lua — GPS Tools Unificado
-- Funciona em Pocket Computer e PC
-- Mova apenas este arquivo para qualquer computador

local GPS_CHANNEL = 65534
local W = term.getSize()
local isPocket = W <= 26

-- ============================================================
-- UTILITARIOS
-- ============================================================

local function cls() term.clear(); term.setCursorPos(1,1) end

local function header(titulo)
    cls()
    if isPocket then
        print("=== " .. titulo .. " ===")
    else
        print(string.rep("=", W))
        local pad = math.floor((W - #titulo) / 2)
        print(string.rep(" ", pad) .. titulo)
        print(string.rep("=", W))
    end
    print()
end

local function aguardarTecla(msg)
    print()
    print(msg or "Pressione qualquer tecla...")
    os.pullEvent("key")
end

local function lerOpcao(validas)
    while true do
        local ev = {os.pullEvent("char")}
        local c = string.lower(ev[2])
        for _, v in ipairs(validas) do
            if c == v then return c end
        end
    end
end

-- ============================================================
-- MATEMATICA GPS
-- ============================================================

local function det3(m)
    return m[1][1]*(m[2][2]*m[3][3]-m[2][3]*m[3][2])
         - m[1][2]*(m[2][1]*m[3][3]-m[2][3]*m[3][1])
         + m[1][3]*(m[2][1]*m[3][2]-m[2][2]*m[3][1])
end

-- Minimos quadrados com todos os pares de hosts
local function calcPosicao(resp)
    local n = #resp
    if n < 4 then return nil end
    local A, b = {}, {}
    for i = 1, n-1 do
        for j = i+1, n do
            local hi, hj = resp[i], resp[j]
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
            Atb[r] = Atb[r] + A[i][r]*b[i]
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

-- Volume do tetraedro (para validador)
local function sub(a,b) return {a[1]-b[1],a[2]-b[2],a[3]-b[3]} end
local function tetraVol(a,b,c,d)
    local function det(u,v,w)
        return u[1]*(v[2]*w[3]-v[3]*w[2])
             - u[2]*(v[1]*w[3]-v[3]*w[1])
             + u[3]*(v[1]*w[2]-v[2]*w[1])
    end
    return math.abs(det(sub(b,a),sub(c,a),sub(d,a)))/6
end

-- ============================================================
-- GPS PING
-- ============================================================

local function ping(timeout)
    local modem = peripheral.find("modem", function(_,m) return m.isWireless() end)
    if not modem then return nil, "Sem modem wireless" end
    local ch = os.getComputerID() % 65000
    modem.open(ch)
    modem.transmit(GPS_CHANNEL, ch, "PING")
    local resp = {}
    local tid = os.startTimer(timeout or 2)
    while true do
        local ev = {os.pullEvent()}
        if ev[1]=="modem_message" and ev[3]==ch then
            local msg, dist = ev[5], ev[6]
            if type(msg)=="table" and #msg==3 and type(dist)=="number" then
                local dup = false
                for _,r in ipairs(resp) do
                    if r[1]==msg[1] and r[2]==msg[2] and r[3]==msg[3] then dup=true; break end
                end
                if not dup then resp[#resp+1]={msg[1],msg[2],msg[3],dist} end
            end
        elseif ev[1]=="timer" and ev[2]==tid then break end
    end
    modem.close(ch)
    return resp
end

-- ============================================================
-- MODULO: LOCALIZAR
-- ============================================================

local function modLocalizar()
    local modem = peripheral.find("modem", function(_,m) return m.isWireless() end)
    if not modem then
        header("Localizar")
        term.setTextColor(colors.red)
        print("Sem modem wireless.")
        term.setTextColor(colors.white)
        aguardarTecla()
        return
    end

    local ch = os.getComputerID() % 65000
    modem.open(ch)

    local function atualizar()
        modem.transmit(GPS_CHANNEL, ch, "PING")
        local resp = {}
        local tid = os.startTimer(1.5)
        while true do
            local ev = {os.pullEvent()}
            if ev[1]=="modem_message" and ev[3]==ch then
                local msg, dist = ev[5], ev[6]
                if type(msg)=="table" and #msg==3 and type(dist)=="number" then
                    local dup = false
                    for _,r in ipairs(resp) do
                        if r[1]==msg[1] and r[2]==msg[2] and r[3]==msg[3] then dup=true; break end
                    end
                    if not dup then resp[#resp+1]={msg[1],msg[2],msg[3],dist} end
                end
            elseif ev[1]=="timer" and ev[2]==tid then break end
        end
        return resp
    end

    local tid = os.startTimer(0)
    local x, y, z, n

    while true do
        local ev = {os.pullEvent()}
        if ev[1]=="timer" and ev[2]==tid then
            local resp = atualizar()
            x, y, z = calcPosicao(resp)
            n = #resp
            cls()
            print("=== GPS ===")
            print()
            if x then
                print(string.format("  X: %d", math.floor(x)))
                print(string.format("  Y: %d", math.floor(y)))
                print(string.format("  Z: %d", math.floor(z)))
                print()
                term.setTextColor(colors.green)
                print(string.format("  OK (%d hosts)", n))
            else
                term.setTextColor(colors.red)
                if n > 0 then
                    print(string.format("  Apenas %d host(s)", n))
                else
                    print("  Sem sinal GPS")
                end
            end
            term.setTextColor(colors.white)
            print()
            print("  [Q] Menu")
            tid = os.startTimer(2)
        elseif ev[1]=="char" and (ev[2]=="q" or ev[2]=="Q") then
            break
        elseif ev[1]=="key" and ev[2]==keys.q then
            break
        end
    end

    modem.close(ch)
end

-- ============================================================
-- MODULO: VALIDAR
-- ============================================================

local function modValidar()
    header("Validar Hosts")
    print("Procurando hosts... 2s")
    local resp, err = ping(2)
    if not resp then
        term.setTextColor(colors.red); print(err); term.setTextColor(colors.white)
        aguardarTecla(); return
    end

    print(string.format("Hosts encontrados: %d", #resp))
    for i,h in ipairs(resp) do
        print(string.format("  %d: (%d,%d,%d)", i, h[1],h[2],h[3]))
    end
    print()

    if #resp < 4 then
        term.setTextColor(colors.red)
        print("Precisa de pelo menos 4 hosts.")
        term.setTextColor(colors.white)
        aguardarTecla(); return
    end

    -- Melhor combinacao de 4
    local function combinations(n,k)
        local res,combo={},{}
        local function gen(s,d)
            if d==k then res[#res+1]={table.unpack(combo)};return end
            for i=s,n-(k-d)+1 do combo[d+1]=i;gen(i+1,d+1) end
        end
        gen(1,0); return res
    end

    local bestVol,bestIdx=0,{1,2,3,4}
    for _,c in ipairs(combinations(#resp,4)) do
        local v=tetraVol(resp[c[1]],resp[c[2]],resp[c[3]],resp[c[4]])
        if v>bestVol then bestVol,bestIdx=v,c end
    end

    if #resp>4 then
        local ignored={}
        for i=1,#resp do
            local ok=false
            for _,idx in ipairs(bestIdx) do if idx==i then ok=true;break end end
            if not ok then ignored[#ignored+1]=i end
        end
        print(string.format("Melhor combo: %s", table.concat(bestIdx,",")))
        print(string.format("(ignorando: %s)", table.concat(ignored,",")))
        print()
    end

    print(string.format("Volume: %.0f blocos3", bestVol))
    print()

    local rating,color
    if bestVol>100000 then rating,color="BOM",colors.green
    elseif bestVol>10000 then rating,color="RAZOAVEL",colors.yellow
    elseif bestVol==0 then rating,color="COPLANAR",colors.red
    else rating,color="RUIM",colors.red end

    term.setTextColor(color)
    print(string.format("[%s]", rating))
    term.setTextColor(colors.white)

    -- Sugestao se ruim
    if bestVol<=10000 then
        local h={}
        for i,idx in ipairs(bestIdx) do h[i]=resp[idx] end
        local function cross(a,b) return {a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]} end
        local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
        local function len(a) return math.sqrt(dot(a,a)) end
        local function othersOf(arr,i)
            local o={}
            for j=1,#arr do if j~=i then o[#o+1]=arr[j] end end
            return o
        end
        local worst,wd=1,math.huge
        for i=1,4 do
            local o=othersOf(h,i)
            local n=cross(sub(o[2],o[1]),sub(o[3],o[1]))
            local nl=len(n)
            local d=nl>0 and math.abs(dot(sub(h[i],o[1]),n))/nl or 0
            if d<wd then wd,worst=d,i end
        end
        local bad=h[worst]
        local o=othersOf(h,worst)
        local cx=(o[1][1]+o[2][1]+o[3][1])/3
        local cy=(o[1][2]+o[2][2]+o[3][2])/3
        local cz=(o[1][3]+o[2][3]+o[3][3])/3
        local n=cross(sub(o[2],o[1]),sub(o[3],o[1]))
        local nl=len(n)
        print()
        term.setTextColor(colors.orange)
        print(string.format("Mover Host %d (%d,%d,%d)", worst,bad[1],bad[2],bad[3]))
        term.setTextColor(colors.white)
        if nl>0 then
            local sc=100/nl
            local sx,sy,sz=cx+n[1]*sc,cy+n[2]*sc,cz+n[3]*sc
            if sy<0 or sy>320 then sx,sy,sz=cx-n[1]*sc,cy-n[2]*sc,cz-n[3]*sc end
            if sy>=0 and sy<=320 then
                print(string.format("Sugestao: (%d,%d,%d)",math.floor(sx),math.floor(sy),math.floor(sz)))
            end
        end
    end

    aguardarTecla()
end

-- ============================================================
-- MODULO: DIAGNOSTICO
-- ============================================================

local function modDiag()
    header("Diagnostico")
    print("Coletando respostas... 2s")
    local resp, err = ping(2)
    if not resp then
        term.setTextColor(colors.red); print(err); term.setTextColor(colors.white)
        aguardarTecla(); return
    end

    if #resp < 4 then
        term.setTextColor(colors.red)
        print(string.format("Apenas %d host(s). Precisa de 4.", #resp))
        term.setTextColor(colors.white)
        aguardarTecla(); return
    end

    local px,py,pz = calcPosicao(resp)
    if not px then
        term.setTextColor(colors.red); print("Nao foi possivel calcular posicao.")
        term.setTextColor(colors.white); aguardarTecla(); return
    end

    print(string.format("Posicao: (%d, %d, %d)", math.floor(px),math.floor(py),math.floor(pz)))
    print()

    for i,h in ipairs(resp) do
        local dx,dy,dz = px-h[1],py-h[2],pz-h[3]
        local esperado = math.sqrt(dx*dx+dy*dy+dz*dz)
        local residuo  = math.abs(esperado-h[4])
        if residuo > 5 then
            term.setTextColor(colors.red)
            print(string.format("Host %d (%d,%d,%d)", i,h[1],h[2],h[3]))
            print(string.format("  erro=%.1f blocos << SUSPEITO", residuo))
        else
            term.setTextColor(colors.green)
            print(string.format("Host %d (%d,%d,%d) OK (%.1f)", i,h[1],h[2],h[3],residuo))
        end
        term.setTextColor(colors.white)
    end

    aguardarTecla()
end

-- ============================================================
-- MODULO: CALIBRAR
-- ============================================================

local function modCalibrar()
    header("Calibrar Host GPS")
    print("[1] Auto (usa outros hosts)")
    print("[2] Manual (digita coords F3)")
    print("[Q] Voltar")
    print()
    io.write("> ")
    local op = lerOpcao({"1","2","q"})
    if op=="q" then return end
    print()

    local x,y,z

    if op=="1" then
        print("Localizando via GPS...")
        x,y,z = gps.locate(5)
        if not x then
            term.setTextColor(colors.red)
            print("Sem sinal. Use modo Manual.")
            term.setTextColor(colors.white)
            aguardarTecla(); return
        end
        x,y,z = math.floor(x),math.floor(y),math.floor(z)
        term.setTextColor(colors.green)
        print(string.format("Posicao: (%d, %d, %d)", x,y,z))
        term.setTextColor(colors.white)
    else
        print("Mire no bloco deste computador")
        print("e leia Block: X Y Z no F3.")
        print()
        local function lerNum(label)
            while true do
                io.write(label)
                local v = tonumber(io.read())
                if v then return math.floor(v) end
                print("Numero invalido.")
            end
        end
        x = lerNum("X: ")
        y = lerNum("Y: ")
        z = lerNum("Z: ")
        term.setTextColor(colors.yellow)
        print(string.format("Coordenadas: (%d, %d, %d)", x,y,z))
        term.setTextColor(colors.white)
    end

    print()
    print("Reescrever startup.lua? (S/N)")
    local conf = lerOpcao({"s","n"})
    if conf~="s" then print("Cancelado."); aguardarTecla(); return end

    local conteudo = string.format(
[[-- GPS Host — calibrado por gps.lua
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then printError("Modem wireless nao encontrado."); return end

local x, y, z = %d, %d, %d
modem.open(65534)
print("GPS Host ativo em (" .. x .. ", " .. y .. ", " .. z .. ")")

while true do
    local ev = {os.pullEvent("modem_message")}
    if ev[3] == 65534 and ev[5] == "PING" then
        modem.transmit(ev[4], 65534, {x, y, z})
    end
end
]], x, y, z)

    local f = fs.open("startup.lua","w")
    f.write(conteudo); f.close()

    term.setTextColor(colors.green)
    print("startup.lua atualizado!")
    term.setTextColor(colors.white)
    print("Reiniciando em 3s...")
    os.sleep(3)
    os.reboot()
end

-- ============================================================
-- MODULO: LIMPAR
-- ============================================================

local function modLimpar()
    header("Limpar Arquivos Antigos")
    local antigos = {"gps-validator.lua","gps-pocket.lua","gps-calibrate.lua","gps-diag.lua"}
    local encontrados = {}
    for _,f in ipairs(antigos) do
        if fs.exists(f) then encontrados[#encontrados+1]=f end
    end

    if #encontrados==0 then
        term.setTextColor(colors.green)
        print("Nenhum arquivo antigo encontrado.")
        term.setTextColor(colors.white)
        aguardarTecla(); return
    end

    print("Arquivos encontrados:")
    for _,f in ipairs(encontrados) do print("  "..f) end
    print()
    print("Deletar todos? (S/N)")
    local conf = lerOpcao({"s","n"})
    if conf~="s" then print("Cancelado."); aguardarTecla(); return end

    for _,f in ipairs(encontrados) do
        fs.delete(f)
        print("  Deletado: "..f)
    end
    term.setTextColor(colors.green)
    print("Limpeza concluida.")
    term.setTextColor(colors.white)
    aguardarTecla()
end

-- ============================================================
-- MENU PRINCIPAL
-- ============================================================

local opcoes = {
    {k="1", l="Localizar",    f=modLocalizar},
    {k="2", l="Validar Hosts",f=modValidar},
    {k="3", l="Diagnostico",  f=modDiag},
    {k="4", l="Calibrar Host",f=modCalibrar},
    {k="5", l="Limpar",       f=modLimpar},
}

while true do
    cls()
    if isPocket then
        print("=== GPS Tools ===")
    else
        print(string.rep("=",W))
        local t=" GPS Tools "; print(string.rep(" ",math.floor((W-#t)/2))..t)
        print(string.rep("=",W))
    end
    print()
    for _,op in ipairs(opcoes) do
        print(string.format("  [%s] %s", op.k, op.l))
    end
    print("  [Q] Sair")
    print()
    io.write("> ")
    local c = lerOpcao({"1","2","3","4","5","q"})
    if c=="q" then break end
    for _,op in ipairs(opcoes) do
        if c==op.k then op.f(); break end
    end
end

cls()
