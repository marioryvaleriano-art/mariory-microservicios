#!/usr/bin/env bash
# ==============================================================================
# Script de Desinstalación y Limpieza - Bodega Peirano
# ==============================================================================
set -euo pipefail

CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}   LIMPIEZA DE RECURSOS: BODEGA PEIRANO MICROSERVICIOS         ${NC}"
echo -e "${CYAN}================================================================${NC}"

echo -e "\n${YELLOW}[1/3] Eliminando namespace y aplicaciones bodega-peirano...${NC}"
kubectl delete namespace bodega-peirano --ignore-not-found=true

read -p "¿Desea también desinstalar Prometheus & Grafana (namespace monitoring)? [s/N]: " RESP
if [[ "$RESP" =~ ^[sSyY]$ ]]; then
    echo -e "\n${YELLOW}[2/3] Desinstalando stack kube-prometheus-stack...${NC}"
    helm uninstall prometheus -n monitoring || true
    kubectl delete namespace monitoring --ignore-not-found=true
else
    echo -e "Omitiendo desinstalación de Prometheus & Grafana."
fi

echo -e "\n${GREEN}✔ Limpieza completada exitosamente.${NC}"
