# ==============================================================================
# Script de Desinstalacion y Limpieza (PowerShell) - Bodega Peirano
# ==============================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   LIMPIEZA DE RECURSOS: BODEGA PEIRANO MICROSERVICIOS         " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

Write-Host "`n[1/3] Eliminando namespace y aplicaciones bodega-peirano..." -ForegroundColor Yellow
kubectl delete namespace bodega-peirano --ignore-not-found=true

$resp = Read-Host "Desea tambien desinstalar Prometheus y Grafana (namespace monitoring)? [s/N]"
if ($resp -match "^[sSyY]$") {
    Write-Host "`n[2/3] Desinstalando stack kube-prometheus-stack..." -ForegroundColor Yellow
    helm uninstall prometheus -n monitoring
    kubectl delete namespace monitoring --ignore-not-found=true
} else {
    Write-Host "Omitiendo desinstalacion de Prometheus y Grafana." -ForegroundColor Gray
}

Write-Host "`n[OK] Limpieza completada exitosamente." -ForegroundColor Green
