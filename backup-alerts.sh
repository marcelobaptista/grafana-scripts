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
grafana_api_folders="${grafana_url}/api/folders"
grafana_api_alert_rules="${grafana_url}/api/v1/provisioning/alert-rules"

# Pasta de destino para os arquivos de backup
folder_destination="${date_now}-alert-rules-backup"

# Arquivo de log
logfile="${date_now}-alert-rules-backup.log"

# Função de logging — grava mensagem com timestamp no arquivo de log
logging()
{
  local alert_rule_name=$1
  local alert_rule_uid=$2
  local file=$3
  local message
  message="[$(date --iso-8601=seconds)] alert_rule: ${alert_rule_name}, uid: ${alert_rule_uid}, file: ${PWD}/${file}"
  echo "${message}" | tee -a "${logfile}"
}

# Consulta a API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_alert_rules}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" \
  -o "alert-rules.json"; then
  printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
  rm -f "alert-rules.json"
  exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "alert-rules.json"; then
  printf "\nErro: chave de API inválida.\n"
  rm -f "alert-rules.json"
  exit 1
elif grep -iq "Access denied" "alert-rules.json" || grep -iq "Permissions needed" "alert-rules.json"; then
  printf "\nErro: token sem permissão suficiente.\n"
  rm -f "alert-rules.json"
  exit 1
fi

# Cria lista de UIDs das pastas
jq -r '
      .[] | 
      select (.folderUID != "") | 
      .folderUID' alert-rules.json \
  | sort -u >folders_uids.txt

# Itera sobre cada folder UID e cria diretórios para salvar os arquivos de backup
while read -r folder_uid; do

  # Cria arquivo temporário para extrair o título da pasta
  curl -sk "${grafana_api_folders}/${folder_uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" >tmp.json

  # Extrai o título da pasta
  folder_title=$(jq -r '.title' tmp.json)

  # Cria diretório para salvar os arquivos de backup do folder
  mkdir -p "${folder_destination}/${folder_title}"

  # Salva o mapeamento folder_uid;folder_title em um arquivo CSV
  echo "${folder_uid};${folder_title}" >>folders.csv

  # Remove o arquivo temporário
  rm -f tmp.json

done <folders_uids.txt

# Itera sobre cada folder UID e faz backup dos alertas
while IFS=';' read -r folder_uid folder_title; do

  # Filtra os alertas por folderUID
  jq -r --arg folder_uid "${folder_uid}" '
    [.[] | 
    select (.folderUID == $folder_uid)]' alert-rules.json >"${folder_uid}.json"

  # Obtém o número de alertas no arquivo JSON do folderUID
  length=$(jq -r '. | length' "${folder_uid}.json")

  # Itera sobre os alertas do folderUID
  for ((i = 0; i < length; i++)); do

    # Extrai o UID do alerta
    alert_uid=$(jq -r --argjson i "${i}" '.[$i].uid' "${folder_uid}.json")

    # Formata o título do alerta para ser usado como nome de arquivo
    alert_title=$(jq -r --argjson i "${i}" '.[$i].title' "${folder_uid}.json" \
      | tr '[:upper:]' '[:lower:]' \
      | tr ' /' '-' \
      | iconv -c -f utf8 -t ascii//TRANSLIT \
      | sed 's/[^a-z0-9-]//g' \
      | sed 's/-\{2,\}/-/g' \
      | sed 's/^-\|-$//g' || true)

    # Cria o arquivo JSON do alerta
    curl -sk "${grafana_api_alert_rules}/${alert_uid}" \
      -H "Accept: application/json" \
      -H "Authorization: Bearer ${grafana_token}" \
      -H "Content-Type: application/json" \
      | jq 'del(.id)' >"${folder_destination}/${folder_title}/${alert_title}.json"

    # Registra no log
    logging "${alert_title}" "${alert_uid}" "${folder_destination}/${folder_title}/${alert_title}.json"

  done
  
  # Remove o arquivo JSON temporário
  rm -f "${folder_uid}.json"

done <folders.csv

# Remove arquivos temporários
rm -f alert-rules.json folders{_uids.txt,.csv}
