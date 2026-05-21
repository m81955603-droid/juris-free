# Arrancar entorno de desarrollo completo
param([switch]$BackendOnly, [switch]$FrontendOnly)

Write-Host 'JURIS-FREE Bolivia — Entorno de desarrollo' -ForegroundColor Cyan

if (-not $FrontendOnly) {
    Write-Host 'Iniciando Backend FastAPI (puerto 8000)...' -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList '-NoExit','-Command','cd backend; pip install -r requirements.txt -q; uvicorn api.main:app --reload --port 8000' -WorkingDirectory 'C:\proyectos\juris-free'
}

if (-not $BackendOnly) {
    Write-Host 'Iniciando Frontend Angular (puerto 4200)...' -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList '-NoExit','-Command','cd frontend; ng serve --open' -WorkingDirectory 'C:\proyectos\juris-free'
}

Write-Host ''
Write-Host 'Servicios iniciando:' -ForegroundColor Green
Write-Host '  Frontend: http://localhost:4200' -ForegroundColor White
Write-Host '  Backend:  http://localhost:8000' -ForegroundColor White
Write-Host '  API docs: http://localhost:8000/docs' -ForegroundColor White
