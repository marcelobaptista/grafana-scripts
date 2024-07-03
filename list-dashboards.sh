#!/bin/bash

#####################################################################
# Script para listar todos os dashboards do Grafana e gerar um CSV #
#####################################################################

# Este script solicita a URL do Grafana, um token de acesso à API do Grafana
# e o nome do arquivo de saída. Em seguida, ele lista todos os dashboards disponíveis
# no Grafana e os salva em um arquivo CSV com as seguintes colunas:
# Folder;Dashboard;Version;createdBy;Created;UpdatedBy;Updated;URL

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se o arquivo a ser criado foi passado como argumento
if [ $# -ne 1 ]; then
    echo "Uso do script: $0 nome_do_arquivo_a_ser_criado"
    exit 1
fi

# Remove o arquivo se ele existir
if [ -f "$1.csv" ]; then
  rm -f "$1.csv"
  echo "Arquivo removido: $1.csv"
fi

token="" # Token de acesso ao Grafana
grafana_url="" # URL do Grafana

# Consulta a API do Grafana para obter a lista de dashboards e salva os UIDs em um arquivo
curl -sk "${grafana_url}/api/search?type=dash-db&limit=5000" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" |
    jq -r '.[] | .uid' >dashboards_uid.txt

while IFS= read -r uid; do
    # Consulta a API para obter informações sobre o dashboard e salva em um arquivo JSON
    curl -sk "${grafana_url}/api/dashboards/uid/${uid}" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" |
        jq -r '
. |
"\(.meta.folderTitle);\(.dashboard.title);\(.meta.version);\(.meta.createdBy);\(.meta.created);\(.meta.updated);\(.meta.updatedBy);'"${grafana_url}"'\(.meta.url)"
' >>"$1.csv"
done <"dashboards_uid.txt"
sed -i "1s/^/Folder;Dashboard;Version;createdBy;Created;Updated;UpdatedBy;URL\n/" "$1.csv"
rm dashboards_uid.txt
