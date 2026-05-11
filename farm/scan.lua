local nomes = peripheral.getNames()
print("Perifericos conectados:")
for _, nome in ipairs(nomes) do
    local tipos = {peripheral.getType(nome)}
    print("- " .. nome .. " -> tipos: " .. table.concat(tipos, ", "))
end
