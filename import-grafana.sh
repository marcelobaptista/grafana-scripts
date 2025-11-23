#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se a URL e o token foram passados como argumentos
if [ $# -lt 3 ]; then
	echo "Usage: $0 <grafana_url> <grafana_token> <origin>"
	exit 1
fi

# Argumentos passados para o script
grafana_url=$1
grafana_token=$2
origin=$3

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_url}/api/org" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
  -o "org.json"; then
	printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
	exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "org.json"; then
	printf "\nErro: chave de API inválida.\n"
	rm -f "org.json"
	exit 1
elif grep -iq "Access denied" "org.json" || grep -iq "Permissions needed" "org.json"; then
	printf "\nErro: token sem permissão suficiente.\n"
	rm -f "org.json"
	exit 1
fi

# Remove arquivo temporário
rm -f "org.json"

# Define a data atual para
import_date=$(date +%Y-%m-%d)

echo "Escolha o tipo para importar:"
echo ""
echo "1) datasources"
echo "2) teams"
echo "3) folders"
echo "4) dashboards"
echo "5) contact points"
echo "6) mute timings"
echo "7) notification policies"
echo "8) alert rules"
echo ""
read -rp "Digite o número da opção: " option

case "${option}" in
1)
	api_endpoint="${grafana_url}/api/datasources"
	logfile="${import_date}-datasources-import.log"
	;;
2)
	api_endpoint="${grafana_url}/api/teams"
	logfile="${import_date}-teams-import.log"
	;;
3)
	api_endpoint="${grafana_url}/api/folders"
	logfile="${import_date}-folders-import.log"
	;;
4)
	api_endpoint="${grafana_url}/api/dashboards/db"
	logfile="${import_date}-dashboards-import.log"
	;;
5)
	api_endpoint="${grafana_url}/api/v1/provisioning/contact-points"
	logfile="${import_date}-contact-points-import.log"
	;;
6)
	api_endpoint="${grafana_url}/api/v1/provisioning/mute-timings"
	logfile="${import_date}-mute-timings-import.log"
	;;
7)
	clear
	logfile="${import_date}-notification-policies-import.log"
	find "./${origin}" -type f -name '*.json' |
		while read -r json; do
			curl -sk -XPUT "${grafana_url}/api/v1/provisioning/policies" \
				-H "Accept: application/json" \
				-H "Authorization: Bearer ${grafana_token}" \
				-H "Content-Type: application/json" -H "X-Disable-Provenance: true" \
				-d @"${json}" | jq -c | tee -a "${logfile}"
		done
	exit 0
	;;
8)
	api_endpoint="${grafana_url}/api/v1/provisioning/alert-rules"
	logfile="${import_date}-alert-rules-import.log"
	;;
*)
	echo "Opção inválida."
	exit 1
	;;
esac

clear
find "./${origin}" -type f -name '*.json' |
	while read -r json; do
		curl -sk -XPOST "${api_endpoint}" \
			-H "Accept: application/json" \
			-H "Content-Type: application/json" \
			-H "X-Disable-Provenance: true" \
			-H "Authorization: Bearer ${grafana_token}" \
			-d @"${json}" | jq -c | tee -a "${logfile}"
	done
