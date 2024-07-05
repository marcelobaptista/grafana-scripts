#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

token="" # Token de acesso ao Grafana
grafana_url="" # URL do Grafana

# Endpoints para as requisições
endpoint_dashboards="${grafana_url}/api/dashboards"
endpoint_search="${grafana_url}/api/search?type=dash-db&limit=5000"

# Consulta a API do Grafana para obter a lista de dashboards e salva os UIDs em um arquivo
curl -sk "${endpoint_search}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" |
  jq -r '.[] | .uid' >dashboards_uid.txt

# Cria diretórios necessários
mkdir -p {updated,original}-dashboards

# Loop sobre os UIDs dos dashboards
while IFS= read -r uid; do
  # Consulta a API para obter informações sobre o dashboard e salva em um arquivo JSON
  curl -sk "${endpoint_dashboards}/uid/${uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" |
    jq -r >tmp.json

  # Verifica se existe painel do tipo "timeseries" no dashboard
  graph=$(grep -c '"type": "graph"' tmp.json)

  # Se não existir, remove o arquivo temporário e continua o loop
  if [ "${graph}" -eq 0 ]; then rm -f tmp.json && continue; fi
  
  # Variáveis para nomear diretórios e arquivos
  folder_title=$(jq -r '.meta.folderTitle' tmp.json)
  dashboard_slug=$(jq -r '.meta.slug' tmp.json)

  # Cria diretório para os arquivos de backup dos dashboards, renomeando-os
  mkdir -p "original-dashboards/${folder_title}"

  # Salva o dashboard original com estrutura JSON modificada
  # que possibilita a importação pela interface do Grafana
  jq -r '{meta:.meta}+.dashboard' tmp.json >"original-dashboards/${folder_title}/${dashboard_slug}.json"

  # Cria diretório para os arquivos com os dashboards modificados
  mkdir -p "updated-dashboards/${folder_title}"
  dashboard_updated="updated-dashboards/${folder_title}/${dashboard_slug}.json"

  # Modifica a estrutura JSON original e salva no respectivo diretório.
  # Esse procedimento é necessário pois caso contrário não é possível
  # atualizar o dashboard através de API
  jq -r '
    . |= (.folderUid=.meta.folderUid) 
    |del(.meta) 
    |del(.dashboard.id) + {overwrite: true}
    ' tmp.json >"${dashboard_updated}"

  # Variável para o nome do dashboard
  dashboard_name=$(jq -r '.dashboard.title' tmp.json)

  # Altera os painéis do tipo "graph" para "timeseries"
  sed -i 's/"type": "graph"/"type": "timeseries"/' "${dashboard_updated}"

  # Atualiza o dashboard usando a API do Grafana
  curl -sk -X POST "${endpoint_dashboards}/db" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d @"${dashboard_updated}"

  rm -f tmp.json

  # Gera um CSV apenas para relatório
  echo "${folder_title};${dashboard_name};${grafana_url}/d/${uid}" >>Dashboards.csv
done <"dashboards_uid.txt"

# Adiciona cabeçalho ao arquivo CSV
sed -i "1s/^/Folder;Dashboard;URL\n/" Dashboards.csv

# Clean up
rm -rf dashboards_uid.txt
