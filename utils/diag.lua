print("=== PERIFERICOS ===")
for _, n in pairs(peripheral.getNames()) do
    local tipos = {peripheral.getType(n)}
    print()
    print("[" .. n .. "]")
    print("  " .. table.concat(tipos, ", "))
    local metodos = peripheral.getMethods(n)
    if metodos and #metodos > 0 then
        for _, m in pairs(metodos) do
            print("    " .. m)
        end
    end
end
print()
print("=== FIM ===")
