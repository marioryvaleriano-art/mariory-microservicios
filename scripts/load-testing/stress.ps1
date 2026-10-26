# ==============================================================================
# Script de Pruebas de Carga y Validación de Casuísticas (PowerShell) - Bodega Peirano
# ==============================================================================
param (
    [string]$HostTarget = ""
)

if ([string]::IsNullOrWhiteSpace($HostTarget)) {
    try {
        $HostTarget = (minikube ip 2>$null).Trim()
    } catch {
        $HostTarget = "127.0.0.1"
    }
}
if ([string]::IsNullOrWhiteSpace($HostTarget)) {
    $HostTarget = "127.0.0.1"
}

$CatalogoUrl = "http://${HostTarget}:30081"
$PedidosUrl = "http://${HostTarget}:30082"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "      BODEGA PEIRANO — GENERADOR DE CARGA Y CASUÍSTICAS         " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Catálogo API: $CatalogoUrl" -ForegroundColor Yellow
Write-Host "Pedidos API:  $PedidosUrl`n" -ForegroundColor Yellow

function Mostrar-Menu {
    Write-Host "Seleccione el escenario a ejecutar:" -ForegroundColor Yellow
    Write-Host "1) Flujo Normal de Pedidos (Compras exitosas, rotación de stock e ingresos)"
    Write-Host "2) Casuística de Negocio: Alta Tasa de Rechazo y Stock Agotado (Regla de negocio)"
    Write-Host "3) Casuística de Servicio Lento (Inyección de latencia y p95)"
    Write-Host "4) Casuística de Servicio Caído (Escalar Servicio A a 0 réplicas y validar)"
    Write-Host "5) Restaurar Servicio Caído (Escalar Servicio A a 1 réplica)"
    Write-Host "6) Ejecutar Suite Completa de Pruebas de Estrés (Mixta)"
    Write-Host "0) Salir"
    return Read-Host "Opción [1-6]"
}

function Flujo-Normal {
    Write-Host "`n>>> Generando 20 pedidos válidos variados..." -ForegroundColor Cyan
    $clientes = @("Restaurante Astrid y Gaston", "Hotel Westin Lima", "Bodega Don Jose", "Sommelier Carlos", "Lucia Bar")
    $vinos = @("VINO-001", "VINO-002", "VINO-003", "VINO-004")

    for ($i = 1; $i -le 20; $i++) {
        $cli = $clientes | Get-Random
        $vino = $vinos | Get-Random
        $cant = Get-Random -Minimum 1 -Maximum 4
        $body = @{
            cliente = $cli
            vinoId = $vino
            cantidad = $cant
        } | ConvertTo-Json

        try {
            $resp = Invoke-RestMethod -Uri "$PedidosUrl/api/pedidos" -Method Post -Body $body -ContentType "application/json"
            Write-Host "Pedido #$i: Estado = $($resp.estado) | Vino = $($resp.nombreVino) | Total = S/.$($resp.montoTotal)" -ForegroundColor Green
        } catch {
            Write-Host "Pedido #$i: Rechazado o Fallido" -ForegroundColor DarkYellow
        }
        Start-Sleep -Milliseconds 250
    }
    Write-Host "`n✔ Flujo normal finalizado. Revise paneles de Ingresos y Flujo en Grafana." -ForegroundColor Green
}

function Casuistica-Negocio {
    Write-Host "`n>>> Ejecutando Casuística de Negocio: Alta Tasa de Rechazos y Stock Agotado..." -ForegroundColor Cyan
    Write-Host "Enviando pedidos con cantidades excesivas (stock insuficiente) y vinos inexistentes..." -ForegroundColor Gray

    for ($i = 1; $i -le 30; $i++) {
        if ($i % 2 -eq 0) {
            $body = @{ cliente = "Supermercado Masivo"; vinoId = "VINO-005"; cantidad = 500 } | ConvertTo-Json
        } else {
            $body = @{ cliente = "Cliente Fantasma"; vinoId = "VINO-999"; cantidad = 2 } | ConvertTo-Json
        }

        try {
            $resp = Invoke-RestMethod -Uri "$PedidosUrl/api/pedidos" -Method Post -Body $body -ContentType "application/json"
            Write-Host "Pedido #$i: $($resp.estado)" -ForegroundColor Yellow
        } catch {
            Write-Host "Pedido #$i: RECHAZADO (Stock Insuficiente / Vino No Existe)" -ForegroundColor Red
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Host "`n✔ Casuística disparada. Observe el panel 'Tasa de Rechazo (%)' y alerta 'HighOrderRejectionRate' en Prometheus." -ForegroundColor Green
}

function Casuistica-Lento {
    Write-Host "`n>>> Ejecutando Casuística de Rendimiento: Servicio Lento..." -ForegroundColor Cyan
    Write-Host "Generando solicitudes con demora inducida de 3 segundos en Servicio A..." -ForegroundColor Gray

    for ($i = 1; $i -le 5; $i++) {
        Write-Host "Llamada con demora #$i (esperando 3s)..." -ForegroundColor Yellow
        $resp = Invoke-RestMethod -Uri "$CatalogoUrl/api/vinos/simular-demora?segundos=3" -Method Get
        Write-Host "  Completado en $($resp.duracionRealMs) ms" -ForegroundColor Green
    }
    Write-Host "`n✔ Casuística finalizada. Observe el panel 'Latencia de Procesamiento p95' y alerta 'SlowOrderProcessingLatency'." -ForegroundColor Green
}

function Casuistica-Caido {
    Write-Host "`n>>> Ejecutando Casuística de Resiliencia: Servicio Caído..." -ForegroundColor Red
    Write-Host "Escalando catalogo-deployment a 0 réplicas..." -ForegroundColor Yellow
    kubectl scale deployment catalogo-deployment -n bodega-peirano --replicas=0

    Write-Host "Esperando 5 segundos a que se detenga el pod..." -ForegroundColor Gray
    Start-Sleep -Seconds 5

    Write-Host "Enviando pedidos mientras el Servicio A está caído:" -ForegroundColor Yellow
    for ($i = 1; $i -le 5; $i++) {
        $body = @{ cliente = "Cliente Intento"; vinoId = "VINO-001"; cantidad = 1 } | ConvertTo-Json
        try {
            $resp = Invoke-RestMethod -Uri "$PedidosUrl/api/pedidos" -Method Post -Body $body -ContentType "application/json"
            Write-Host "Pedido #$i: $($resp.estado)"
        } catch {
            Write-Host "Pedido #$i: HTTP 503 / Fallido (Servicio A inalcanzable)" -ForegroundColor DarkRed
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Host "`n✔ Verifique en Grafana que el panel 'Disponibilidad' marca DOWN en rojo y se activa la alerta 'CatalogoServiceDown'." -ForegroundColor Yellow
    Write-Host "Para restaurar el servicio seleccione la opción 5 en el menú." -ForegroundColor Cyan
}

function Restaurar-Servicio {
    Write-Host "`n>>> Restaurando Servicio A (Catálogo)..." -ForegroundColor Green
    kubectl scale deployment catalogo-deployment -n bodega-peirano --replicas=1
    kubectl rollout status deployment/catalogo-deployment -n bodega-peirano --timeout=60s
    Write-Host "`n✔ Servicio restaurado a 1 réplica. El panel volverá a ONLINE verde en Grafana." -ForegroundColor Green
}

function Suite-Completa {
    Flujo-Normal
    Casuistica-Negocio
    Casuistica-Lento
}

do {
    $opc = Mostrar-Menu
    switch ($opc) {
        "1" { Flujo-Normal }
        "2" { Casuistica-Negocio }
        "3" { Casuistica-Lento }
        "4" { Casuistica-Caido }
        "5" { Restaurar-Servicio }
        "6" { Suite-Completa }
        "0" { Write-Host "Saliendo..."; break }
        default { Write-Host "Opción inválida." -ForegroundColor Red }
    }
    Write-Host ""
} while ($opc -ne "0")
