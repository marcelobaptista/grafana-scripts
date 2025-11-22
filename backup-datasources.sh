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
grafana_api_datasources="${grafana_url}/api/datasources"

# Pasta de destino para os arquivos de backup
folder_destination="${date_now}-datasources-backup"

# Arquivo de log
logfile="${date_now}-datasources-backup.log"

# Função de logging — grava mensagem com timestamp no arquivo de log
logging() {
	local datasource_name=$1
	local datasource_uid=$2
	local file=$3
	local message
	message="[$(date --iso-8601=seconds)] datasource: ${datasource_name}, uid: ${datasource_uid}, file: ${file}"
	echo "${message}" | tee -a "${logfile}"
}

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_datasources}" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
	>"datasources.json"; then
	printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
	exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "datasources.json"; then
	printf "\nErro: chave de API inválida.\n"
	rm -f "datasources.json"
	exit 1
elif grep -iq "Access denied" "datasources.json" || grep -iq "Permissions needed" "datasources.json"; then
	printf "\nErro: token sem permissão suficiente.\n"
	rm -f "datasources.json"
	exit 1
fi

# Cria lista de UIDs dos datasources
jq -r '.[].uid' datasources.json >datasources_uid.txt

# Cria diretório para salvar os arquivos de backup
mkdir -p "${folder_destination}"

# Itera sobre cada datasource UID e faz backup dos datasources
while IFS= read -r datasource_uid; do

	# Extrai o nome do datasource
	datasource_name=$(
		jq -r --arg datasource_uid "${datasource_uid}" '
    .[] | select(.uid == "'"${datasource_uid}"'") |.name
  ' datasources.json
	)

	# Formata o título do datasource para ser usado como nome de arquivo
	datasource_name_sanitized=$(python3 -c "import sys, unicodedata, re; s=sys.argv[1].lower(); s=unicodedata.normalize('NFKD', s).encode('ascii','ignore').decode('ascii'); s=re.sub(r'[^a-z0-9]+', '-', s); s=re.sub(r'-+', '-', s); print(s.strip('-'))" "${datasource_name}")

	# Salva o datasource, removendo o campo id, em um arquivo JSON
	jq -r --arg datasource_uid "${datasource_uid}" \
		'.[] | 
    select(.uid == "'"${datasource_uid}"'") | 
    del(.id)
    ' datasources.json >"${folder_destination}/${datasource_name_sanitized}-${datasource_uid}.json"

	# Registra no log
	logging "${datasource_name}" "${datasource_uid}" "${folder_destination}/${datasource_name_sanitized}-${datasource_uid}.json"

done <datasources_uid.txt

# Remove arquivos temporários
rm -f datasources{.json,_uid.txt}
