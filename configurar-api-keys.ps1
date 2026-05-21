# JURIS-FREE Bolivia — Setup completo de API keys + .env
# Ejecutar desde: C:\proyectos\juris-free
# PowerShell 7+ | Guia interactiva paso a paso

param(
    [string]$Ruta = "C:\proyectos\juris-free"
)

$ErrorActionPreference = "Continue"

function Titulo  { param($m) Write-Host "`n$m" -ForegroundColor Cyan }
function OK      { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function WARN    { param($m) Write-Host "  !!  $m" -ForegroundColor Yellow }
function INFO    { param($m) Write-Host "  ->  $m" -ForegroundColor White }
function ESPACIO { Write-Host "" }

# ─────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────
Clear-Host
Write-Host @"
╔══════════════════════════════════════════════════════╗
║   JURIS-FREE Bolivia — Configuracion de API Keys     ║
║   5 proveedores LLM gratuitos | ~100M tokens/mes     ║
╚══════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host "  Este script:" -ForegroundColor White
Write-Host "   1. Te guia para obtener cada API key gratuita" -ForegroundColor Gray
Write-Host "   2. Verifica que cada key funciona" -ForegroundColor Gray
Write-Host "   3. Genera tu archivo .env completo" -ForegroundColor Gray
Write-Host "   4. Configura el entorno listo para usar" -ForegroundColor Gray
ESPACIO
Write-Host "  Tiempo estimado: 20-25 minutos" -ForegroundColor DarkCyan
Write-Host "  Costo total: USD 0.00" -ForegroundColor DarkCyan
ESPACIO
Read-Host "  Presiona Enter para comenzar"

# ─────────────────────────────────────────────
# VERIFICAR DIRECTORIO
# ─────────────────────────────────────────────
if (-not (Test-Path $Ruta)) {
    New-Item -ItemType Directory -Path $Ruta -Force | Out-Null
    OK "Directorio creado: $Ruta"
}

Set-Location $Ruta

# ─────────────────────────────────────────────
# FUNCION: Verificar API key con llamada real
# ─────────────────────────────────────────────
function Test-GeminiKey {
    param([string]$key)
    try {
        $body = @{
            contents = @(@{ parts = @(@{ text = "Responde solo: OK" }) })
            generationConfig = @{ maxOutputTokens = 5 }
        } | ConvertTo-Json -Depth 5
        $url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$key"
        $resp = Invoke-RestMethod -Uri $url -Method POST -Body $body -ContentType "application/json" -TimeoutSec 15
        return $resp.candidates -ne $null
    } catch { return $false }
}

function Test-OpenAICompatibleKey {
    param([string]$key, [string]$url, [string]$model)
    try {
        $headers = @{ "Authorization" = "Bearer $key"; "Content-Type" = "application/json" }
        $body = @{
            model = $model
            messages = @(@{ role = "user"; content = "Responde solo: OK" })
            max_tokens = 5
        } | ConvertTo-Json -Depth 5
        $resp = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $body -TimeoutSec 15
        return $resp.choices -ne $null
    } catch { return $false }
}

# ─────────────────────────────────────────────
# DEFINICION DE PROVEEDORES
# ─────────────────────────────────────────────
$proveedores = @(
    @{
        Nombre    = "Google Gemini 2.5 Flash"
        EnvVar    = "GEMINI_API_KEY"
        Prioridad = 1
        URL       = "https://aistudio.google.com/app/apikey"
        Modelo    = "gemini-2.5-flash"
        Limite    = "1,500 req/dia | 1M contexto | 0 costo"
        Pasos     = @(
            "Abrir: https://aistudio.google.com/app/apikey",
            "Iniciar sesion con tu cuenta Gmail",
            "Hacer clic en 'Create API key'",
            "Seleccionar 'Create API key in new project'",
            "Copiar la clave (empieza con AIza...)"
        )
        TestFn    = { param($k) Test-GeminiKey $k }
        PrefixHint = "AIza"
    },
    @{
        Nombre    = "Groq — Llama 3.3 70B (el mas rapido)"
        EnvVar    = "GROQ_API_KEY"
        Prioridad = 2
        URL       = "https://console.groq.com/keys"
        Modelo    = "llama-3.3-70b-versatile"
        Limite    = "14,400 req/dia | 315 tokens/seg | 0 costo"
        Pasos     = @(
            "Abrir: https://console.groq.com",
            "Sign Up con email o GitHub",
            "Ir a seccion 'API Keys'",
            "Hacer clic en 'Create API Key'",
            "Copiar la clave (empieza con gsk_...)"
        )
        TestFn    = { param($k) Test-OpenAICompatibleKey $k "https://api.groq.com/openai/v1/chat/completions" "llama-3.3-70b-versatile" }
        PrefixHint = "gsk_"
    },
    @{
        Nombre    = "Cerebras — Mayor volumen de tokens"
        EnvVar    = "CEREBRAS_API_KEY"
        Prioridad = 3
        URL       = "https://cloud.cerebras.ai/platform"
        Modelo    = "llama3.3-70b"
        Limite    = "~1M tokens/dia | Sin limite de req | 0 costo"
        Pasos     = @(
            "Abrir: https://cloud.cerebras.ai/platform",
            "Registrarse con email",
            "Verificar email (revisar bandeja de entrada)",
            "Ir a 'API Keys' en el dashboard",
            "Crear nueva API key y copiarla"
        )
        TestFn    = { param($k) Test-OpenAICompatibleKey $k "https://api.cerebras.ai/v1/chat/completions" "llama3.3-70b" }
        PrefixHint = "csk-"
    },
    @{
        Nombre    = "OpenRouter — 30+ modelos gratuitos"
        EnvVar    = "OPENROUTER_API_KEY"
        Prioridad = 4
        URL       = "https://openrouter.ai/keys"
        Modelo    = "qwen/qwen-2.5-72b-instruct:free"
        Limite    = "200 req/dia modelos :free | Sin costo"
        Pasos     = @(
            "Abrir: https://openrouter.ai",
            "Sign Up con email o Google",
            "Ir a seccion 'Keys'",
            "Crear nueva key y copiarla (empieza con sk-or-...)",
            "NOTA: usar modelos con sufijo ':free' para costo 0"
        )
        TestFn    = { param($k) Test-OpenAICompatibleKey $k "https://openrouter.ai/api/v1/chat/completions" "qwen/qwen-2.5-72b-instruct:free" }
        PrefixHint = "sk-or-"
    },
    @{
        Nombre    = "SambaNova — DeepSeek V3 / Llama 4"
        EnvVar    = "SAMBANOVA_API_KEY"
        Prioridad = 5
        URL       = "https://cloud.sambanova.ai/apis"
        Modelo    = "Meta-Llama-3.3-70B-Instruct"
        Limite    = "~1M tokens/dia | Velocidad muy alta"
        Pasos     = @(
            "Abrir: https://cloud.sambanova.ai",
            "Sign Up (acepta email personal o empresarial)",
            "Verificar cuenta por email",
            "Ir a 'API' en el dashboard",
            "Generar API key y copiarla"
        )
        TestFn    = { param($k) Test-OpenAICompatibleKey $k "https://api.sambanova.ai/v1/chat/completions" "Meta-Llama-3.3-70B-Instruct" }
        PrefixHint = "sn-"
    }
)

# ─────────────────────────────────────────────
# RECOLECTAR KEYS
# ─────────────────────────────────────────────
$keysObtenidas = @{}
$keysVerificadas = @{}

foreach ($p in $proveedores) {
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Proveedor $($p.Prioridad) de 5: $($p.Nombre.PadRight(35))  ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    ESPACIO

    Write-Host "  Limite gratuito:" -ForegroundColor DarkCyan
    Write-Host "  $($p.Limite)" -ForegroundColor White
    ESPACIO

    Write-Host "  Pasos para obtener la key:" -ForegroundColor DarkCyan
    $i = 1
    foreach ($paso in $p.Pasos) {
        Write-Host "  $i. $paso" -ForegroundColor Gray
        $i++
    }
    ESPACIO

    # Ofrecer abrir el navegador
    $abrir = Read-Host "  Abrir en el navegador ahora? (s/n)"
    if ($abrir -eq 's' -or $abrir -eq 'S') {
        Start-Process $p.URL
        Write-Host "  Navegador abierto. Vuelve aqui cuando tengas la key." -ForegroundColor DarkCyan
        ESPACIO
    }

    # Pedir la key
    $intentos = 0
    $keyValida = $false

    while (-not $keyValida -and $intentos -lt 3) {
        $key = Read-Host "  Pega tu API key de $($p.Nombre.Split('—')[0].Trim()) (Enter para saltar)"

        if ([string]::IsNullOrWhiteSpace($key)) {
            WARN "Saltando $($p.Nombre) — podras agregarla manualmente al .env despues"
            break
        }

        # Validacion basica de formato
        $key = $key.Trim()
        if ($key.Length -lt 20) {
            WARN "La key parece muy corta. Las keys validas tienen al menos 20 caracteres."
            $intentos++
            continue
        }

        # Verificar con llamada real
        Write-Host "  Verificando key con $($p.Nombre)..." -ForegroundColor DarkCyan
        try {
            $resultado = & $p.TestFn $key
            if ($resultado) {
                OK "Key verificada con exito — $($p.Nombre) responde correctamente"
                $keysObtenidas[$p.EnvVar] = $key
                $keysVerificadas[$p.EnvVar] = $true
                $keyValida = $true
            } else {
                WARN "La key no funciono. Verifica que la copiaste completa."
                $intentos++
            }
        } catch {
            # Si la verificacion falla por red, guardar igual
            WARN "No se pudo verificar (problema de red). Guardando key sin verificar."
            $keysObtenidas[$p.EnvVar] = $key
            $keysVerificadas[$p.EnvVar] = $false
            $keyValida = $true
        }
    }

    if ($intentos -ge 3) {
        WARN "Demasiados intentos fallidos. Saltando este proveedor."
    }

    ESPACIO
}

# ─────────────────────────────────────────────
# SUPABASE
# ─────────────────────────────────────────────
Clear-Host
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  Base de datos: Supabase (PostgreSQL + pgvector)     ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Magenta
ESPACIO
Write-Host "  Supabase es tu base de datos gratuita:" -ForegroundColor White
Write-Host "  - PostgreSQL con extension pgvector (busqueda semantica)" -ForegroundColor Gray
Write-Host "  - Autenticacion con Google OAuth integrada" -ForegroundColor Gray
Write-Host "  - 500MB gratis | 50,000 usuarios activos/mes" -ForegroundColor Gray
Write-Host "  - IMPORTANTE: el proyecto se pausa tras 7 dias sin uso" -ForegroundColor Yellow
Write-Host "    (el GitHub Actions keep-alive lo previene automaticamente)" -ForegroundColor Gray
ESPACIO

$abrirSupabase = Read-Host "  Abrir Supabase en el navegador? (s/n)"
if ($abrirSupabase -eq 's' -or $abrirSupabase -eq 'S') {
    Start-Process "https://supabase.com"
    ESPACIO
    Write-Host "  Pasos en Supabase:" -ForegroundColor DarkCyan
    Write-Host "  1. Sign Up con GitHub o email" -ForegroundColor Gray
    Write-Host "  2. 'New Project' -> nombre: juris-free-bolivia" -ForegroundColor Gray
    Write-Host "  3. Elegir region: us-east-1 (la mas cercana con free tier)" -ForegroundColor Gray
    Write-Host "  4. Anotar la password de la base de datos (la necesitaras)" -ForegroundColor Gray
    Write-Host "  5. Esperar ~2 min a que el proyecto se cree" -ForegroundColor Gray
    Write-Host "  6. Ir a: Project Settings -> API" -ForegroundColor Gray
    Write-Host "  7. Copiar 'Project URL' y 'anon public' key" -ForegroundColor Gray
    ESPACIO
}

$supabaseUrl = Read-Host "  Pega tu Supabase Project URL (https://xxxx.supabase.co)"
$supabaseAnon = Read-Host "  Pega tu Supabase anon key (empieza con eyJ...)"
$supabaseService = Read-Host "  Pega tu Supabase service_role key (empieza con eyJ... es diferente a la anon)"

if ($supabaseUrl) { $keysObtenidas["SUPABASE_URL"] = $supabaseUrl.Trim() }
if ($supabaseAnon) { $keysObtenidas["SUPABASE_ANON_KEY"] = $supabaseAnon.Trim() }
if ($supabaseService) { $keysObtenidas["SUPABASE_SERVICE_KEY"] = $supabaseService.Trim() }

# ─────────────────────────────────────────────
# GENERAR ARCHIVO .env
# ─────────────────────────────────────────────
Clear-Host
Titulo "Generando archivo .env"

$envPath = Join-Path $Ruta ".env"
$envLines = @(
    "# JURIS-FREE Bolivia — Variables de entorno",
    "# Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "# NUNCA subir este archivo al repositorio",
    "",
    "# ── APIs LLM Gratuitas ─────────────────────────────────────",
    "# Prioridad de uso: Gemini -> Groq -> Cerebras -> OpenRouter -> SambaNova",
    ""
)

$proveedores | ForEach-Object {
    $valor = if ($keysObtenidas.ContainsKey($_.EnvVar)) { $keysObtenidas[$_.EnvVar] } else { "" }
    $verificado = if ($keysVerificadas.ContainsKey($_.EnvVar) -and $keysVerificadas[$_.EnvVar]) { " # verificada OK" } else { "" }
    $limite = "# $($_.Limite)"
    $envLines += "$limite"
    $envLines += "$($_.EnvVar)=$valor$verificado"
    $envLines += ""
}

$envLines += @(
    "# ── Supabase ────────────────────────────────────────────────",
    "SUPABASE_URL=$(if ($keysObtenidas['SUPABASE_URL']) { $keysObtenidas['SUPABASE_URL'] } else { '' })",
    "SUPABASE_ANON_KEY=$(if ($keysObtenidas['SUPABASE_ANON_KEY']) { $keysObtenidas['SUPABASE_ANON_KEY'] } else { '' })",
    "SUPABASE_SERVICE_KEY=$(if ($keysObtenidas['SUPABASE_SERVICE_KEY']) { $keysObtenidas['SUPABASE_SERVICE_KEY'] } else { '' })",
    "",
    "# ── Oracle Cloud VM ──────────────────────────────────────────",
    "# Completar despues de crear la VM Oracle",
    "ORACLE_VM_URL=",
    "ORACLE_VM_IP=",
    "",
    "# ── Cloudflare ───────────────────────────────────────────────",
    "# Completar despues de crear cuenta Cloudflare",
    "CF_API_TOKEN=",
    "CF_ACCOUNT_ID=",
    "",
    "# ── Vercel ───────────────────────────────────────────────────",
    "VERCEL_TOKEN=",
    "VERCEL_PROJECT_ID=",
    "",
    "# ── Configuracion de la app ──────────────────────────────────",
    "ENVIRONMENT=development",
    "LOG_LEVEL=INFO",
    "PORT=8000",
    "CORS_ORIGINS=http://localhost:4200"
)

Set-Content -Path $envPath -Value $envLines -Encoding UTF8
OK ".env generado en: $envPath"

# ─────────────────────────────────────────────
# COPIAR .env AL FRONTEND Y BACKEND
# ─────────────────────────────────────────────
Titulo "Sincronizando configuracion"

# Generar environment.ts Angular con las Supabase keys reales
$supaUrl  = if ($keysObtenidas['SUPABASE_URL'])      { $keysObtenidas['SUPABASE_URL'] }      else { 'TU_SUPABASE_URL' }
$supaAnon = if ($keysObtenidas['SUPABASE_ANON_KEY']) { $keysObtenidas['SUPABASE_ANON_KEY'] } else { 'TU_SUPABASE_ANON_KEY' }

$envDev = @(
    "// src/environments/environment.ts — GENERADO AUTOMATICAMENTE",
    "// No editar manualmente. Regenerar con: .\scripts\get-api-keys.ps1",
    "export const environment = {",
    "  production: false,",
    "  apiUrl: 'http://localhost:8000',",
    "  supabaseUrl: '$supaUrl',",
    "  supabaseAnonKey: '$supaAnon',",
    "  cfWorkerUrl: 'http://localhost:8787'",
    "};"
)

$envDevPath = "$Ruta\frontend\src\environments\environment.ts"
if (Test-Path (Split-Path $envDevPath)) {
    Set-Content -Path $envDevPath -Value $envDev
    OK "environment.ts actualizado con keys reales de Supabase"
} else {
    WARN "frontend/src/environments/ no existe aun. Ejecuta primero iniciar-juris-free.ps1"
}

# ─────────────────────────────────────────────
# INSTALAR DEPENDENCIAS PYTHON BACKEND
# ─────────────────────────────────────────────
Titulo "Instalando dependencias del backend Python"

$reqPath = "$Ruta\backend\requirements.txt"
if (Test-Path $reqPath) {
    Write-Host "  Instalando paquetes Python (puede tardar 2-3 min)..." -ForegroundColor DarkCyan
    Set-Location "$Ruta\backend"

    # Crear entorno virtual si no existe
    if (-not (Test-Path "venv")) {
        Write-Host "  Creando entorno virtual Python..." -ForegroundColor DarkCyan
        python -m venv venv 2>&1 | Out-Null
        OK "Entorno virtual creado"
    }

    # Activar e instalar
    & ".\venv\Scripts\Activate.ps1" 2>&1 | Out-Null
    pip install -r requirements.txt -q 2>&1 | Out-Null
    OK "Dependencias Python instaladas"

    Set-Location $Ruta
} else {
    WARN "requirements.txt no encontrado. Ejecuta primero generar-codigo.ps1"
}

# ─────────────────────────────────────────────
# INSTALAR DEPENDENCIAS ANGULAR (si no estan)
# ─────────────────────────────────────────────
Titulo "Verificando dependencias Angular"

$packageJson = "$Ruta\frontend\package.json"
$nodeModules  = "$Ruta\frontend\node_modules"

if ((Test-Path $packageJson) -and -not (Test-Path $nodeModules)) {
    Write-Host "  Instalando node_modules (puede tardar 3-5 min)..." -ForegroundColor DarkCyan
    Set-Location "$Ruta\frontend"
    npm install --silent 2>&1 | Out-Null
    OK "node_modules instalados"
    Set-Location $Ruta
} elseif (Test-Path $nodeModules) {
    OK "node_modules ya instalados"
} else {
    WARN "frontend/package.json no encontrado. Ejecuta primero iniciar-juris-free.ps1"
}

# ─────────────────────────────────────────────
# VERIFICAR SQL SUPABASE
# ─────────────────────────────────────────────
Titulo "Schema SQL para Supabase"

$sqlPath = "$Ruta\infra\supabase\schema.sql"
if (Test-Path $sqlPath) {
    Write-Host "  El schema SQL esta listo en:" -ForegroundColor White
    Write-Host "  $sqlPath" -ForegroundColor DarkCyan
    ESPACIO
    Write-Host "  Para aplicarlo:" -ForegroundColor Yellow
    Write-Host "  1. Ir a: https://supabase.com/dashboard" -ForegroundColor Gray
    Write-Host "  2. Abrir tu proyecto -> SQL Editor" -ForegroundColor Gray
    Write-Host "  3. Copiar y pegar el contenido de schema.sql" -ForegroundColor Gray
    Write-Host "  4. Hacer clic en 'Run'" -ForegroundColor Gray
    ESPACIO

    $abrirSQL = Read-Host "  Abrir el archivo schema.sql ahora? (s/n)"
    if ($abrirSQL -eq 's' -or $abrirSQL -eq 'S') {
        Start-Process notepad.exe $sqlPath
    }
}

# ─────────────────────────────────────────────
# RESUMEN FINAL
# ─────────────────────────────────────────────
Clear-Host
Write-Host @"
╔══════════════════════════════════════════════════════╗
║         JURIS-FREE Bolivia — Configuracion lista     ║
╚══════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

ESPACIO
Write-Host "  RESUMEN DE API KEYS:" -ForegroundColor White
ESPACIO

$proveedores | ForEach-Object {
    $tiene = $keysObtenidas.ContainsKey($_.EnvVar) -and $keysObtenidas[$_.EnvVar]
    $verif = $keysVerificadas.ContainsKey($_.EnvVar) -and $keysVerificadas[$_.EnvVar]
    if ($tiene -and $verif) {
        Write-Host "  OK  $($_.Nombre)" -ForegroundColor Green
    } elseif ($tiene) {
        Write-Host "  ~   $($_.Nombre) (sin verificar)" -ForegroundColor Yellow
    } else {
        Write-Host "  --  $($_.Nombre) (pendiente)" -ForegroundColor DarkGray
    }
}

ESPACIO
Write-Host "  SUPABASE:" -ForegroundColor White
if ($keysObtenidas['SUPABASE_URL']) {
    OK "URL configurada: $($keysObtenidas['SUPABASE_URL'])"
} else {
    WARN "URL no configurada — agregar al .env manualmente"
}

ESPACIO
Write-Host "  ARCHIVOS GENERADOS:" -ForegroundColor White
INFO ".env                      → $Ruta\.env"
INFO "environment.ts            → $Ruta\frontend\src\environments\"
INFO "schema.sql (aplicar en Supabase) → $Ruta\infra\supabase\"

ESPACIO
Write-Host "  PARA ARRANCAR EL SISTEMA LOCAL:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Terminal 1 — Backend FastAPI:" -ForegroundColor White
Write-Host "    cd C:\proyectos\juris-free\backend" -ForegroundColor DarkCyan
Write-Host "    .\venv\Scripts\Activate.ps1" -ForegroundColor DarkCyan
Write-Host "    uvicorn api.main:app --reload --port 8000" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Terminal 2 — Frontend Angular:" -ForegroundColor White
Write-Host "    cd C:\proyectos\juris-free\frontend" -ForegroundColor DarkCyan
Write-Host "    ng serve --open" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Abrir en el celular (misma red WiFi):" -ForegroundColor White
Write-Host "    http://TU_IP_LOCAL:4200" -ForegroundColor DarkCyan

ESPACIO
Write-Host "  PENDIENTE PARA PRODUCCION:" -ForegroundColor Yellow
Write-Host "  - Aplicar schema.sql en Supabase Dashboard -> SQL Editor" -ForegroundColor Gray
Write-Host "  - Crear VM Oracle Cloud (guia: siguiente script)" -ForegroundColor Gray
Write-Host "  - Deploy Vercel + Cloudflare Workers" -ForegroundColor Gray

ESPACIO
$arrancar = Read-Host "  Arrancar el entorno local ahora? (s/n)"
if ($arrancar -eq 's' -or $arrancar -eq 'S') {

    # Arrancar backend en nueva ventana
    $backendCmd = "cd '$Ruta\backend'; .\venv\Scripts\Activate.ps1; uvicorn api.main:app --reload --port 8000"
    Start-Process pwsh -ArgumentList "-NoExit", "-Command", $backendCmd

    # Esperar 3 segundos y arrancar frontend
    Start-Sleep -Seconds 3
    $frontendCmd = "cd '$Ruta\frontend'; ng serve --open"
    Start-Process pwsh -ArgumentList "-NoExit", "-Command", $frontendCmd

    ESPACIO
    OK "Servidores iniciando..."
    Write-Host "  Backend:  http://localhost:8000" -ForegroundColor White
    Write-Host "  Frontend: http://localhost:4200  (abrira en el navegador)" -ForegroundColor White
    Write-Host "  API docs: http://localhost:8000/docs" -ForegroundColor White
}

ESPACIO
Write-Host "  Configuracion completada. JURIS-FREE Bolivia listo." -ForegroundColor Green
ESPACIO
