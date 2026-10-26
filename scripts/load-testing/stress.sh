#!/usr/bin/env bash
# ==============================================================================
# Script de Pruebas de Carga y Validación de Casuísticas - Bodega Peirano
# ==============================================================================
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Determinar host de acceso (Minikube IP o localhost)
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "127.0.0.1")
HOST="${1:-$MINIKUBE_IP}"
CATALOGO_URL="http://${HOST}:30081"
PEDIDOS_URL="http://${HOST}:30082"

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}      BODEGA PEIRANO — GENERADOR DE CARGA Y CASUÍSTICAS         ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Catálogo API: ${YELLOW}${CATALOGO_URL}${NC}"
echo -e "Pedidos API:  ${YELLOW}${PEDIDOS_URL}${NC}\n"

mostrar_menu() {
    echo -e "${YELLOW}Seleccione el escenario a ejecutar:${NC}"
    echo "1) Flujo Normal de Pedidos (Compras exitosas, rotación de stock e ingresos)"
    echo "2) Casuística de Negocio: Alta Tasa de Rechazo y Stock Agotado (Regla de negocio)"
    echo "3) Casuística de Servicio Lento (Inyección de latencia y p95)"
    echo "4) Casuística de Servicio Caído (Escalar Servicio A a 0 réplicas y validar)"
    echo "5) Restaurar Servicio Caído (Escalar Servicio A a 1 réplica)"
    echo "6) Ejecutar Suite Completa de Pruebas de Estrés (Mixta)"
    echo "0) Salir"
    read -p "Opción [1-6]: " OPCION
}

flujo_normal() {
    echo -e "\n${CYAN}>>> Generando 20 pedidos válidos variados...${NC}"
    CLIENTES=("Restaurante Astrid y Gaston" "Hotel Westin Lima" "Bodega Don Jose" "Sommelier Carlos" "Lucia Bar")
    VINOS=("VINO-001" "VINO-002" "VINO-003" "VINO-004")

    for i in {1..20}; do
        CLI=${CLIENTES[$RANDOM % ${#CLIENTES[@]}]}
        VINO=${VINOS[$RANDOM % ${#VINOS[@]}]}
        CANT=$(( (RANDOM % 3) + 1 ))

        curl -s -X POST "${PEDIDOS_URL}/api/pedidos" \
             -H "Content-Type: application/json" \
             -d "{\"cliente\":\"$CLI\",\"vinoId\":\"$VINO\",\"cantidad\":$CANT}" \
             | grep -o '"estado":"[^"]*"' || true
        sleep 0.3
    done
    echo -e "\n${GREEN}✔ Flujo normal finalizado. Revise paneles de Ingresos y Flujo en Grafana.${NC}"
}

casuistica_negocio() {
    echo -e "\n${CYAN}>>> Ejecutando Casuística de Negocio: Alta Tasa de Rechazos y Stock Agotado...${NC}"
    echo -e "Enviando pedidos con cantidades excesivas (stock insuficiente) y vinos inexistentes..."

    for i in {1..30}; do
        if (( i % 2 == 0 )); then
            # Pide 500 botellas de un vino que solo tiene stock reducido
            curl -s -X POST "${PEDIDOS_URL}/api/pedidos" \
                 -H "Content-Type: application/json" \
                 -d '{"cliente":"Supermercado Masivo","vinoId":"VINO-005","cantidad":500}' \
                 | grep -o '"estado":"[^"]*"' || true
        else
            # Pide vino inexistente
            curl -s -X POST "${PEDIDOS_URL}/api/pedidos" \
                 -H "Content-Type: application/json" \
                 -d '{"cliente":"Cliente Fantasma","vinoId":"VINO-999","cantidad":2}' \
                 | grep -o '"estado":"[^"]*"' || true
        fi
        sleep 0.2
    done
    echo -e "\n${GREEN}✔ Casuística disparada. Observe el panel 'Tasa de Rechazo (%)' y alerta 'HighOrderRejectionRate' en Prometheus.${NC}"
}

casuistica_lento() {
    echo -e "\n${CYAN}>>> Ejecutando Casuística de Rendimiento: Servicio Lento...${NC}"
    echo -e "Generando solicitudes con demora inducida de 3 segundos en Servicio A..."

    for i in {1..5}; do
        echo -e "Llamada con demora #$i..."
        curl -s "${CATALOGO_URL}/api/vinos/simular-demora?segundos=3" | grep -o '"segundosSimulados":[0-9]*' || true
    done
    echo -e "\n${GREEN}✔ Casuística finalizada. Observe el panel 'Latencia de Procesamiento p95' y alerta 'SlowOrderProcessingLatency'.${NC}"
}

casuistica_caido() {
    echo -e "\n${RED}>>> Ejecutando Casuística de Resiliencia: Servicio Caído...${NC}"
    echo -e "Escalando catalogo-deployment a 0 réplicas..."
    kubectl scale deployment catalogo-deployment -n bodega-peirano --replicas=0

    echo -e "Esperando 5 segundos a que se detenga el pod..."
    sleep 5

    echo -e "Enviando pedidos mientras el Servicio A está caído:"
    for i in {1..5}; do
        curl -s -X POST "${PEDIDOS_URL}/api/pedidos" \
             -H "Content-Type: application/json" \
             -d '{"cliente":"Cliente Intento","vinoId":"VINO-001","cantidad":1}' \
             | grep -o '"estado":"[^"]*"' || true
        sleep 0.5
    done

    echo -e "\n${YELLOW}✔ Verifique en Grafana que el panel 'Disponibilidad' marca DOWN en rojo y se activa la alerta 'CatalogoServiceDown'.${NC}"
    echo -e "Para restaurar el servicio seleccione la opción 5 en el menú."
}

restaurar_servicio() {
    echo -e "\n${GREEN}>>> Restaurando Servicio A (Catálogo)...${NC}"
    kubectl scale deployment catalogo-deployment -n bodega-peirano --replicas=1
    kubectl rollout status deployment/catalogo-deployment -n bodega-peirano --timeout=60s
    echo -e "\n${GREEN}✔ Servicio restaurado a 1 réplica. El panel volverá a ONLINE verde en Grafana.${NC}"
}

suite_completa() {
    flujo_normal
    casuistica_negocio
    casuistica_lento
}

if [ $# -gt 0 ] && [ "$1" == "--all" ]; then
    suite_completa
    exit 0
fi

while true; do
    mostrar_menu
    case "$OPCION" in
        1) flujo_normal ;;
        2) casuistica_negocio ;;
        3) casuistica_lento ;;
        4) casuistica_caido ;;
        5) restaurar_servicio ;;
        6) suite_completa ;;
        0) exit 0 ;;
        *) echo -e "${RED}Opción no válida.${NC}" ;;
    esac
    echo ""
done
