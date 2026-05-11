# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

ComputerCraft Lua scripts for Minecraft with the Create mod. They run directly on in-game computers — there is no build step, no package manager, no test runner. Development means editing `.lua` files and reloading them in-game.

## Deployment

Files are copied directly into ComputerCraft computers via the game filesystem. `startup.lua` runs automatically on boot.

To test a change: save the file, then in-game run `reboot` or re-execute the script.

## Architecture

### farm/startup.lua — Main System (single file, four modes)

The entry point for all farm monitoring. On startup it auto-detects the environment and branches into one of four operating modes:

| Mode | Hardware | Role |
|------|----------|------|
| `modoCentral` | PC + large monitor (≥70 wide) | Aggregates all zones, paginated overview |
| `modoZona` | PC + small monitor | Local farm monitoring + toggle control |
| `modoPocket` | Pocket computer | Wireless dashboard with audio alerts |
| `modoFonte` | PC (isFonte=true in config) | Power/stressometer broadcast |

All modes run **concurrent loops via `parallel.waitForAny()`** — typically a data/send loop, a draw loop, and an input/receive loop.

### Config System

On first run, `startup.lua` scans connected peripherals and generates `farms.cfg` as a Lua file that returns a table. Reload the script after editing config:

```lua
-- farms.cfg structure
return {
  zoneName = "Zona Central",
  isCentral = true,
  isFonte = false,
  stressometer = "Create_Stressometer_0",
  farms = {
    { name = "Farm 1",
      speed  = "Create_Speedometer_0",
      output = "storagedrawers:standard_drawers_1_0",
      input  = "minecraft:chest_0",
      alerts = { minInput = 16, maxOutputPct = 90 } }
  }
}
```

### Wireless Protocols (rednet)

| Protocol | Flow | Purpose |
|----------|------|---------|
| `farm_monitor` | Zone↔Central↔Pocket | Farm status aggregation |
| `miner_cmd` | Control→Turtle | Mining commands |
| `miner_hb` | Turtle→Control | Heartbeat (position, fuel, inv) every 3s |
| `miner_log` | Turtle→Control | Debug messages |
| `miner_status` | Turtle→Control | Full status response |

### Turtle Mining (turtle/)

`turtle_miner.lua` is a state machine (aguardando → minerando → pausado → voltando) with branch mining, fuel management, and ore prioritization (5 tiers). It waits for `iniciar` over `miner_cmd` before doing anything.

`control.lua` is the interactive PC controller — sends commands, receives heartbeat, shows live status.

## Key Patterns

**Safe peripheral calls** — always wrap peripheral API calls in `pcall` to avoid crashes when hardware is missing:
```lua
local function safe(func, ...) local ok, r = pcall(func, ...); return ok and r or nil end
```

**Offline detection** — remote zone data has a 10-second staleness check (`os.clock()-cache.lastUpdate < 10`). Stale zones show as OFFLINE.

**Responsive layout** — central monitor columns: 1 col < 70w, 2 cols 70–129w, 3 cols ≥130w.

**Status color convention** — OK=lime (<70% stress), WARN=yellow (70–90%), CRIT/ERR=red (>90%).

**Item name display** — strip mod namespace and underscores: `"minecraft:diamond_ore"` → `"Diamond ore"` via `name:gsub("^[%w_%-]+:", ""):gsub("_", " ")`.

## Other Files

- `farm/stock_monitor.lua` — monitors Create Stock Ticker (production flow history)
- `farm/packager_monitor.lua` — monitors Create Packager with entry/exit log
- `farm/farm_monitor.lua` — older central hub implementation (v3, for reference)
- `utils/diag.lua` — lists all connected peripherals and their methods (run to debug hardware)
- `turtle/send_test.lua` / `recv_test.lua` — wireless ping tests for diagnosing comms
