#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se a url e o token foram passados como argumentos
if [ $# -lt 2 ]; then
  printf "\nUso do script: %s <grafana_url> <grafana_token>\n" "$0"
  exit 1
fi

# Argumentos passados para o script
grafana_url=$1
grafana_token=$2

# Define a data atual
date_now=$(date +%Y-%m-%d)

# Arquivo de saída
output_file="${date_now}-grafana-graph-panels.csv"

# Consulta API do Grafana e extrai todos dashboards configurados, com tratamento de erro de conexão
if ! curl -sk "${grafana_url}/api/search?type=dash-db&limit=5000" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" \
  -o "dashboards.json"; then
  printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
  rm -f "dashboards.json"
  exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "dashboards.json"; then
  printf "\nErro: chave de API inválida.\n"
  rm -f "dashboards.json"
  exit 1
elif grep -iq "Access denied" "dashboards.json" || grep -iq "Permissions needed" "dashboards.json"; then
  printf "\nErro: token sem permissão suficiente.\n"
  rm -f "dashboards.json"
  exit 1
fi

# Cria lista de UIDs dos dashboards
jq -r '.[].uid' dashboards.json >dashboards_uid.txt

# Itera sobre cada UID e extrai informações
while IFS= read -r uid; do

  # Salva o dashboard em um arquivo temporário
  curl -# -sk "${grafana_url}/api/dashboards/uid/${uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" \
    | jq -r >temp.json

  # Extrai número de painéis no dashboard
  panels_length=$(jq -r '.dashboard.panels | length' temp.json)

  # Loop através de todos os painéis do dashboard
  for ((i = 0; i < panels_length; i++)); do

    # Verifica o tipo do painel
    panel_type=$(jq -r --argjson i "${i}" '.dashboard.panels[$i].type' temp.json)

    # Verifica se o tipo do painel é "graph"
    if [ "${panel_type}" != "graph" ]; then continue; fi

    # Se o painel for do tipo "graph", coleta o ID do painel
    panel_id=$(jq -r --argjson i "${i}" '.dashboard.panels[$i].id' temp.json)

    # Adiciona informações do painel ao arquivo CSV
    jq -r --arg grafana_url "${grafana_url}" \
      --arg panel_id "${panel_id}" \
      '. |
        (.meta.folderTitle | tostring) + ";" +
        (.dashboard.title | tostring) + ";" +
        ($grafana_url) + (.meta.url) + "?viewPanel=" +($panel_id | tostring))
    ' temp.json >>"${output_file}"

  done

  # Remove o arquivo temporário
  rm -f temp.json

done <dashboards_uid.txt

if [ ! -s "${output_file}" ]; then
  printf "\nNenhum painel do tipo 'graph' foi encontrado.\n"
  rm -rf dashboards{.json,_uid.txt}
  exit 0
fi

# Remove linhas duplicadas, se houver
sort -u -o "${output_file}" "${output_file}"

# Adiciona o cabeçalho no arquivo gerado
sed -i "1s/^/dashboardFolder;dashboardName;url\n/" "${output_file}"

# Remove arquivos temporários
rm -rf dashboards{.json,_uid.txt}
