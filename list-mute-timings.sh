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
output_file="${date_now}-mute-timings-report.csv"

# Endpoint para requisições
endpoint_mute_timings="${grafana_url}/api/v1/provisioning/mute-timings"

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${endpoint_mute_timings}" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
  -o "mute-timings.json"; then
	printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
	exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "mute-timings.json"; then
	printf "\nErro: chave de API inválida.\n"
	rm -f mute-timings.json
	exit 1
elif grep -iq "Access denied" "mute-timings.json" || grep -iq "Permissions needed" "mute-timings.json"; then
	printf "\nErro: token sem permissão suficiente.\n"
	rm -f mute-timings.json
	exit 1
fi

# Gera o CSV com informações dos mute timings
jq -r '
  (["name","weekdays","days_of_month","months","years","times","location"] | join(";")),
  map(select(type=="object" and has("time_intervals")))[] as $mute |
    $mute.time_intervals[] as $interval |
    [
      $mute.name,
      ($interval.weekdays // ["-"] | join(",")),
      ($interval.days_of_month // ["-"] | join(",")),
      ($interval.months // ["-"] | join(",")),
      ($interval.years // ["-"] | join(",")),
      (if ($interval.times // null) then ($interval.times | map(.start_time + "-" + .end_time) | join(",")) else "-" end),
      ($interval.location // "-")
    ] | join(";")
' mute-timings.json >"${output_file}"

# Remove arquivo temporário
rm -f mute-timings.json
