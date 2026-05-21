param([string]$Ruta = "C:\proyectos\juris-free")

Write-Host "`n  JURIS-FREE Bolivia — Iniciando sistema...`n" -ForegroundColor Cyan

Write-Host "  -> Backend FastAPI (puerto 8001)..." -ForegroundColor Cyan
Start-Process pwsh -ArgumentList @(
    "-NoExit",
    "-Command",
    "cd '$Ruta\backend'; .\venv\Scripts\Activate.ps1; uvicorn api.main:app --reload --port 8001"
)

Start-Sleep -Seconds 4

Write-Host "  -> Frontend Angular (puerto 4200)..." -ForegroundColor Cyan
Start-Process pwsh -ArgumentList @(
    "-NoExit",
    "-Command",
    "cd '$Ruta\frontend'; ng serve --open"
)

Write-Host @"

  Backend:  http://localhost:8001
  Frontend: http://localhost:4200
  API docs: http://localhost:8001/docs

"@ -ForegroundColor Green