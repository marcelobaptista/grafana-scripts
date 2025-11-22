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
grafana_api_teams="${grafana_url}/api/teams"

# Pasta de destino para os arquivos de backup
folder_destination="${date_now}-teams-backup"

# Arquivo de log
logfile="${date_now}-teams-backup.log"

# Função de logging — grava mensagem com timestamp no arquivo de log
logging()
{
  local team_name=$1
  local team_id=$2
  local file=$3
  local message
  message="[$(date --iso-8601=seconds)] team-name: ${team_name}, uid: ${team_id}, file: ${file}"
  echo "${message}" | tee -a "${logfile}"
}

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_teams}/search?" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" \
  >"teams.json"; then
  printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
  exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "teams.json"; then
  printf "\nErro: chave de API inválida.\n"
  rm -f "teams.json"
  exit 1
elif grep -iq "Access denied" "teams.json" || grep -iq "Permissions needed" "teams.json"; then
  printf "\nErro: token sem permissão suficiente.\n"
  rm -f "teams.json"
  exit 1
fi

# Cria lista de UIDs dos teams
jq -r '.teams[].id' teams.json >teams-ids.txt

# Cria diretório para salvar os arquivos de backup
mkdir -p "${folder_destination}"

# Itera sobre cada folder UID e faz backup
while IFS= read -r team_id; do

  # Salva o team, removendo os campos id e uid, em um arquivo JSON
  curl -sk "${grafana_api_teams}/${team_id}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" \
    | jq -r 'del(.id, .uid)' >"team-${team_id}.json"

  # Extrai o nome do team
  team_name=$(jq -r --arg uid "${team_id}" '.name' "team-${team_id}.json")

  # Formata o nome do team para ser usado como nome de arquivo
  team_name_sanitized=$(python3 -c "import sys, unicodedata, re; s=sys.argv[1].lower(); s=unicodedata.normalize('NFKD', s).encode('ascii','ignore').decode('ascii'); s=re.sub(r'[^a-z0-9]+', '-', s); s=re.sub(r'-+', '-', s); print(s.strip('-'))" "${team_name}")

  # Renomeia o arquivo e move para o diretório de backup
  mv "team-${team_id}.json" "${folder_destination}/${team_name_sanitized}-${team_id}.json"

  # Registra no log
  logging "${team_name}" "${team_id}" "${folder_destination}/${team_name_sanitized}-${team_id}.json"

done <teams-ids.txt

# Remove arquivos temporários
rm -f teams{.json,-ids.txt}
