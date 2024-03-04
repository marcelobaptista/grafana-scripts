#!/bin/bash

#####################################################################
# Script para listar todos os dashboards do Grafana e gerar um CSV #
#####################################################################

# Este script solicita a URL do Grafana, um token de acesso à API do Grafana 
# e o nome do arquivo de saída. Em seguida, ele lista todos os dashboards disponíveis
# no Grafana e os salva em um arquivo CSV com as seguintes colunas:
# Folder;Dashboard;Version;createdBy;Created;UpdatedBy;Updated;URL

# Habilita o modo de saída de erro
set -e

# Função para exibir mensagem de erro e sair
exit_with_error() {
    echo "Erro: $1"
    exit 1
}

# Função para testar o acesso à API do Grafana
grafana_check_api() {
    check_api=$(curl -sk -X GET "${grafana_url}/api/org" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${token}")
    if [[ -z "${check_api}" ]]; then
        exit_with_error "Verifique a URL fornecida"
    fi
    if [[ "${check_api}" == *"Invalid API key"* ]]; then
        exit_with_error "Token inválido"
    fi
}

# Função para fazer a solicitação à API Grafana
grafana_api_request() {
    local url="$1"
    local token="$2"
    curl -sk -H "Authorization: Bearer ${token}" "${url}"
}

# Função para listar todos os dashboards
list_dashboards() {
    grafana_api_request "${grafana_url}/api/search?type=dash-db&limit=5000" "${token}" |
        jq -r '.[].uid' >dashboards_uid.txt
    while IFS= read -r uid; do
        grafana_api_request "${grafana_url}/api/dashboards/uid/${uid}" "${token}" |
            jq -r '. |
"\(.meta.folderTitle);\(.dashboard.title);\(.meta.version);\(.meta.createdBy);\(.meta.created);\(.meta.updatedBy);\(.meta.updated);'"${grafana_url}"'\(.meta.url)"'
    done <"dashboards_uid.txt" >"${file}.csv"
    sed -i "1s/^/Folder;Dashboard;Version;createdBy;Created;UpdatedBy;Updated;URL\n/" "${file}.csv"
    rm dashboards_uid.txt
    printf "Arquivo %s${file}.csv gerado com sucesso: \n"
}

# Solicita a URL do Grafana
printf "Digite a URL do Grafana (ex: http://127.0.0.1:3000)\n\n"
read -r grafana_url
[[ -z "${grafana_url}" ]] && exit_with_error "URL do Grafana não pode ser vazia"

# Solicita o token de acesso à API do Grafana
printf "\nDigite o token:\n\n"
read -r token
[[ -z "${token}" ]] && exit_with_error "Token não pode ser vazio"

# Solicita o nome do arquivo de saída, sem extensão
printf "\nDigite o nome do arquivo de saída, sem extensão\n\n"
read -r file
[[ -z "${file}" ]] && exit_with_error "Nome do arquivo não pode ser vazio"

clear

# Desabilita o modo de saída de erro
set +e

# Verifica se a URL e o token são válidos
grafana_check_api

# Habilita o modo de saída de erro novamente
set -e

# Lista os dashboards
list_dashboards