-- airplane/test_stabilize.lua
-- Rodar no CC: lua test_stabilize.lua
local stab   = require("stabilize")
local passed = 0
local failed = 0

local function test(name, got, expected, tol)
    tol = tol or 0
    if math.abs(got - expected) <= tol then
        passed = passed + 1
        print("PASS: " .. name)
    else
        failed = failed + 1
        print(string.format("FAIL: %s  got=%d  expected=%d", name, got, expected))
    end
end

local p = { base_speed=256, max_speed=512, kA=10, kP=5, kR=5, target_alt=80 }

-- Nivelado na altitude alvo → velocidade base
local flat = { FL=80, FR=80, RL=80, RR=80 }
test("flat FL", stab.calcSpeed(p, flat, "FL"), 256)
test("flat FR", stab.calcSpeed(p, flat, "FR"), 256)
test("flat RL", stab.calcSpeed(p, flat, "RL"), 256)
test("flat RR", stab.calcSpeed(p, flat, "RR"), 256)

-- 2 blocos abaixo do alvo → kA*2 = +20 em todos
local below = { FL=78, FR=78, RL=78, RR=78 }
test("below FL", stab.calcSpeed(p, below, "FL"), 276)
test("below RR", stab.calcSpeed(p, below, "RR"), 276)

-- Esquerda 2 blocos mais alta (roll_error=+2): esq. -kR*2=-10, dir. +kR*2=+10
-- avg=80 → alt_error=0
local rolled = { FL=81, FR=79, RL=81, RR=79 }
test("rolled FL", stab.calcSpeed(p, rolled, "FL"), 246)  -- 256-10
test("rolled FR", stab.calcSpeed(p, rolled, "FR"), 266)  -- 256+10
test("rolled RL", stab.calcSpeed(p, rolled, "RL"), 246)
test("rolled RR", stab.calcSpeed(p, rolled, "RR"), 266)

-- Frente 2 blocos mais alta (pitch_error=+2): frente -kP*2=-10, trás +kP*2=+10
local pitched = { FL=81, FR=81, RL=79, RR=79 }
test("pitched FL", stab.calcSpeed(p, pitched, "FL"), 246)
test("pitched FR", stab.calcSpeed(p, pitched, "FR"), 246)
test("pitched RL", stab.calcSpeed(p, pitched, "RL"), 266)
test("pitched RR", stab.calcSpeed(p, pitched, "RR"), 266)

-- Clamp mínimo: muito acima do alvo
local way_above = { FL=200, FR=200, RL=200, RR=200 }
test("clamp min FL", stab.calcSpeed(p, way_above, "FL"), 0)

-- Clamp máximo: muito abaixo do alvo
local way_below = { FL=0, FR=0, RL=0, RR=0 }
test("clamp max FL", stab.calcSpeed(p, way_below, "FL"), 512)

-- Apenas 2 cantos disponíveis (parcial)
local partial = { FL=80, FR=80 }
test("partial_2corners FL", stab.calcSpeed(p, partial, "FL"), 256)

print(string.format("\n%d passed, 0 failed", passed, failed))
