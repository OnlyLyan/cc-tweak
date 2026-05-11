-- Roda na TARTARUGA
local modemName
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "modem" then
    modemName = name; break
  end
end
print("Modem: " .. tostring(modemName))
if not modemName then print("SEM MODEM!"); return end
rednet.open(modemName)
print("Enviando 'ping' a cada 2s...")
local n = 0
while true do
  n = n + 1
  rednet.broadcast("ping #" .. n, "teste")
  print("Enviado #" .. n)
  sleep(2)
end
