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
output_file="${date_now}-contact-points-report.csv"

# Endpoint para requisições
grafana_api_contact_points="${grafana_url}/api/v1/provisioning/contact-points"

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
	rm -f contact-points.json
	exit 1
elif grep -iq "Access denied" "contact-points.json" || grep -iq "Permissions needed" "contact-points.json"; then
	printf "\nErro: token sem permissão suficiente.\n"
	rm -f contact-points.json
	exit 1
fi

# Gera o CSV com informações dos contact points
jq -r '.[] |
      (.name) + ";" +
      (.uid) + ";" +
      (.type) + ";" +
      (.settings.url) + ";" +
      (.disableResolveMessage|tostring)' contact-points.json >"${output_file}"

# Ordena e remove linhas duplicadas, se houver
sort -u "${output_file}" -o "${output_file}"

# Insere cabeçalho no arquivo CSV
sed -i '1i\
name;uid;type;url;disableResolveMessage
' "${output_file}"

# Remove arquivo temporário
rm -f contact-points.json
