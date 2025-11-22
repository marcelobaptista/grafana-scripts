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

# Pasta de destino
folder_destination="./_${date_now}-panels-report"

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_url}/api/search?type=dash-db&limit=5000" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" \
  > "dashboards.json"; then
  printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
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
jq -r '.[] | .uid' dashboards.json >dashboards-uids.txt

# Cria pasta de destino dos arquivos CSV gerados ( 1 arquivo CSV por folder do Grafana)
mkdir -p "./${folder_destination}"

# Itera sobre cada dashboard UID e extrai informações
while IFS= read -r uid; do

  curl -# -sk "${grafana_url}/api/dashboards/uid/${uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" \
    | jq -r >"dashboard-${uid}.json"

  # Extrai o nome do folder
  folder_title=$(jq -r '.meta.folderTitle' "dashboard-${uid}.json")

  # Formata o nome do folder para ser usado como nome de arquivo 
  folder_title_sanitized=$(jq -r '.meta.url' "dashboard-${uid}.json" | awk -F'/' '{print $NF}')

  # Extrai o nome do dashboard
  dashboard_title=$(jq -r '.dashboard.title' "dashboard-${uid}.json")

  # Formata o nome do dashboard para ser usado como nome de arquivo 
  dashboard_url=$(jq -r '.meta.url' "dashboard-${uid}.json")

  # Extrai número de painéis no dashboard
  panels_length=$(jq '.dashboard.panels | length' "dashboard-${uid}.json")

  # Itera sobre cada painel do dashboard
  for ((i = 0; i < panels_length; i++)); do

    # Salva o painel em um arquivo temporário
    jq -r '.dashboard.panels['"${i}"']' "dashboard-${uid}.json" >"panel-${i}.json"

    # Ignora painéis do tipo row
    if jq -e '.type == "row"' "panel-${i}.json" >/dev/null; then
      rm -f "panel-${i}.json"
      continue
    fi

    # Se tiver targets, lista normalmente, mas trata array e objeto
    if jq -e '.targets != null and .targets != []' "panel-${i}.json" >/dev/null; then
      # Verifica se targets é array
      if jq -e '(.targets | type) == "array"' "panel-${i}.json" >/dev/null; then
        jq -r \
          --arg folder_title "${folder_title}" \
          --arg dashboard_title "${dashboard_title}" \
          --arg dashboard_url "${dashboard_url}" \
          --arg grafana_url "${grafana_url}" \
          '
            . as $panel |
            ($folder_title) + ";" +
            ($dashboard_title) + ";" +
            ($panel.title // "-") + ";" +
            ($grafana_url + $dashboard_url + "?&viewPanel=" + ($panel.id|tostring)) + ";" +
            (if ($panel.datasource | type) == "object" 
                then ($panel.datasource.type // "-") 
                else ($panel.datasource // "-") 
            end) + ";" +
            ($panel.type // "-") + ";" +
            (if ($panel.targets and ($panel.targets | length) > 0 and $panel.targets[0].datasource and ($panel.targets[0].datasource | type) == "object") then ($panel.targets[0].datasource.uid // "-") else "-" end)
            ' "panel-${i}.json" >>"${folder_destination}/${folder_title_sanitized}".csv
      else
        # targets é objeto, não array
        jq -r \
          --arg folder_title "${folder_title}" \
          --arg dashboard_title "${dashboard_title}" \
          --arg dashboard_url "${dashboard_url}" \
          --arg grafana_url "${grafana_url}" \
          '
            . as $panel |
            ($folder_title) + ";" +
            ($dashboard_title) + ";" +
            ($panel.title // "-") + ";" +
            ($grafana_url + $dashboard_url + "?orgId=1&viewPanel=" + ($panel.id|tostring)) + ";" +
            (if ($panel.datasource | type) == "object" then ($panel.datasource.type // "-") else ($panel.datasource // "-") end) + ";" +
            ($panel.type // "-") + ";N/A"
            ' "panel-${i}.json" >>"${folder_destination}/${folder_title_sanitized}".csv
      fi
    else
      jq -r \
        --arg folder_title "${folder_title}" \
        --arg dashboard_title "${dashboard_title}" \
        --arg dashboard_url "${dashboard_url}" \
        --arg grafana_url "${grafana_url}" \
        '
          . as $panel |
          ($folder_title) + ";" +
          ($dashboard_title) + ";" +
          ($grafana_url + $dashboard_url + "?viewPanel=" + ($panel.id|tostring)) + ";" +
          ($panel.title // "-") + ";" +
          (if ($panel.datasource | type) == "object" then ($panel.datasource.type // "-") else ($panel.datasource // "-") end) + ";" +
          ($panel.type // "-") + ";N/A"
          ' "panel-${i}.json" >>"${folder_destination}/${folder_title_sanitized}".csv
    fi

    # Remove arquivo temporário do painel
    rm -f "panel-${i}.json"

  done

  # Remove arquivo temporário do dashboard
  rm -f "dashboard-${uid}.json"

done <dashboards-uids.txt

# Remove arquivos temporários
rm -f dashboards{.json,-uids.txt}
