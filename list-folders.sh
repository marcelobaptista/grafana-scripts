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
output_file="${date_now}-folders-report.csv"

# Endpoints para requisições
grafana_api_folders="${grafana_url}/api/folders"

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_folders}" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
	>"folders.json"; then
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

# Gera o CSV com nome, UID e URL de cada pasta
jq -r --arg grafana_url "${grafana_url}" '
    .[] | 
    (.title) + ";" +
    (.uid) + ";" +
    ($grafana_url) + "/dashboards/f/" + (.uid)
' folders.json >"${output_file}"

# Insere cabeçalho no arquivo CSV
sed -i '1i\
folderName;folderUID;folderURL
' "${output_file}"

# Remove arquivo temporário
rm -f folders.json
