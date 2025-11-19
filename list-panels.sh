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

  # Extrai título do folder, título do dashboard e URL do dashboard
  folder_title=$(jq -r '.meta.folderTitle' temp.json)
  dashboard_title=$(jq -r '.dashboard.title' temp.json)
  dashboard_url=$(jq -r '.meta.url' temp.json)

  # Extrai número de painéis no dashboard
  panels_length=$(jq -r '.dashboard.panels | length' temp.json)

  # Cria a pasta de destino para os arquivos CSV
  mkdir -p "${date_now}-panels/${folder_title}"

  # Define a pasta de destino para os arquivos CSV
  folder_destination="${date_now}-panels/${folder_title}"

  # Loop através de todos os painéis do dashboard
  for ((i = 0; i < panels_length; i++)); do
    jq -r '.dashboard.panels['"${i}"']' temp.json >"${i}.json"

    # Ignora painéis do tipo "row"
    if jq -e '.type == "row"' "${i}.json" >/dev/null; then
      rm -f "${i}.json"
      continue
    fi

    # Se tiver targets, lista normalmente, mas trata array e objeto
    if jq -e '.targets != null and .targets != []' "${i}.json" >/dev/null; then

      # Verifica se targets é array
      if jq -e '(.targets | type) == "array"' "${i}.json" >/dev/null; then
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
            (if ($panel.targets and ($panel.targets | length) > 0 and
                $panel.targets[0].datasource and
                ($panel.targets[0].datasource | type) == "object")
                then ($panel.targets[0].datasource.uid // "-")
                else "-"
            end) + ";" +
            ($panel.type // "-")
            ' "${i}.json" >>"${folder_destination}/panels.csv"
      else

        # targets é objeto, não array
        #
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
            (if ($panel.datasource | type) == "object" then ($panel.datasource.type // "-") else ($panel.datasource // "-") end) + ";" +
            ($panel.type // "-") + ";N/A"
            ' "${i}.json" >>"${folder_destination}/panels.csv"
      fi
    else
      # Não tem targets
      #
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
          ' "${i}.json" >>"${folder_destination}/panels.csv"
    fi

    # Remove o arquivo temporário do painel
    rm -f "${i}.json"

  done

  # Remove linhas duplicadas, se houver
  sort -u -o "${folder_destination}/panels.csv" "${folder_destination}/panels.csv"

  # Adiciona o cabeçalho no arquivo gerado
  sed -i "1s/^/dashboardFolder;dashboardName;panelTitle;url;datasourceType;datasourceUid;panelType\n/" "${folder_destination}/panels.csv"

  # Remove o arquivo temporário do dashboard
  rm -f temp.json

done <dashboards_uid.txt

# Remove arquivos temporários
rm -rf dashboards{.json,_uid.txt}
