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

# Nome do arquivo de saída
output_file="${date_now}-datasources-report.csv"

# Endpoint para requisições
endpoint_datasources="${grafana_url}/api/datasources"

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
curl -sk "${endpoint_datasources}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" |
  jq -r >datasources.json

# Extrai as informações e adiciona ao arquivo CSV
jq -r '.[] |
  (.name) + ";" +
  (.uid) + ";" +
  (.typeName) + ";" +
  ((.url // "-") | select(length > 0) // "-")' datasources.json >"${output_file}"

# Insere cabeçalho no arquivo CSV
sed -i '1i\
datasourceName;uid;typeName;url
' "${output_file}"

# Remove arquivo temporário
rm -f datasources.json
