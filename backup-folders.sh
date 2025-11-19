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

# Endpoint para requisições
grafana_api_folders="${grafana_url}/api/folders"

# Pasta de destino para os arquivos de backup
folder_destination="${date_now}-folders-backup"

# Arquivo de log
logfile="${date_now}-folders-backup.log"

# Função de logging — grava mensagem com timestamp no arquivo de log
logging() {
  local folder_title=$1
  local folder_uid=$2
  local file=$3
  local message
  message="[$(date --iso-8601=seconds)] folder: ${folder_title}, uid: ${folder_uid}, file: ${file}"
  echo "${message}" | tee -a "${logfile}"
}

# Consulta a API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_folders}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" \
  -o "folders.json"; then
  printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
  exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "folders.json"; then
  printf "\nErro: chave de API inválida.\n"
  rm -f "folders.json"
  exit 1
elif grep -iq "Access denied" "folders.json" || grep -iq "Permissions needed" "folders.json"; then
  printf "\nErro: token sem permissão suficiente.\n"
  rm -f "folders.json"
  exit 1
fi

# Cria lista de UIDs das pastas do Grafana
jq -r '.[].uid' folders.json >folders-uid.txt

# Cria diretório para salvar os arquivos de backup
mkdir -p "${folder_destination}"

# Itera sobre cada folder UID e faz backup
while IFS= read -r folder_uid; do

  # Salva a pasta, removendo o campo id, em um arquivo JSON
  curl -sk "${grafana_api_folders}/${folder_uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" |
    jq -r 'del(.id)' >folder.json

  # Extrai o nome da pasta
  folder_title=$(jq -r '.title' folder.json)

  # Formata o nome da pasta para ser usado como nome de arquivo
  folder_title_sanitized=$(jq -r '.url' folder.json | awk -F'/' '{print $NF}')

  # Renomeia o arquivo e move para o diretório de backup
  mv folder.json "${folder_destination}/${folder_title_sanitized}-${folder_uid}.json"

  # Registra no log
  logging "${folder_title}" "${folder_uid}" "${folder_destination}/${folder_title_sanitized}-${folder_uid}.json"

done <folders-uid.txt

# Remove arquivos temporários
rm -f folders{.json,-uid.txt}
