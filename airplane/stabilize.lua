-- airplane/stabilize.lua
-- Cálculo de RPM para estabilização. Sem efeitos colaterais.

local SIGNS = {
    FL = { pitch = -1, roll = -1 },
    FR = { pitch = -1, roll =  1 },
    RL = { pitch =  1, roll = -1 },
    RR = { pitch =  1, roll =  1 },
}

-- params: { base_speed, max_speed, kA, kP, kR, target_alt }
-- heights: { FL=n, FR=n, RL=n, RR=n }  (qualquer campo pode ser nil)
-- corner: "FL" | "FR" | "RL" | "RR"
-- Retorna: rpm (integer)
local function calcSpeed(params, heights, corner)
    local sign = SIGNS[corner]
    if not sign then return params.base_speed end

    local sum, count = 0, 0
    for _, h in pairs(heights) do
        sum   = sum + h
        count = count + 1
    end

    if count == 0 then return params.base_speed end

    local avg_all  = sum / count
    local alt_error = params.target_alt - avg_all

    -- Pitch (frente vs trás)
    local front_sum, front_n = 0, 0
    local rear_sum,  rear_n  = 0, 0
    if heights.FL then front_sum = front_sum + heights.FL; front_n = front_n + 1 end
    if heights.FR then front_sum = front_sum + heights.FR; front_n = front_n + 1 end
    if heights.RL then rear_sum  = rear_sum  + heights.RL; rear_n  = rear_n  + 1 end
    if heights.RR then rear_sum  = rear_sum  + heights.RR; rear_n  = rear_n  + 1 end

    local pitch_error = 0
    if front_n > 0 and rear_n > 0 then
        pitch_error = front_sum / front_n - rear_sum / rear_n
    end

    -- Roll (esquerda vs direita)
    local left_sum,  left_n  = 0, 0
    local right_sum, right_n = 0, 0
    if heights.FL then left_sum  = left_sum  + heights.FL; left_n  = left_n  + 1 end
    if heights.RL then left_sum  = left_sum  + heights.RL; left_n  = left_n  + 1 end
    if heights.FR then right_sum = right_sum + heights.FR; right_n = right_n + 1 end
    if heights.RR then right_sum = right_sum + heights.RR; right_n = right_n + 1 end

    local roll_error = 0
    if left_n > 0 and right_n > 0 then
        roll_error = left_sum / left_n - right_sum / right_n
    end

    local speed = params.base_speed
               + params.kA * alt_error
               + params.kP * sign.pitch * pitch_error
               + params.kR * sign.roll  * roll_error

    speed = math.max(0, math.min(params.max_speed, speed))
    return math.floor(speed)
end

return { calcSpeed = calcSpeed }
