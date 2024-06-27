#!/bin/bash

###############################################################
# Script para listar todos os teams do Grafana e gerar um CSV #
###############################################################

# Este script solicita a URL do Grafana, um token de acesso à API do Grafana 
# e o nome do arquivo de saída. Em seguida, ele lista todos os teams disponíveis
# no Grafana e os salva em um arquivo CSV com as seguintes colunas:
# Name;Email;Id

# Habilita o modo de saída de erro
set -euo pipefail

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

# Função para listar todos os teams
list_grafana_teams() {
    grafana_api_request "${grafana_url}/api/teams/search?" "${token}" |
        jq -r '.teams[] | "\(.name);\(.email);\(.id)"' >"${file}.csv"
    # Adiciona um cabeçalho ao arquivo CSV
    sed -i "1s/^/Name;Email;Id\n/" "${file}.csv"
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
list_grafana_teams