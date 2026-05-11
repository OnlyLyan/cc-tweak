-- Apaga tudo exceto os arquivos da tartaruga mineradora
local keep = {
  ["control.lua"]      = true,
  ["turtle_miner.lua"] = true,
  ["send_test.lua"]    = true,
  ["recv_test.lua"]    = true,
  ["cleanup.lua"]      = true,
}

local deleted = 0
for _, file in ipairs(fs.list("/")) do
  if not keep[file] and not fs.isDir("/" .. file) then
    fs.delete("/" .. file)
    print("Apagado: " .. file)
    deleted = deleted + 1
  end
end

print("")
print("Pronto! " .. deleted .. " arquivo(s) removido(s).")
print("Arquivos restantes:")
for _, file in ipairs(fs.list("/")) do
  if not fs.isDir("/" .. file) then
    print("  " .. file)
  end
end
