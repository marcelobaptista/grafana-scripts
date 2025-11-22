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
grafana_api_mute_timings="${grafana_url}/api/v1/provisioning/mute-timings"

# # Pasta de destino para os arquivos de backup
folder_destination="${date_now}-mute-timings-backup"

# Arquivo de log
logfile="${date_now}-mute-timings-backup.log"

# Função de logging — grava mensagem com timestamp no arquivo de log
logging() {
  local mute_timing_title=$1
  local mute_timing_uid=$2
  local file=$3
  local message
  message="[$(date --iso-8601=seconds)] mute-timing: ${mute_timing_title}, uid: ${mute_timing_uid}, file: ${file}"
  echo "${message}" | tee -a "${logfile}"
}

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_mute_timings}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${grafana_token}" \
  -H "Content-Type: application/json" \
  > "mute-timings.json"; then
  printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
  exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "mute-timings.json"; then
  printf "\nErro: chave de API inválida.\n"
  rm -f "mute-timings.json"
  exit 1
elif grep -iq "Access denied" "mute-timings.json" || grep -iq "Permissions needed" "mute-timings.json"; then
  printf "\nErro: token sem permissão suficiente.\n"
  rm -f "mute-timings.json"
  exit 1
fi

# Cria lista de nomes dos mute timings do Grafana
jq -r '.[].name' mute-timings.json >mute-timings-names.txt

# Cria diretório para salvar os arquivos de backup
mkdir -p "${folder_destination}"

# Itera sobre cada mute timing e faz backup
while IFS= read -r mute_timing_name; do

  # Faz encoding correto do nome para uso na URL
  name=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "${mute_timing_name}")

  # Formata o título do mute timing para ser usado como nome de arquivo
  mute_timing_name_sanitized=$(python3 -c "import sys, unicodedata, re; s=sys.argv[1].lower(); s=unicodedata.normalize('NFKD', s).encode('ascii','ignore').decode('ascii'); s=re.sub(r'[^a-z0-9]+', '-', s); s=re.sub(r'-+', '-', s); print(s.strip('-'))" "${mute_timing_name}")

  # Salva o mute timing em um arquivo JSON
  curl -sk "${grafana_api_mute_timings}/${name}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json" |
    jq -r >"${folder_destination}/${mute_timing_name_sanitized}.json"

  # Registra no log
  logging "${mute_timing_name}" "${mute_timing_name_sanitized}" "${folder_destination}/${mute_timing_name_sanitized}.json"

done <mute-timings-names.txt

# Remove arquivos temporários
rm -f mute-timings{.json,-names.txt}
