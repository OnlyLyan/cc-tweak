-- update.lua
-- Sincroniza todos os arquivos com o repositorio GitHub
-- Baixa atualizacoes, substitui locais e remove arquivos deletados do repo
-- Use: update

local REPO   = "OnlyLyan/cc-tweak"
local BRANCH = "main"
local API    = "https://api.github.com/repos/"..REPO.."/git/trees/"..BRANCH.."?recursive=1"
local RAW    = "https://raw.githubusercontent.com/"..REPO.."/"..BRANCH.."/"

-- Arquivos locais que nunca devem ser deletados (gerados localmente)
local PROTEGIDOS = {
    ["startup.lua"]    = true,  -- GPS host ou startup customizado
    ["update.lua"]     = true,  -- este proprio script
    ["farms.cfg"]      = true,  -- config gerada pelo farm monitor
}

-- ============================================================
local function cls() term.clear(); term.setCursorPos(1,1) end

local function status(msg, cor)
    term.setTextColor(cor or colors.white)
    print(msg)
    term.setTextColor(colors.white)
end

-- Lista todos os arquivos locais recursivamente
local function listarLocais(dir, lista)
    lista = lista or {}
    local ok, items = pcall(fs.list, dir)
    if not ok then return lista end
    for _, nome in ipairs(items) do
        local caminho = dir == "" and nome or dir.."/"..nome
        if fs.isDir(caminho) then
            listarLocais(caminho, lista)
        else
            lista[#lista+1] = caminho
        end
    end
    return lista
end

-- Baixa um arquivo do GitHub e salva localmente
local function baixar(caminho)
    local url = RAW..caminho
    local resp = http.get(url)
    if not resp then return false, "falha HTTP" end
    local conteudo = resp.readAll()
    resp.close()

    -- Cria diretorios intermediarios se necessario
    local dir = fs.getDir(caminho)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local f = fs.open(caminho, "w")
    if not f then return false, "nao foi possivel escrever" end
    f.write(conteudo)
    f.close()
    return true
end

-- ============================================================
-- MAIN
-- ============================================================

cls()
print("=== Atualizador GitHub ===")
print("Repo: "..REPO)
print()

-- 1. Verifica HTTP
if not http then
    status("[ERRO] HTTP desabilitado. Ative no config do servidor.", colors.red)
    return
end

-- 2. Busca lista de arquivos via GitHub API
status("Buscando lista de arquivos...", colors.yellow)
local resp = http.get(API, {["User-Agent"]="CC-Tweaked"})
if not resp then
    status("[ERRO] Nao foi possivel contatar GitHub.", colors.red)
    return
end

local json = resp.readAll()
resp.close()

local data = textutils.unserialiseJSON(json)
if not data or not data.tree then
    status("[ERRO] Resposta invalida da API.", colors.red)
    return
end

-- 3. Filtra apenas arquivos (blobs), ignora diretorios e nao-.lua
local remotos = {}
local remotoSet = {}
for _, item in ipairs(data.tree) do
    if item.type == "blob" then
        -- Ignora arquivos que nao sao relevantes para o jogo
        local ext = item.path:match("%.(%w+)$")
        if ext == "lua" or ext == "cfg" then
            remotos[#remotos+1] = item.path
            remotoSet[item.path] = true
        end
    end
end

status(string.format("Arquivos no repo: %d", #remotos), colors.white)
print()

-- 4. Baixa e atualiza todos os arquivos remotos
local ok_count, err_count = 0, 0
for _, caminho in ipairs(remotos) do
    io.write("  "..caminho.."... ")
    local ok, err = baixar(caminho)
    if ok then
        term.setTextColor(colors.green)
        print("OK")
        ok_count = ok_count + 1
    else
        term.setTextColor(colors.red)
        print("ERRO: "..(err or "?"))
        err_count = err_count + 1
    end
    term.setTextColor(colors.white)
end

print()

-- 5. Remove arquivos locais que nao existem mais no repo
status("Verificando arquivos obsoletos...", colors.yellow)
local locais = listarLocais("")
local deletados = 0

for _, caminho in ipairs(locais) do
    local ext = caminho:match("%.(%w+)$")
    if (ext == "lua" or ext == "cfg")
        and not remotoSet[caminho]
        and not PROTEGIDOS[caminho]
        and not PROTEGIDOS[fs.getName(caminho)]
    then
        fs.delete(caminho)
        term.setTextColor(colors.orange)
        print("  Removido: "..caminho)
        term.setTextColor(colors.white)
        deletados = deletados + 1
    end
end

if deletados == 0 then
    print("  Nenhum arquivo obsoleto.")
end

-- 6. Resumo
print()
term.setTextColor(colors.green)
print(string.format("Atualizados: %d", ok_count))
term.setTextColor(colors.white)
if err_count > 0 then
    term.setTextColor(colors.red)
    print(string.format("Erros:       %d", err_count))
    term.setTextColor(colors.white)
end
if deletados > 0 then
    term.setTextColor(colors.orange)
    print(string.format("Removidos:   %d", deletados))
    term.setTextColor(colors.white)
end
print()
print("Concluido.")
