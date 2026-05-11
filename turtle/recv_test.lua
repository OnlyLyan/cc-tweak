-- Roda no PC
local modemName
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "modem" then
    modemName = name; break
  end
end
print("Modem: " .. tostring(modemName))
if not modemName then print("SEM MODEM!"); return end
rednet.open(modemName)
print("Aguardando mensagens...")
while true do
  local id, msg, proto = rednet.receive(5)
  if id then
    print("ID=" .. id .. " proto=" .. tostring(proto) .. " msg=" .. tostring(msg))
  else
    print("(timeout - nada recebido)")
  end
end
