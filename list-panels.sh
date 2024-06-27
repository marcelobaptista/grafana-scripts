#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Solicita a URL do Grafana
printf "Digite a URL do Grafana (ex: http://127.0.0.1:3000)\n\n"
read -r grafana_url
[[ -z "${grafana_url}" ]] && exit_with_error "URL do Grafana não pode ser vazia"

# # Solicita o token de acesso à API do Grafana
printf "\nDigite o token:\n\n"
read -r token
[[ -z "${token}" ]] && exit_with_error "Token não pode ser vazio"

clear

# Lista todos os dashboards
curl -k "${grafana_url}/api/search?type=dash-db&limit=5000" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${token}" |
  jq -r '.[].uid' >dashboardsUID.txt

#
while IFS= read -r uid; do
  curl -k "${grafana_url}/api/dashboards/uid/${uid}" \
    -H "Accept: application/json" \
    -H "Content-Type: application" \
    -H "Authorization: Bearer ${token}" |
    jq -r >dashboard.json

  #
  dashboard_title=$(jq -r '.dashboard.title' dashboard.json)
  panels_length=$(jq '.dashboard.panels | length' dashboard.json)

  #
  for ((i = 0; i < panels_length; i++)); do
    jq -r '.dashboard.panels['"${i}"']' dashboard.json >"${i}.json"

    #
    if jq -e '.targets != null and .targets != []' "${i}.json" >/dev/null; then
      jq -r --arg dashboard_title "${dashboard_title}" \
        '. |"\($dashboard_title);\(.title);\(.type);\(.targets[].datasource.uid);\(.targets[].expr)"' \
        "${i}.json" >>panels.csv
      rm -f "${i}.json"
    #
    else
      jq -r --arg dashboard_title "${dashboard_title}" \
        '. |"\($dashboard_title);\(.title);\(.type);N/A;N/A"' \
        "${i}.json" >>panels.csv
      rm -f "${i}.json"
    fi
  done
done <dashboardsUID.txt
sort -u panels.csv -o panels.csv
sed -i "1s/^/Dashboard;Panel;Type;Datasource;Query\n/" panels.csv
rm -f dashboard.json dashboardsUID.txt
