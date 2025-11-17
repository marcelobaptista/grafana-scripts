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

# Endpoints para requisições
grafana_api_dashboard_uid="${grafana_url}/api/dashboards/uid"
grafana_api_search="${grafana_url}/api/search?type=dash-db&limit=5000"

# Pastas de destino para os arquivos de backup
folder_destination_api="${date_now}-dashboards-backup/api"
folder_destination_webui="${date_now}-dashboards-backup/webui"

# Arquivo de log
logfile="${date_now}-dashboards-backup.log"

# Função de logging — grava mensagem com timestamp no arquivo de log
logging()
{
  local dashboard_title=$1
  local dashboard_uid=$2
  local file=$3
  local message
  message="[$(date --iso-8601=seconds)] dashboard: ${dashboard_title}, uid: ${dashboard_uid}, file: ${PWD}/${file}"
  echo "${message}" | tee -a "${logfile}"
}

# Consulta a API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_search}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" \
  -o "dashboards.json"; then
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
jq -r '.[].uid' dashboards.json >dashboards_uid.txt

# Cria diretórios para salvar os arquivos de backup
mkdir -p "${folder_destination_api}"
mkdir -p "${folder_destination_webui}"

# Itera sobre cada dashboard UID e faz backup
while IFS= read -r uid; do

  # Salva o dashboard original em um arquivo temporário
  curl -sk "${grafana_api_dashboard_uid}/${uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" \
    | jq -r >tmp.json

  # Extrai informações necessárias para nomear o arquivo de backup
  folder_title=$(jq -r '.meta.folderTitle' tmp.json)
  dashboard_title=$(jq -r '.dashboard.title' tmp.json)
  dashboard_title_sanitized=$(jq -r '.meta.url' tmp.json | awk -F'/' '{print $NF}')

  # Cria diretório para salvar o dashboard na estrutura da interface web do Grafana
  mkdir -p "${folder_destination_webui}/${folder_title}"

  # Salva o dashboard original com estrutura JSON modificada
  # que possibilita a importação pela interface web do Grafana
  jq -r '
  {meta:.meta}+.dashboard
  ' tmp.json >"${folder_destination_webui}/${folder_title}/${dashboard_title_sanitized}.json"

  # Registra no log
  logging "${dashboard_title}" "${uid}" "${folder_destination_webui}/${folder_title}/${dashboard_title_sanitized}.json"

  # Cria diretório para salvar o dashboard na estrutura da API do Grafana
  mkdir -p "${folder_destination_api}/${folder_title}"

  # Salva o dashboard original com estrutura JSON modificada
  # que possibilita a importação pela API do Grafana
  jq -r '
    . |= (.folderUid=.meta.folderUid) 
    |del(.meta) 
    |del(.dashboard.id) + {overwrite: true}
    ' tmp.json >"${folder_destination_api}/${folder_title}/${dashboard_title_sanitized}.json"

  # Registra no log
  logging "${dashboard_title}" "${uid}" "${folder_destination_api}/${folder_title}/${dashboard_title_sanitized}.json"

  # Remove o arquivo temporário
  rm -f tmp.json

done <dashboards_uid.txt

# Remove arquivos temporários
rm -f dashboards{.json,_uid.txt}
