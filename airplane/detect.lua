-- airplane/detect.lua
-- Varre periféricos conectados e classifica por métodos expostos.
-- Retorna: result, err
--   result = { altSensor, speedCtrl, speedMethod, router, routerName }

local function detect()
    local result = {}

    for _, name in ipairs(peripheral.getNames()) do
        local ptype = peripheral.getType(name)
        local p     = peripheral.wrap(name)
        local methods = peripheral.getMethods(name)

        -- Indexar métodos para lookup O(1)
        local mset = {}
        for _, m in ipairs(methods) do mset[m] = true end

        if mset["getHeight"] and not result.altSensor then
            -- Sensor de altitude (Create: Simulated)
            result.altSensor = p

        elseif ptype == "modem" and p.isWireless and p.isWireless() then
            -- Wireless modem / router
            result.router     = p
            result.routerName = name

        elseif not result.speedCtrl then
            -- Speed Controller: qualquer setter com "speed" ou "rpm"
            for _, m in ipairs(methods) do
                local lower = m:lower()
                if lower:find("set") and (lower:find("speed") or lower:find("rpm")) then
                    result.speedCtrl  = p
                    result.speedMethod = m
                    break
                end
            end
        end
    end

    local missing = {}
    if not result.altSensor then
        missing[#missing+1] = "Sensor de altitude  (precisa expor getHeight)"
    end
    if not result.speedCtrl then
        missing[#missing+1] = "Speed Controller    (precisa expor set*Speed ou set*RPM)"
    end
    if not result.router then
        missing[#missing+1] = "Wireless Modem"
    end

    if #missing > 0 then
        return nil, "Periféricos não encontrados:\n  - " .. table.concat(missing, "\n  - ")
    end

    return result
end

return { detect = detect }
