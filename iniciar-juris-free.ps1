# JURIS-FREE Bolivia — Inicializador de proyecto
# PowerShell 7+ | Sin CmdletBinding | Sin heredocs

param(
    [string]$Ruta = "C:\proyectos\juris-free"
)

$ErrorActionPreference = "Stop"

function OK   { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function PASO { param($m) Write-Host "`n--- $m ---" -ForegroundColor Cyan }
function WARN { param($m) Write-Host "  !! $m" -ForegroundColor Yellow }

Write-Host @"

  JURIS-FREE BOLIVIA
  Sistema Juridico Inteligente - Open Source
  Stack: Angular 17 + TypeScript + FastAPI + Cloudflare Workers

"@ -ForegroundColor Cyan

# ── 1. VERIFICAR HERRAMIENTAS ─────────────────────────────────────────────────
PASO "Verificando herramientas instaladas"

$herramientas = @("node","npm","python","git")
foreach ($h in $herramientas) {
    try {
        $ver = & $h --version 2>&1 | Select-Object -First 1
        OK "$h → $ver"
    } catch {
        WARN "$h no encontrado - instalalo antes de continuar"
    }
}

# ── 2. CREAR ESTRUCTURA DE DIRECTORIOS ────────────────────────────────────────
PASO "Creando estructura del proyecto en $Ruta"

$dirs = @(
    "frontend\src\app\core\services",
    "frontend\src\app\core\guards",
    "frontend\src\app\core\models",
    "frontend\src\app\features\chat",
    "frontend\src\app\features\library",
    "frontend\src\app\features\cases",
    "frontend\src\app\features\settings",
    "frontend\src\app\shared\components",
    "frontend\src\environments",
    "backend\api\routes",
    "backend\api\models",
    "backend\agents",
    "backend\ingestion",
    "workers\orchestrator\src",
    "workers\agent-civil\src",
    "workers\agent-penal\src",
    "workers\agent-laboral\src",
    "workers\shared",
    "infra\github-actions",
    "scripts",
    "data\raw",
    "data\processed",
    "data\embeddings",
    ".github\workflows"
)

foreach ($d in $dirs) {
    $path = Join-Path $Ruta $d
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}
OK "Estructura creada ($($dirs.Count) directorios)"

# ── 3. INSTALAR ANGULAR CLI + WRANGLER ────────────────────────────────────────
PASO "Instalando herramientas globales npm"

$paquetes = @(
    @{ nombre = "Angular CLI 17"; pkg = "@angular/cli@17" },
    @{ nombre = "Wrangler (Cloudflare)"; pkg = "wrangler" },
    @{ nombre = "TypeScript"; pkg = "typescript" }
)

foreach ($p in $paquetes) {
    Write-Host "  Instalando $($p.nombre)..." -NoNewline
    npm install -g $p.pkg --silent 2>&1 | Out-Null
    Write-Host " listo" -ForegroundColor Green
}

# ── 4. CREAR PROYECTO ANGULAR ─────────────────────────────────────────────────
PASO "Creando proyecto Angular 17"

$frontendPath = Join-Path $Ruta "frontend"

if (Test-Path (Join-Path $frontendPath "package.json")) {
    WARN "Angular ya existe en $frontendPath, saltando..."
} else {
    Set-Location $Ruta
    Write-Host "  Ejecutando: ng new juris-free-app (puede tardar 2-3 min)..."
    ng new juris-free-app `
        --directory frontend `
        --routing true `
        --style scss `
        --strict true `
        --skip-git true `
        --standalone true `
        --skip-tests false 2>&1 | Where-Object { $_ -match "CREATE|UPDATE|error" }
    OK "Proyecto Angular creado"
}

# ── 5. INSTALAR DEPENDENCIAS ANGULAR ──────────────────────────────────────────
PASO "Instalando dependencias Angular"

Set-Location $frontendPath

$deps = "@supabase/supabase-js @angular/material @angular/cdk marked dompurify @types/dompurify highlight.js"
$devDeps = "@types/node tailwindcss postcss autoprefixer"

Write-Host "  Instalando dependencias de produccion..."
npm install $deps.Split(" ") --save --silent 2>&1 | Out-Null
OK "Dependencias instaladas"

Write-Host "  Instalando dependencias de desarrollo..."
npm install $devDeps.Split(" ") --save-dev --silent 2>&1 | Out-Null
OK "Dev dependencies instaladas"

Write-Host "  Agregando PWA support..."
ng add @angular/pwa --skip-confirmation 2>&1 | Out-Null
OK "PWA configurado"

Set-Location $Ruta

# ── 6. GENERAR ARCHIVOS DE CONFIGURACION ──────────────────────────────────────
PASO "Generando archivos de configuracion"

# Environment desarrollo
$envDev = @(
    "// src/environments/environment.ts",
    "export const environment = {",
    "  production: false,",
    "  apiUrl: 'http://localhost:8000',",
    "  supabaseUrl: 'TU_SUPABASE_URL',",
    "  supabaseAnonKey: 'TU_SUPABASE_ANON_KEY',",
    "  cfWorkerUrl: 'https://juris-free.TU_SUBDOMINIO.workers.dev'",
    "};"
)
Set-Content -Path "$frontendPath\src\environments\environment.ts" -Value $envDev
OK "environment.ts creado"

# Environment produccion
$envProd = @(
    "// src/environments/environment.production.ts",
    "export const environment = {",
    "  production: true,",
    "  apiUrl: 'https://TU_IP_ORACLE_VM',",
    "  supabaseUrl: 'TU_SUPABASE_URL',",
    "  supabaseAnonKey: 'TU_SUPABASE_ANON_KEY',",
    "  cfWorkerUrl: 'https://juris-free.TU_SUBDOMINIO.workers.dev'",
    "};"
)
Set-Content -Path "$frontendPath\src\environments\environment.production.ts" -Value $envProd
OK "environment.production.ts creado"

# Tailwind config
$tailwind = @(
    "/** @type {import('tailwindcss').Config} */",
    "module.exports = {",
    "  content: ['./src/**/*.{html,ts,scss}'],",
    "  theme: {",
    "    extend: {",
    "      colors: {",
    "        juris: {",
    "          primary: '#1a3a5c',",
    "          accent:  '#c4922a',",
    "          bg:      '#f8f6f1'",
    "        }",
    "      }",
    "    }",
    "  },",
    "  plugins: []",
    "}"
)
Set-Content -Path "$frontendPath\tailwind.config.js" -Value $tailwind
OK "tailwind.config.js creado"

# .env.example
$envExample = @(
    "# JURIS-FREE Bolivia — Variables de entorno",
    "# Copiar a .env y completar. NUNCA subir .env al repo.",
    "",
    "# APIs LLM Gratuitas",
    "GEMINI_API_KEY=        # https://aistudio.google.com/app/apikey",
    "GROQ_API_KEY=          # https://console.groq.com/keys",
    "CEREBRAS_API_KEY=      # https://cloud.cerebras.ai/platform",
    "OPENROUTER_API_KEY=    # https://openrouter.ai/keys",
    "SAMBANOVA_API_KEY=     # https://cloud.sambanova.ai/apis",
    "",
    "# Supabase",
    "SUPABASE_URL=          # https://app.supabase.com -> Project Settings -> API",
    "SUPABASE_ANON_KEY=     # Clave publica (safe para frontend)",
    "SUPABASE_SERVICE_KEY=  # Clave privada (SOLO backend)",
    "",
    "# Oracle VM",
    "ORACLE_VM_URL=         # URL publica via Cloudflare Tunnel",
    "",
    "# Cloudflare",
    "CF_API_TOKEN=          # https://dash.cloudflare.com/profile/api-tokens",
    "CF_ACCOUNT_ID=         # Dashboard Cloudflare -> Account ID",
    "",
    "# Vercel",
    "VERCEL_TOKEN=          # https://vercel.com/account/tokens"
)
Set-Content -Path "$Ruta\.env.example" -Value $envExample
OK ".env.example creado"

# .gitignore
$gitignore = @(
    ".env",
    "*.pem",
    "node_modules/",
    "dist/",
    ".angular/",
    "__pycache__/",
    "*.pyc",
    "venv/",
    "data/embeddings/*.faiss",
    "data/raw/*.pdf",
    ".wrangler/",
    ".DS_Store"
)
Set-Content -Path "$Ruta\.gitignore" -Value $gitignore
OK ".gitignore creado"

# ── 7. GITHUB ACTIONS KEEP-ALIVE ──────────────────────────────────────────────
PASO "Configurando GitHub Actions (keep-alive anti-pausa)"

$keepAlive = @(
    "name: Keep-Alive Services",
    "on:",
    "  schedule:",
    "    - cron: '0 9 */5 * *'",
    "  workflow_dispatch:",
    "jobs:",
    "  ping:",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - name: Ping Supabase",
    "        run: |",
    "          curl -s `"`${{ secrets.SUPABASE_URL }}/rest/v1/`" \",
    "            -H `"apikey: `${{ secrets.SUPABASE_ANON_KEY }}`"",
    "          echo Supabase OK",
    "      - name: Ping Oracle VM",
    "        run: |",
    "          curl -s `"`${{ secrets.ORACLE_VM_URL }}/health`" || true",
    "          echo Oracle VM ping enviado"
)
Set-Content -Path "$Ruta\.github\workflows\keep-alive.yml" -Value $keepAlive
OK "keep-alive.yml creado"

# ── 8. REQUIREMENTS PYTHON ────────────────────────────────────────────────────
PASO "Configurando backend Python"

$requirements = @(
    "fastapi==0.115.0",
    "uvicorn[standard]==0.32.0",
    "httpx==0.27.2",
    "pydantic==2.9.2",
    "supabase==2.9.1",
    "sentence-transformers==3.2.1",
    "numpy==1.26.4",
    "python-dotenv==1.0.1"
)
Set-Content -Path "$Ruta\backend\requirements.txt" -Value $requirements
OK "requirements.txt creado"

# ── 9. WRANGLER CONFIG PARA WORKERS ───────────────────────────────────────────
PASO "Configurando Cloudflare Workers"

$wrangler = @(
    "name = `"juris-free-orchestrator`"",
    "main = `"src/index.ts`"",
    "compatibility_date = `"2024-11-01`"",
    "",
    "[vars]",
    "ENVIRONMENT = `"production`"",
    "",
    "[ai]",
    "binding = `"AI`""
)
Set-Content -Path "$Ruta\workers\orchestrator\wrangler.toml" -Value $wrangler
OK "wrangler.toml creado"

# ── 10. SCRIPT DE OBTENCION DE API KEYS ───────────────────────────────────────
PASO "Generando script de API keys"

$apiKeysScript = @(
    "# scripts/get-api-keys.ps1",
    "# Guia interactiva para obtener las 5 API keys gratuitas",
    "",
    "Write-Host 'JURIS-FREE Bolivia - Obtencion de API Keys Gratuitas' -ForegroundColor Cyan",
    "",
    "`$apis = @(",
    "  @{ Nombre='Gemini (Google)'; URL='https://aistudio.google.com/app/apikey'; Var='GEMINI_API_KEY' },",
    "  @{ Nombre='Groq (Llama 3.3)'; URL='https://console.groq.com/keys'; Var='GROQ_API_KEY' },",
    "  @{ Nombre='Cerebras'; URL='https://cloud.cerebras.ai/platform'; Var='CEREBRAS_API_KEY' },",
    "  @{ Nombre='OpenRouter'; URL='https://openrouter.ai/keys'; Var='OPENROUTER_API_KEY' },",
    "  @{ Nombre='SambaNova'; URL='https://cloud.sambanova.ai/apis'; Var='SAMBANOVA_API_KEY' }",
    ")",
    "",
    "foreach (`$api in `$apis) {",
    "  Write-Host `"`nProveedor: `$(`$api.Nombre)`" -ForegroundColor Yellow",
    "  Write-Host `"  URL: `$(`$api.URL)`"",
    "  `$abrir = Read-Host '  Abrir en navegador? (s/n)'",
    "  if (`$abrir -eq 's') { Start-Process `$api.URL }",
    "  `$key = Read-Host '  Pega tu API key (Enter para saltar)'",
    "  if (`$key) {",
    "    Add-Content -Path '.env' -Value `"`$(`$api.Var)=`$key`"",
    "    Write-Host '  Guardado en .env' -ForegroundColor Green",
    "  }",
    "}",
    "Write-Host '`nListo! Revisa tu .env' -ForegroundColor Green"
)
Set-Content -Path "$Ruta\scripts\get-api-keys.ps1" -Value $apiKeysScript
OK "get-api-keys.ps1 creado"

# ── RESUMEN FINAL ─────────────────────────────────────────────────────────────
Write-Host @"

===============================================================
  JURIS-FREE Bolivia configurado exitosamente
===============================================================

  Proximos pasos:
  1. cd $Ruta
  2. .\scripts\get-api-keys.ps1     Obtener API keys gratuitas
  3. cd frontend && ng serve         Dev server Angular (puerto 4200)
  4. cd backend && pip install -r requirements.txt
     uvicorn api.main:app --reload   Backend FastAPI (puerto 8000)

  Servicios a crear (gratuitos):
  - Supabase:     https://supabase.com
  - Oracle Cloud: https://cloud.oracle.com/free
  - Cloudflare:   https://dash.cloudflare.com
  - Vercel:       https://vercel.com
  - Neo4j Aura:   https://console.neo4j.io

===============================================================
"@ -ForegroundColor Green
