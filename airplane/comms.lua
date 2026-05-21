-- airplane/comms.lua
-- Abstrações sobre rednet para o sistema de estabilização.

local CHANNEL_STATUS = "aviao_status"
local CHANNEL_CMD    = "aviao_cmd"
local TIMEOUT_CORNER = 2   -- segundos sem mensagem → canto offline

-- Abre o modem wireless para rednet
local function open(routerName)
    rednet.open(routerName)
end

-- Canto → todos: transmite altura atual
-- corner: "FL"|"FR"|"RL"|"RR"   height: number
local function broadcastStatus(corner, height)
    rednet.broadcast({ corner = corner, height = height }, CHANNEL_STATUS)
end

-- Cockpit → cantos: transmite altitude alvo e estado
-- target_alt: number   enabled: boolean
local function broadcastCmd(target_alt, enabled)
    rednet.broadcast({ target_alt = target_alt, enabled = enabled }, CHANNEL_CMD)
end

-- Recebe UMA mensagem com timeout.
-- Retorna: protocol (string), data (table), sender_id (number)
-- Retorna nil, nil, nil se timeout esgotar.
local function receive(timeout)
    local id, data, protocol = rednet.receive(nil, timeout)
    return protocol, data, id
end

return {
    open            = open,
    broadcastStatus = broadcastStatus,
    broadcastCmd    = broadcastCmd,
    receive         = receive,
    CHANNEL_STATUS  = CHANNEL_STATUS,
    CHANNEL_CMD     = CHANNEL_CMD,
    TIMEOUT_CORNER  = TIMEOUT_CORNER,
}
