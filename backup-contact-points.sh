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
grafana_api_contact_points="${grafana_url}/api/v1/provisioning/contact-points"

# Pasta de destino para os arquivos de backup
folder_destination="${date_now}-contact-points-backup"

# Arquivo de log
logfile="${date_now}-contact-points-backup.log"

# Função de logging — grava mensagem com timestamp no arquivo de log
logging() {
	local contact_point_name=$1
	local contact_point_uid=$2
	local file=$3
	local message
	message="[$(date --iso-8601=seconds)] contact-point: ${contact_point_name}, uid: ${contact_point_uid}, file: ${file}"
	echo "${message}" | tee -a "${logfile}"
}

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_contact_points}" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
	>"contact-points.json"; then
	printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
	exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "contact-points.json"; then
	printf "\nErro: chave de API inválida.\n"
	rm -f "contact-points.json"
	exit 1
elif grep -iq "Access denied" "contact-points.json" || grep -iq "Permissions needed" "contact-points.json"; then
	printf "\nErro: token sem permissão suficiente.\n"
	rm -f "contact-points.json"
	exit 1
fi

# Cria lista de UIDs dos contact points
jq -r '.[].uid' contact-points.json | sort -u >contact-points-uid.txt

# Cria diretório para salvar os arquivos de backup
mkdir -p "${folder_destination}"

# Itera sobre cada contact point UID e faz backup dos contact points
while IFS= read -r uid; do

	# Extrai o nome do contact point
	contact_point_name=$(jq -r --arg uid "${uid}" '.[] | select(.uid == $uid) | .name' contact-points.json)

	# Formata o título do contact point para ser usado como nome de arquivo
	contact_point_name_sanitized=$(python3 -c "import sys, unicodedata, re; s=sys.argv[1].lower(); s=unicodedata.normalize('NFKD', s).encode('ascii','ignore').decode('ascii'); s=re.sub(r'[^a-z0-9]+', '-', s); s=re.sub(r'-+', '-', s); print(s.strip('-'))" "${contact_point_name}")

	# Salva o contact point em um arquivo JSON
	jq -r --arg uid "${uid}" '
    .[] | 
    select(.uid == $uid)
    ' contact-points.json >"${folder_destination}/${contact_point_name_sanitized}-${uid}.json"

	# Registra no log
	logging "${contact_point_name}" "${uid}" "${folder_destination}/${contact_point_name_sanitized}-${uid}.json"

done <contact-points-uid.txt

# Remove arquivos temporários
rm -f contact-points{.json,-uid.txt}
