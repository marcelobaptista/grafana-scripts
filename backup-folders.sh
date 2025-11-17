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
  local fd_title=$1
  local fd_uid=$2
  local file=$3
  local message
  message="[$(date --iso-8601=seconds)] folder: ${fd_title}, uid: ${fd_uid}, file: ${PWD}/${file}"
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
jq -r '.[].uid' folders.json >folders_uid.txt

# Cria diretório para salvar os arquivos de backup
mkdir -p "${folder_destination}"

# Itera sobre cada folder UID e faz backup
while IFS= read -r folder_uid; do

  # Faz backup da pasta deletando o campo id
  curl -sk "${grafana_api_folders}/${folder_uid}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" \
    | jq -r 'del(.id)' >"${folder_uid}.json"

  # Extrai o nome da pasta para nomear o arquivo de backup
  folder_title=$(jq -r '.url' -- "${folder_uid}.json" | awk -F'/' '{print $NF}')

  # Renomeia o arquivo e move para o diretório de backup
  mv -- "${folder_uid}.json" "${folder_destination}/${folder_title}.json"

  # Registra no log
  logging "${folder_title}" "${folder_uid}" "${folder_destination}/${folder_title}.json"

done <folders_uid.txt

# Remove arquivos temporários
rm -f folders{.json,_uid.txt}