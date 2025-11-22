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
grafana_api_dashboards="${grafana_url}/api/dashboards"
grafana_api_search="${grafana_url}/api/search?type=dash-db&limit=5000"

# Pastas de destino de backup dos dashboards atualizados e originais
folder_destination_original="${date_now}-original-dashboards"
folder_destination_updated="${date_now}-updated-dashboards"

# Arquivo de log
logfile="${date_now}-dashboards-backup.log"

# # Função de logging para backups
logging_backup()
{
  local dashboard_title=$1
  local dashboard_uid=$2
  local file=$3
  local message
  message="[$(date --iso-8601=seconds)] dashboard: ${dashboard_title}, uid: ${dashboard_uid}, file: ${file}"
  echo "${message}" | tee -a "${logfile}"
}

#  Função de logging para dashboards atualizados (de graph para timeseries)
logging_updated()
{
  local dashboard_title=$1
  local dashboard_uid=$2
  local message
  message="[$(date --iso-8601=seconds)] dashboard_updated: ${dashboard_title}, uid: ${dashboard_uid}"
  echo "${message}" | tee -a "${logfile}"
}

# CConsulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_search}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" \
  >"dashboards.json"; then
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
jq -r '.[].uid' dashboards.json >dashboards-uid.txt

# Cria diretórios para salvar os arquivos de backup
mkdir -p "${folder_destination_original}"
mkdir -p "${folder_destination_updated}"

# Itera sobre cada dashboard UID
while IFS= read -r uid; do

  # Salva o dashboard original em um arquivo temporário
  curl -sk "${grafana_api_dashboards}/uid/${uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" \
    | jq -r >"dashboard-${uid}"

  # Verifica se existe painel do tipo "timeseries" no dashboard
  verify_graph_panel=$(grep -c '"type": "graph"' "dashboard-${uid}")

  # Se não existir, remove o arquivo temporário e continua o loop
  if [ "${verify_graph_panel}" -eq 0 ]; then
    rm -f "dashboard-${uid}"
    continue
  fi

  # Extrai o nome do folder
  folder_title=$(jq -r '.meta.folderTitle' "dashboard-${uid}")

  # Extrai o nome do dashboard
  dashboard_title=$(jq -r '.dashboard.title' "dashboard-${uid}")

  # Formata o nome do dashboard para ser usado como nome de arquivo
  dashboard_title_sanitized=$(jq -r '.meta.url' "dashboard-${uid}" | awk -F'/' '{print $NF}')

  # Cria diretório para backup do dashboard original
  mkdir -p "${folder_destination_original}/${folder_title}"

  # Salva o dashboard original com estrutura JSON modificada
  # que possibilita a importação pela interface web do Grafana
  jq -r '
  {meta:.meta}+.dashboard
  ' "dashboard-${uid}" >"${folder_destination_original}/${folder_title}/${dashboard_title_sanitized}-${uid}.json"

  # Registra no log
  logging_backup "${dashboard_title}" "${uid}" "${folder_destination_original}/${folder_title}/${dashboard_title_sanitized}-${uid}.json"

  # Cria diretório para salvar o dashboard na estrutura da API do Grafana
  mkdir -p "${folder_destination_updated}/${folder_title}"

  # Salva o dashboard original com estrutura JSON modificada
  # que possibilita a importação pela API do Grafana
  jq -r '
    . |= (.folderUid=.meta.folderUid) 
    |del(.meta) 
    |del(.dashboard.id) + {overwrite: true}
    ' "dashboard-${uid}" >"${folder_destination_updated}/${folder_title}/${dashboard_title_sanitized}-${uid}.json"

  # Remove arquivo temporário
  rm -f "dashboard-${uid}"

done <"dashboards-uid.txt"

# Itera sobre cada dashboard atualizado e faz a alteração dos painéis de graph para timeseries
for dashboard_updated in "${folder_destination_updated}"/*/*.json; do

  # Altera os painéis do tipo "graph" para "timeseries"
  sed -i 's/"type": "graph"/"type": "timeseries"/g' "${dashboard_updated}"

  # Atualiza o dashboard usando a API do Grafana
  curl -sk -X POST "${grafana_api_dashboards}/db" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" \
    -d @"${dashboard_updated}"

  # Registra no log
  logging_update "${dashboard_title}" "${dashboard_uid}"

done

# Remove arquivos temporários
rm -f dashboards{.json,-uid.txt}
