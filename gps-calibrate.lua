-- gps-calibrate.lua
-- Roda no computador HOST GPS
-- Modo auto: usa os outros hosts para se localizar
-- Modo manual: voce digita as coordenadas do F3

local function escreverStartup(x, y, z)
    local conteudo = string.format(
[[-- GPS Host — calibrado por gps-calibrate.lua
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then
    printError("Modem wireless nao encontrado. Conecte um modem e reinicie.")
    return
end

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

    local f = fs.open("startup.lua", "w")
    f.write(conteudo)
    f.close()
end

local function lerNumero(prompt)
    while true do
        io.write(prompt)
        local v = tonumber(io.read())
        if v then return math.floor(v) end
        print("  Numero invalido, tente novamente.")
    end
end

-- Header
term.clear()
term.setCursorPos(1, 1)
print("=== GPS Calibracao ===")
print()
print("Modo:")
print("  [1] Auto (usa outros hosts)")
print("  [2] Manual (voce digita o F3)")
io.write("> ")
local modo = io.read()
print()

local x, y, z

if modo == "1" then
    print("Localizando via GPS...")
    x, y, z = gps.locate(5)
    if not x then
        term.setTextColor(colors.red)
        print("[ERRO] Sem sinal GPS.")
        print("Use o modo manual (2) se todos os hosts")
        print("estiverem com coordenadas erradas.")
        term.setTextColor(colors.white)
        return
    end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    term.setTextColor(colors.green)
    print(string.format("Posicao: (%d, %d, %d)", x, y, z))
    term.setTextColor(colors.white)

elseif modo == "2" then
    print("Abra o F3 e olhe as coordenadas")
    print("DESTE computador (bloco onde esta).")
    print()
    x = lerNumero("X: ")
    y = lerNumero("Y: ")
    z = lerNumero("Z: ")
    print()
    term.setTextColor(colors.yellow)
    print(string.format("Coordenadas: (%d, %d, %d)", x, y, z))
    term.setTextColor(colors.white)

else
    print("Opcao invalida. Saindo.")
    return
end

-- Confirmacao
print()
print("Confirmar e reescrever startup.lua? (S/N)")
local resp = string.lower(io.read())
if resp ~= "s" then
    print("Cancelado.")
    return
end

escreverStartup(x, y, z)

term.setTextColor(colors.green)
print("startup.lua atualizado!")
term.setTextColor(colors.white)
print("Reiniciando em 3s...")
os.sleep(3)
os.reboot()
