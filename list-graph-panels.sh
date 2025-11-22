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
output_file="${date_now}-grafana-graph-panels.csv"

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_url}/api/search?type=dash-db&limit=5000" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
	-o "dashboards.json"; then
	printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
	rm -f "dashboards.json"
	exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "dashboards.json"; then
	printf "\nErro: chave de API inválida.\n"
	rm -f "dashboards.json"
	exit 1
elif grep -iq "Access denied" "dashboards.json" || grep -iq "Permissions needed" "dashboards.json"; then
	printf "\nErro: token sem permissão suficiente.\n"
	rm -f "dashboards.json"
	exit 1
fi

# Cria lista de UIDs dos dashboards
jq -r '.[].uid' dashboards.json >dashboards-uids.txt

# Itera sobre cada UID e extrai informações
while IFS= read -r uid; do

	# Salva o dashboard em um arquivo temporário
	curl -# -sk "${grafana_url}/api/dashboards/uid/${uid}" \
		-H "Accept: application/json" \
		-H "Authorization: Bearer ${grafana_token}" \
		-H "Content-Type: application/json" |
		jq -r >"dashboard-${uid}.json"

	# Extrai número de painéis no dashboard
	panels_length=$(jq -r '.dashboard.panels | length' "dashboard-${uid}.json")

	# Loop através de todos os painéis do dashboard
	for ((i = 0; i < panels_length; i++)); do

		# Verifica o tipo do painel
		panel_type=$(jq -r --argjson i "${i}" '.dashboard.panels[$i].type' "dashboard-${uid}.json")

		# Verifica se o tipo do painel é "graph"
		if [ "${panel_type}" != "graph" ]; then continue; fi

		# Se o painel for do tipo "graph", coleta o ID do painel
		panel_id=$(jq -r --argjson i "${i}" '.dashboard.panels[$i].id' "dashboard-${uid}.json")

		# Adiciona informações do painel ao arquivo CSV
		jq -r --arg grafana_url "${grafana_url}" \
			--arg panel_id "${panel_id}" \
			'. |
        (.meta.folderTitle | tostring) + ";" +
        (.dashboard.title | tostring) + ";" +
        ($grafana_url) + (.meta.url) + "?viewPanel=" +($panel_id | tostring))
    ' "dashboard-${uid}.json" >>"${output_file}"

	done

	# Remove arquivo temporário
	rm -f "dashboard-${uid}.json"

done <dashboards-uids.txt

# Verifica se algum painel do tipo graph foi encontrado
if [ ! -s "${output_file}" ]; then
	printf "\nNenhum painel do tipo 'graph' foi encontrado.\n"
	rm -rf dashboards{.json,-uids.txt}
	exit 0
fi

# Remove linhas duplicadas, se houver
sort -u "${output_file}" -o "${output_file}"

# Insere cabeçalho no arquivo CSV
sed -i '1i\
dashboardFolder;dashboardName;url
' "${output_file}"

# Remove arquivos temporários
rm -rf dashboards{.json,-uids.txt}
