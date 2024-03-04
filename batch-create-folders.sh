#!/usr/bin/bash

#######################################################
# Script para criar folders no Grafana usando sua API #
#######################################################

# Este script solicita a URL do Grafana, um token de acesso à API do Grafana 
# e o nome do arquivo contendo os nomes dos folders a serem criados.
# O arquivo de entrada deve conter um nome de folder por linha.

# Habilita o modo de saída de erro 
set -e

# Função para exibir mensagem de erro e sair
exit_with_error() {
    echo "Erro: $1"
    exit 1
}

# Função para fazer a solicitação à API Grafana
grafana_api_request() {
    local url="$1"
    local token="$2"
    local folder="$3"
    curl -sk -X POST "${url}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${token}" \
        -d "{\"title\": \"${folder}\"}"
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

# Função para criar folders
create_folders() {
    while IFS= read -r folder_name || [[ -n "$folder_name" ]]; do
        # Ignora linhas em branco
        if [[ -z "$folder_name" ]]; then continue; fi

        response=$(grafana_api_request "${grafana_url}/api/folders" "${token}" "${folder_name}")

        echo "Criando folder ${folder_name}"

        # Verifica se o folder foi criado com sucesso
        if [[ $(echo "${response}" | jq -e 'has("title")') == true ]]; then
            if [[ $(echo "${response}" | jq -r '.title') == "${folder_name}" ]]; then
                echo "Folder ${folder_name} criado com sucesso"
            fi
        fi

        # Verifica se houve erro ao criar o folder e exibe a mensagem de erro
        if [[ $(echo "${response}" | jq -e 'has("message")') == true ]]; then
            if [[ $(echo "${response}" | jq -r '.message') == *"already exists"* ]]; then
                echo "Folder ${folder_name} já existe"
            elif [[ $(echo "${response}" | jq -r '.message') == "name cannot be empty" ]]; then
                echo "O nome do folder não pode ser vazio"
            else
                [[ $(echo "${response}" | jq -r '.message') == *"need additional permissions"* ]]
                exit_with_error "Token não tem permissão para criar folders"
            fi
        fi

    done <"${input_file}"
}

# Menu de opções
clear

# Solicita a URL do Grafana
printf "Digite a URL do Grafana (ex: http://127.0.0.1:3000)\n\n"
read -r grafana_url
[[ -z "${grafana_url}" ]] && exit_with_error "URL do Grafana não pode ser vazia"

# Solicita o token de acesso à API do Grafana
printf "\nDigite o token:\n\n"
read -r token
[[ -z "${token}" ]] && exit_with_error "Token não pode ser vazio"

# Solicita o nome do arquivo contendo os nomes dos folders
printf "\nDigite o nome do arquivo contendo os nomes dos folders (ex: folders.txt):\n\n"
read -r input_file
[[ -z "${input_file}" ]] && exit_with_error "Nome do arquivo não pode ser vazio"
[[ ! -f "${input_file}" ]] && exit_with_error "Arquivo não encontrado"

clear 

# Desabilita o modo de saída de erro
set +e

# Verifica se a URL e o token são válidos
grafana_check_api

# Habilita o modo de saída de erro novamente
set -e

# Cria folders
create_folders
