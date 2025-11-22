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
logging() {
	local alert_title=$1
	local alert_rule_uid=$2
	local file=$3
	local message
	message="[$(date --iso-8601=seconds)] alert_rule: ${alert_title}, uid: ${alert_rule_uid}, file: ${file}"
	echo "${message}" | tee -a "${logfile}"
}

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_alert_rules}" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
	>"alert-rules.json"; then
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
      .folderUID' alert-rules.json |
	sort -u >alert-rules-folders-uids.txt

# Itera sobre cada folder UID e cria diretórios para salvar os arquivos de backup
while read -r folder_uid; do

	# Cria arquivo temporário para extrair o título do folder
	curl -sk "${grafana_api_folders}/${folder_uid}" \
		-H "Accept: application/json" \
		-H "Authorization: Bearer ${grafana_token}" \
		-H "Content-Type: application/json" >"alert-rule-folder-${folder_uid}.json"

	# Extrai o título do folder
	folder_title=$(jq -r '.title' "alert-rule-folder-${folder_uid}.json")

	# Cria diretório para salvar os arquivos de backup
	mkdir -p "${folder_destination}/${folder_title}"

	# Salva o mapeamento folder_uid;folder_title em um arquivo CSV
	echo "${folder_uid};${folder_title}" >>alert-rules-folders.csv

	# Remove arquivo temporário
	rm -f "alert-rule-folder-${folder_uid}.json"

done <alert-rules-folders-uids.txt

# Itera sobre cada folder UID e faz backup dos alertas
while IFS=';' read -r folder_uid folder_title; do

	# Filtra os alertas por folder_uid
	jq -r --arg folder_uid "${folder_uid}" '
    [.[] | 
    select (.folderUID == $folder_uid)]' alert-rules.json >"alert-rule-folder-${folder_uid}.json"

	# Obtém o número de alertas no arquivo JSON do folder_uid
	length=$(jq -r '. | length' "alert-rule-folder-${folder_uid}.json")

	# Itera sobre os alertas do folder_uid
	for ((i = 0; i < length; i++)); do

		# Extrai o UID do alerta
		alert_uid=$(jq -r --argjson i "${i}" '.[$i].uid' "alert-rule-folder-${folder_uid}.json")

		# Extrai o título do alerta
		alert_title=$(jq -r --argjson i "${i}" '.[$i].title' "alert-rule-folder-${folder_uid}.json")

		# Formata o título do alerta para ser usado como nome de arquivo
		alert_title_sanitized=$(python3 -c "import sys, unicodedata, re; s=sys.argv[1].lower(); s=unicodedata.normalize('NFKD', s).encode('ascii','ignore').decode('ascii'); s=re.sub(r'[^a-z0-9]+', '-', s); s=re.sub(r'-+', '-', s); print(s.strip('-'))" "${alert_title}")

		# Salva o alerta, removendo o campo id, em um arquivo JSON
		curl -sk "${grafana_api_alert_rules}/${alert_uid}" \
			-H "Accept: application/json" \
			-H "Authorization: Bearer ${grafana_token}" \
			-H "Content-Type: application/json" |
			jq 'del(.id)' >"${folder_destination}/${folder_title}/${alert_title_sanitized}-${alert_uid}.json"

		# Registra no log
		logging "${alert_title}" "${alert_uid}" "${folder_destination}/${folder_title}/${alert_title_sanitized}-${alert_uid}.json"

	done

	# Remove arquivo temporário
	rm -f "alert-rule-folder-${folder_uid}.json"

done <alert-rules-folders.csv

# Remove arquivos temporários
rm -f alert-rules{.json,-folders.csv,-folders-uids.txt}
