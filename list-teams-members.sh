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

# Nome do arquivo de saída
output_file="${date_now}-grafana-teams-members.csv"

#
grafana_api_teams="${grafana_url}/api/teams"

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_teams}" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
	-o "teams.json"; then
	printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
	rm -f "teams.json"
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
jq -r '.teams[] | .id' "teams.json" >"teams_ids.txt"

# Itera sobre cada UID e extrai informações
while IFS= read -r team_id; do

	# Salva o team em um arquivo temporário

	curl -# -sk "${grafana_api_teams}/${team_id}" \
		-H "Accept: application/json" \
		-H "Authorization: Bearer ${grafana_token}" \
		-H "Content-Type: application/json" |
		jq -r >"${team_id}.json"

	# Extrai nome do team
	name=$(jq -r '.name' "${team_id}.json")

	# Lista os usuários existentes no team e salva em um arquivo temporário
	curl -sk "${grafana_api_teams}/${team_id}/members" \
		-H "Accept: application/json" \
		-H "Authorization: Bearer ${grafana_token}" \
		-H "Content-Type: application/json" |
		jq -r '.[] | "'"${name}"';\(.login)"' >>"${output_file}"

	# Remove arquivo temporário do team
	rm -f "${team_id}.json"

done <"teams_ids.txt"

# Insere cabeçalho no arquivo CSV
sed -i '1i\
Name;Login
' "${output_file}"

# Remove arquivos temporários
rm -f teams{.json,_ids.txt}
