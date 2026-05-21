# Design: Sistema de Estabilização Automática de Avião

**Data:** 2026-05-21  
**Modpack:** Skybound SMP (NeoForge 1.21.1)  
**Mods relevantes:** Create: Simulated/Aeronautics, CC:Tweaked, Create (Speed Controller)

---

## Contexto

Avião tipo quadcopter no Minecraft (Create: Aeronautics) com 4 hélices nos cantos. O peso desequilibrado faz a aeronave inclinar. O objetivo é nivelar automaticamente ajustando a velocidade de rotação de cada hélice individualmente, mantendo uma altitude alvo configurada pelo piloto.

---

## Arquitetura

### Componentes de hardware por canto (×4)

| Bloco | Função |
|---|---|
| CC Computer | Executa `corner.lua` |
| Altitude Sensor (Create: Simulated) | Lê altura Y do canto |
| Speed Controller (Create) | Controla RPM da hélice |
| Wireless Modem / Router | Comunicação rednet com os outros cantos e cockpit |

### Componente central (×1)

| Bloco | Função |
|---|---|
| CC Computer | Executa `cockpit.lua` |
| Wireless Modem | Comunicação rednet |

### Diagrama

```
[PC-FL] ←── rednet ──→ [PC-FR]
   ↕                       ↕
[PC-RL] ←── rednet ──→ [PC-RR]
         ↖           ↗
          [PC-COCKPIT]
```

---

## Arquivos

```
airplane/
  corner.lua    — programa dos 4 cantos (idêntico)
  cockpit.lua   — programa do PC central
  config.lua    — gerado automaticamente no primeiro boot
```

---

## Auto-detecção de Periféricos

No boot, `corner.lua` varre todos os periféricos conectados e os classifica **pelos métodos que expõem**, não pelo nome do mod:

| Métodos presentes | Classificação |
|---|---|
| `getHeight()` | Sensor de altitude |
| Qualquer método com "speed" ou "rpm" no nome (case-insensitive) | Speed Controller |
| `isWireless()` retorna `true` | Router rednet |
| `setSignal()` | Link analógico (atuador futuro) |
| `getAngles()` | Gimbal sensor (reservado para expansão) |

A detecção do Speed Controller usa `peripheral.getMethods()` e busca por padrão em vez de nome exato, pois o método varia conforme a versão do mod (pode ser `setTargetSpeed`, `setRPM`, `setSpeed`, etc.). O nome real do método detectado é salvo em `config.lua` no primeiro boot para evitar re-scan a cada reinicialização.

Se algum periférico obrigatório não for encontrado, o programa exibe erro descritivo e para. Periféricos não reconhecidos são ignorados com log.

---

## Protocolo de Comunicação (rednet)

### Canal `aviao_status` (corners → todos)
Frequência: 50 ms  
Payload: `{ corner = "FL", height = 64.5 }`

Cada corner transmite sua altura. Todos os outros cantos e o cockpit escutam.

### Canal `aviao_cmd` (cockpit → corners)
Frequência: 200 ms  
Payload: `{ target_alt = 80, enabled = true }`

O cockpit transmite a altitude alvo e se a estabilização está ativa. Na inicialização do cockpit, `target_alt` é definido como a média das alturas recebidas dos cantos nos primeiros 2s de escuta (se nenhum canto responder, usa 64 como padrão).

---

## Configuração (config.lua)

Gerado no primeiro boot via menu interativo:

```lua
return {
  corner           = "FL",              -- "FL" | "FR" | "RL" | "RR"
  base_speed       = 256,               -- RPM base de cruzeiro
  max_speed        = 512,               -- RPM máximo permitido
  kA               = 10,                -- ganho de altitude
  kP               = 5,                 -- ganho de pitch
  kR               = 5,                 -- ganho de roll
  channel          = 42,                -- canal rednet
  speed_method     = "setTargetSpeed",  -- detectado automaticamente no primeiro boot
}
```

Os ganhos `kA`, `kP`, `kR` são editáveis sem reescrever o programa — permite tunar o PID em voo.

---

## Lógica de Estabilização

Cada canto mantém uma tabela com as últimas alturas recebidas de todos os cantos (timeout de 2s → considera o canto offline). Com os 4 valores:

```
avg_front   = (FL + FR) / 2
avg_rear    = (RL + RR) / 2
avg_left    = (FL + RL) / 2
avg_right   = (FR + RR) / 2
avg_all     = (FL + FR + RL + RR) / 4

pitch_error = avg_front - avg_rear     -- > 0: frente alta
roll_error  = avg_left  - avg_right    -- > 0: esquerda alta
alt_error   = target_alt - avg_all     -- > 0: abaixo da meta
```

Multiplicadores de sinal por canto:

| Canto | pitch_sign | roll_sign |
|---|---|---|
| FL | -1 | -1 |
| FR | -1 | +1 |
| RL | +1 | -1 |
| RR | +1 | +1 |

Velocidade final:

```
speed = base_speed
      + kA × alt_error
      + kP × pitch_sign × pitch_error
      + kR × roll_sign  × roll_error

speed = clamp(speed, 0, max_speed)
```

Quando estabilização está desativada (`enabled = false`), o corner aplica apenas `base_speed` sem correção.

Se um ou mais cantos estiverem offline (sem dados recentes), os erros de pitch/roll são calculados com os cantos disponíveis. Se menos de 2 cantos estiverem ativos, a estabilização de atitude é suspensa e apenas `alt_error` é aplicado.

---

## Cockpit (cockpit.lua)

Terminal interativo exibido no monitor ou na tela do PC:

```
╔══════════════════════════════╗
║   AVIÃO — CONTROLE DE VOO   ║
╠══════════════════════════════╣
║ Altitude alvo:   80 blocos  ║
║ Altitude atual:  78.2       ║
║ Pitch:  +1.3°   Roll: -0.4° ║
╠══════════════════════════════╣
║ FL: 77.8   FR: 78.1         ║
║ RL: 78.6   RR: 78.4         ║
╠══════════════════════════════╣
║ [↑/↓] Altitude  [E] On/Off  ║
║ Estabilização: ATIVA        ║
╚══════════════════════════════╝
```

**Controles:**
- `↑` / `↓` — ajusta altitude alvo ±1 bloco
- `PgUp` / `PgDn` — ajusta altitude alvo ±10 blocos
- `E` — ativa/desativa estabilização
- `Q` — encerra o programa

---

## Setup (primeiro boot em cada canto)

1. Detecta periféricos automaticamente
2. Se `config.lua` não existe, exibe menu:
   ```
   Qual é o seu canto?
   [1] Frente-Esquerda (FL)
   [2] Frente-Direita  (FR)
   [3] Trás-Esquerda   (RL)
   [4] Trás-Direita    (RR)
   ```
3. Salva `config.lua`
4. Entra no loop principal

---

## Tratamento de Erros

| Situação | Comportamento |
|---|---|
| Periférico obrigatório ausente | Exibe erro descritivo, para |
| Canto offline >2s | Calcula correção com cantos disponíveis |
| <2 cantos disponíveis | Suspende pitch/roll, mantém só altitude |
| Speed Controller sem resposta | Log de erro, tenta novamente no próximo ciclo |
| Cockpit offline | Corners mantêm último `target_alt` recebido |

---

## Expansões Futuras (fora do escopo atual)

- Substituir Speed Controller por Create Aeronautics Thrusters (`setThrottle()`)
- Controle de heading (rumo) via NavTable (`getRelativeAngle()`)
- Controle de superfícies (ailerons via SwivelBearing)
- PID completo com derivativo para reduzir oscilação
