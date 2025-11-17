#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se a url e o token foram passados como argumentos
if [ $# -lt 2 ]; then
    printf "\nUso do script: %s <grafana_url> <grafana_token>\n" "$0"
    exit 1
fi

# Argumentos passados para o script
grafana_url=$1
grafana_token=$2

# Define a data atual
date_now=$(date +%Y-%m-%d)

# Arquivo de saída
output_file="${date_now}-grafana-dashboards.csv"

# Consulta API do Grafana para obter a lista de dashboards e salva os UIDs em um arquivo
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
jq -r '.[].uid' dashboards.json >dashboards_uid.txt

# Itera sobre cada UID e extrai informações
while IFS= read -r uid; do

    # Salva o dashboard em um arquivo temporário
    curl -# -sk "${grafana_url}/api/dashboards/uid/${uid}" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer ${grafana_token}" \
        -H "Content-Type: application/json" \
        | jq -r >temp.json

    # Extrai as informações e adiciona ao arquivo CSV
    jq -r --arg grafana_url "${grafana_url}" \
        '. |
        (.meta.folderTitle | tostring) + ";" +
        (.dashboard.title | tostring) + ";" +
        ($grafana_url) + (.meta.url) + ";" +
        (.dashboard.time.from | tostring) + ";" +
        (.dashboard.time.to | tostring) + ";" +
        (.dashboard.refresh | tostring) + ";" +
        (.meta.created | tostring) + ";" +
        (.meta.createdBy | tostring) + ";" +
        (.meta.updated | tostring) + ";" +
        (.meta.updatedBy | tostring) + ";" +
        (.dashboard.editable // true | tostring) + ";" +
        (.meta.provisioned // false | tostring)
    ' temp.json >>"${output_file}"

    # Remove arquivo temporário
    rm -f temp.json
done <"dashboards_uid.txt"

# Remove linhas duplicadas, se houver
sort -u "${output_file}" -o "${output_file}"

# Adiciona um cabeçalho no arquivo CSV
sed -i '1i\
folderTitle;dashboardTitle;url;timeFrom;timeTo;refresh;created;createdBy;updated;updatedBy;editable;provisioned
' "${output_file}"

# Remove arquivos temporários
rm -f dashboards{_uid.txt,_uid.json,.json}
