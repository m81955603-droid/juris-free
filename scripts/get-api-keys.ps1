# scripts/get-api-keys.ps1
# Guia interactiva para obtener las 5 API keys gratuitas

Write-Host 'JURIS-FREE Bolivia - Obtencion de API Keys Gratuitas' -ForegroundColor Cyan

$apis = @(
  @{ Nombre='Gemini (Google)'; URL='https://aistudio.google.com/app/apikey'; Var='GEMINI_API_KEY' },
  @{ Nombre='Groq (Llama 3.3)'; URL='https://console.groq.com/keys'; Var='GROQ_API_KEY' },
  @{ Nombre='Cerebras'; URL='https://cloud.cerebras.ai/platform'; Var='CEREBRAS_API_KEY' },
  @{ Nombre='OpenRouter'; URL='https://openrouter.ai/keys'; Var='OPENROUTER_API_KEY' },
  @{ Nombre='SambaNova'; URL='https://cloud.sambanova.ai/apis'; Var='SAMBANOVA_API_KEY' }
)

foreach ($api in $apis) {
  Write-Host "
Proveedor: $($api.Nombre)" -ForegroundColor Yellow
  Write-Host "  URL: $($api.URL)"
  $abrir = Read-Host '  Abrir en navegador? (s/n)'
  if ($abrir -eq 's') { Start-Process $api.URL }
  $key = Read-Host '  Pega tu API key (Enter para saltar)'
  if ($key) {
    Add-Content -Path '.env' -Value "$($api.Var)=$key"
    Write-Host '  Guardado en .env' -ForegroundColor Green
  }
}
Write-Host '
Listo! Revisa tu .env' -ForegroundColor Green
