#!/bin/bash

#############################################################
# Este script importa todos os datasources,dashboards       # 
# e folders do Grafana e exporta para outro Grafana         #
#############################################################

# Habilita o modo de saída de erro
set -euo pipefail

grafana_source="" # URL do Grafana de origem
token_source=""  # Token de acesso do Grafana de origem

grafana_dest="" # URL do Grafana de destino
token_dest="" # Token de acesso do Grafana de destino

# Consulta a API do Grafana para obter a lista de dashboards e salva os UIDs em um arquivo
curl -sk "${grafana_source}/api/search?type=dash-db&limit=5000" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${token_source}" \
  -H "Content-Type: application/json" |
  jq -r '.[] | .uid' >dashboards_uid.txt

# Cria um diretório para armazenar os dashboards
mkdir -p ./dashboards

# Loop sobre os UIDs dos dashboards
while IFS= read -r uid; do
  # Consulta a API para obter informações sobre o dashboard e salva em um arquivo JSON
  curl -sk "${grafana_source}/api/dashboards/uid/${uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token_source}" \
    -H "Content-Type: application/json" |
    jq -r '. |= (.folderUid=.meta.folderUid) |del(.meta) |del(.dashboard.id) + {overwrite: true}' >"./dashboards/${uid}.json"
done <"dashboards_uid.txt"

###########################################################################################################################

# Consulta a API do Grafana para obter a lista de folders e salva os UIDs em um arquivo
curl -sk "${grafana_source}/api/folders" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${token_source}" \
  -H "Content-Type: application/json" |
  jq -r '.[] | .uid' >folders_uid.txt

# Cria um diretório para armazenar os folders
mkdir -p ./folders

while IFS= read -r uid; do
  # Consulta a API para obter informações sobre o folder e salva em um arquivo JSON
  curl -sk "${grafana_source}/api/folders/${uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token_source}" \
    -H "Content-Type: application/json" |
    jq '. |del(.id) + {overwrite: true}' >"./folders/${uid}.json"
done <"folders_uid.txt"

###########################################################################################################################

# Consulta a API do Grafana para obter a lista de datasources e salva os UIDs em um arquivo
curl -sk "${grafana_source}/api/datasources" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${token_source}" \
  -H "Content-Type: application/json" |
  jq -r '.[] | .uid' >datasources_uid.txt

# Cria um diretório para armazenar os datasources
mkdir -p ./datasources

while IFS= read -r uid; do
  # Consulta a API para obter informações sobre o datasource e salva em um arquivo JSON
  curl -sk "${grafana_source}/api/datasources/uid/${uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token_source}" \
    -H "Content-Type: application/json" |
    jq '. |del(.id)' >"./datasources/${uid}.json"
done <"datasources_uid.txt"

# Exporta os datasources
for datasource in ./datasources/*json; do
  curl -k -X POST "${grafana_dest}/api/datasources" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token_dest}" \
    -H "Content-Type: application/json" \
    -d "@${datasource}"
done

# Exporta os folders
for folder in ./folders/*json; do
  curl -k -X POST "${grafana_dest}/api/folders" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token_dest}" \
    -H "Content-Type: application/json" \
    -d "@${folder}"
done

# Exporta os dashboards
for dashboard in ./dashboards/*json; do
  curl -k -X POST "${grafana_dest}/api/dashboards/db" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token_dest}" \
    -H "Content-Type: application/json" \
    -d "@${dashboard}"
done

rm -f {dashboards_uid,datasources_uid,folders_uid}.txt