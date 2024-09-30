#!/bin/bash

# Script para buscar alertas configurados de um tipo de datasource
# É executado de forma interativa e ao final gera um arquivo .csv

grafana_token=""
grafana_url=""

# Endpoints para as requisições
endpoint_alert_rules="${grafana_url}/api/v1/provisioning/alert-rules"
endpoint_datasources="${grafana_url}/api/datasources"
endpoint_folders="${grafana_url}/api/folders"

# Lista todas as regras de alerta configuradas
curl -sk "${endpoint_alert_rules}" \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer ${grafana_token}" \
  -H 'Content-Type: application/json' |
  jq -r >alert-rules.json

if [ ! -s alert-rules.json ]; then echo "Verificar url e token" && exit 1; fi

# Lista todos folders configurados
curl -sk "${endpoint_folders}" \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer ${grafana_token}" \
  -H 'Content-Type: application/json' |
  jq -r >folders.json

# Lista todos datasources configurados
curl -sk "${endpoint_datasources}" \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer ${grafana_token}" \
  -H 'Content-Type: application/json' |
  jq -r >datasources.json

# Cria uma lista com o tipo de datasource disponível no Grafana
datasources=$(jq -r '.[].type' datasources.json | sort -u)

# Solicita no terminal o tipo de datasource
printf "Digite um tipo de datasource:\n\n%s\n\n" "${datasources}"
read -r choice

# Cria um arquivo .txt com os UIDs do datasource escolhido anteriormente
jq -r --arg choice "${choice}" '.[] | select(.type == $choice) | .uid' datasources.json >"${choice}".txt

# Verifica a quantidade de alerta configurado
length=$(jq -r '. | length' alert-rules.json)

# Loop em todos alerta
for ((i = 0; i < length; i++)); do
  # Salva o alerta em um arquivo temporário
  jq -r --argjson i "${i}" '.[$i]' alert-rules.json >"${i}.json"

  # Verifica a quantidade de queries configurado
  data_length=$(jq -r '.data | length' "${i}.json")

  # Loop em todas queries
  for ((j = 0; j < data_length; j++)); do

    # Extrai o uid do datasource da query atual
    datasource_uid=$(jq -r --argjson j "${j}" '.data[$j].datasourceUid' "${i}.json")

    # Verifica se o UID da query atual é o mesmo que o escolhido anteriormente
    # Caso não seja, vai para a próxima query
    if ! grep -q -- "${datasource_uid}" "${choice}".txt; then
      continue
    fi

    # Extrai o nome do datasource
    datasource_name=$(jq -r --arg uid "${datasource_uid}" '.[] | select(.uid == $uid) | .name' datasources.json)

    # Extrai o uid do folder
    folder_uid=$(jq -r 'if .folderUID == "" then null else .folderUID end' "${i}.json")

    # Verifica se o folder_uid é null e define folder_name como null, caso contrário, extrai o nome do folder
    if [[ "${folder_uid}" == "null" ]]; then
      folder_name="null"
    else
      folder_name=$(jq -r --arg uid "${folder_uid}" '.[] | select(.uid == $uid) | .title' folders.json)
    fi

    # Exporta para arquivo .csv
    jq -r -r --argjson j "$j" '
            . | 
            "'"${choice}"';'"${datasource_name}"';'"${folder_name}"';\(.title);\(.isPaused);'"${grafana_url}"'/alerting/\(.uid)/edit"
            ' "${i}.json" >>"${choice}-alerts".csv
  done
  rm -f "${i}.json"
done

# Ordena pela coluna FolderName o arquivo .csv
sort -ut ';' -k 3 "${choice}-alerts".csv -o "${choice}-alerts".csv

# Adiciona um cabeçalho ao arquivo .csv
sed -i '' "1s/^/DatasourceType;DatasourceName;FolderName;AlertName;isPaused;AlertUrl\n/" "${choice}-alerts".csv

# Cleanup
rm alert-rules.json datasources.json folders.json "${choice}".txt
