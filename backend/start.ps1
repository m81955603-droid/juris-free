# Arrancar backend FastAPI en modo desarrollo
Write-Host 'Iniciando JURIS-FREE Backend...' -ForegroundColor Cyan

# Crear .env si no existe
if (-not (Test-Path '.env')) {
    Copy-Item '..\env.example' '.env'
    Write-Host 'Crea el archivo .env con tus API keys' -ForegroundColor Yellow
}

# Instalar dependencias Python
pip install -r requirements.txt

# Iniciar servidor
uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
