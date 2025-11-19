#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se a URL e o token foram passados como argumentos
if [ $# -lt 2 ]; then
  printf "\nUso do script: %s <grafana_url> <grafana_token>\n" "$0"
  exit 1
fi

# Argumentos passados para o script
grafana_url=$1
grafana_token=$2

# Define a data atual
date_now=$(date +%Y-%m-%d)

# Endpoint para requisições
grafana_api_notification_policies="${grafana_url}/api/v1/provisioning/policies"

# Consulta a API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_notification_policies}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" \
  -o "temp.json"; then
  printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
  exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "temp.json"; then
  printf "\nErro: chave de API inválida.\n"
  rm -f "temp.json"
  exit 1
elif grep -iq "Access denied" "temp.json" || grep -iq "Permissions needed" "temp.json"; then
  printf "\nErro: token sem permissão suficiente.\n"
  rm -f "temp.json"
  exit 1
fi

# Formata e salva o JSON de notification policy
jq -r '.' temp.json >"${date_now}-notification-policy-tree.json"

# Remove arquivo temporário
rm -f temp.json
