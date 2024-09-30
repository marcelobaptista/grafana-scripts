#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

token="" # Token de acesso ao Grafana
grafana_url="" # URL do Grafana

# Endpoints para as requisições
endpoint_dashboards="${grafana_url}/api/dashboards/uid"
endpoint_search="${grafana_url}/api/search?type=dash-db&limit=5000"

# Consulta a API do Grafana para listar dashboards e salva os UIDs em um arquivo
curl -kH "Authorization: Bearer ${token}" \
  "${endpoint_search}" |
  jq -r '.[].uid' >dashboards_uid.txt

# Cria um diretório temporário
mkdir -p ./tmp

# Lê cada UID do arquivo dashboards_uid.txt
while IFS= read -r uid; do

  # Consulta a API para pegar informações sobre o dashboard e formata os resultados
  curl -# -kH "Authorization: Bearer ${token}" \
    "${endpoint_dashboards}/${uid}" | jq -r >"./tmp/${uid}.json"

  # Variáveis para DashboardFolder, DashboardName e Url
  dashboard_folder=$(jq -r '.meta.folderTitle' "./tmp/${uid}.json")
  dashboard_name=$(jq -r '.dashboard.title' "./tmp/${uid}.json")
  dashboard_url=$(jq -r '.meta.url' "./tmp/${uid}.json")

  # Pega o número de painéis no dashboard
  panels_length=$(jq -r '.dashboard.panels | length' "./tmp/${uid}.json")

  # Loop através de todos os painéis do dashboard
  for ((i = 0; i < panels_length; i++)); do

    # Verifica o tipo do painel
    panel_type=$(jq -r --argjson i "${i}" '.dashboard.panels[$i].type' "./tmp/${uid}.json")

    # Verifica se o tipo do painel é "graph"
    if [ "${panel_type}" != "graph" ]; then continue; fi

    # Se o painel for do tipo "graph", coleta o ID do painel
    panel_id=$(jq -r --argjson i "${i}" '.dashboard.panels[$i].id' "./tmp/${uid}.json")

    # Adiciona informações do painel ao arquivo CSV
    echo "${dashboard_folder};${dashboard_name};${grafana_url}${dashboard_url}?orgId=1&editPanel=${panel_id}" >>GraphPanels.csv
  done
done <dashboards_uid.txt

# Remove duplicatas e adiciona cabeçalho ao arquivo CSV
sort -u GraphPanels.csv -o GraphPanels.csv
sed -i '' "1s/^/DashboardFolder;DashboardName;DashboardPanelUrl\n/" GraphPanels.csv

# Remove diretório temporário e arquivo de UIDs
rm -rf ./tmp dashboards_uid.txt
