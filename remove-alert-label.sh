#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se a URL e o token foram passados como argumentos
if [ $# -lt 3 ]; then
	printf "\nUso do script: %s <grafana_url> <grafana_token> <folder_uid> <label>\n" "$0"
	exit 1
fi

# Argumentos passados para o script
grafana_url=$1
grafana_token=$2
folder_uid=$3
label=$4

# Endpoints para alert rules e rule groups
grafana_api_alert_rules="${grafana_url}/api/v1/provisioning/alert-rules"
grafana_api_rule_groups="${grafana_url}/api/v1/provisioning/folder/${folder_uid}/rule-groups"

# Arquivo de log
logfile="remove-alert-label.log"

# Função de logging — grava mensagem com timestamp no arquivo de log
logging() {
	local message="$1"
	echo "[$(date --iso-8601=seconds)] ${message}" | tee -a "${logfile}"
}

# Lista todas as regras de alerta configuradas
if ! curl -sk "${grafana_api_alert_rules}" \
	-H "Accept: application/json" \
	-H "Content-Type: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	> alert-rules.json; then
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

# Extrai UIDs dos alert rules
jq -r --arg folderUID "${folder_uid}" \
	'.[] | select(.folderUID == "'"${folder_uid}"'") | .uid' alert-rules.json >alert-rules.txt

# Extrai folderUIDs dos rule groups
jq -r --arg folderUID "${folder_uid}" \
	'.[] | select(.folderUID == "'"${folder_uid}"'") | .ruleGroup' alert-rules.json >rule-groups.txt

# Itera sobre cada  UID
while IFS= read -r uid; do
	if ! curl -sk "${grafana_api_alert_rules}/${uid}" \
		-H "Authorization: Bearer ${grafana_token}" \
		> temp.json; then
		logging "Aviso: falha ao baixar alert-rule ${uid}; pulando"
		continue
	fi

	# deleta a label configurada
	data_raw=$(jq --arg key "${label}" 'del(.labels[$key])' temp.json)

	# Atualiza a regra de alerta no Grafana
	if ! curl -sk -X PUT "${grafana_api_alert_rules}/${uid}" \
		-H "Accept: application/json" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${grafana_token}" \
		-d "${data_raw}" >/dev/null 2>&1; then
		logging "Erro: falha ao atualizar alert-rule ${uid}"
	else
		logging "Atualizado alert-rule ${uid} (chave '${label}' removida)"
	fi
done <"alert-rules.txt"

while IFS= read -r rulegroup; do
	# Tratamento de espaços na URL
	url="${grafana_api_rule_groups}/${rulegroup}"
	url="${url// /%20}"

	# Atualiza rule groupos, pois alert rules se tornam não editáveis
	# ao serem atualizados por meio de API.
	# Usando o endpoint de rule group voltam a ser editáveis
	if ! curl -sk "${url}" -H "Authorization: Bearer ${grafana_token}" > temp.json; then
		logging "Aviso: falha ao baixar rule-group ${rulegroup}; pulando"
		continue
	fi

	if ! curl -sk -X PUT "${url}" \
		-H "Accept: application/json" \
		-H "X-Disable-Provenance: true" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${grafana_token}" \
		-d @temp.json >/dev/null 2>&1; then
		logging "Erro: falha ao atualizar rule-group ${rulegroup}"
	else
		logging "Atualizado rule-group ${rulegroup}"
	fi
done <"rule-groups.txt"

# Remove arquivos temporários gerados pelo script
rm -f alert-rules.json temp.json alert-rules.txt rule-groups.txt
