#!/usr/bin/bash

#######################################################
# Script para criar folders no Grafana usando sua API #
#######################################################

# Este script solicita a URL do Grafana, um token de acesso à API do Grafana
# e o nome do arquivo contendo os nomes dos folders a serem criados.
# O arquivo de entrada deve conter um nome de folder por linha.

# Habilita o modo de saída de erro
set -euo pipefail

grafana_token=""       # Token de acesso ao Grafana
grafana_url=""         # URL do Grafana

# Nome do arquivo contendo os nomes dos folders
input_file="$1"

# Verifica se o arquivo foi passado como argumento
if [ $# -ne 1 ]; then
    echo "Uso do script: $0 arquivo.txt"
    exit 1
fi

# Verifica se o arquivo existe
if [ ! -f "${input_file}" ]; then
    echo "Arquivo não encontrado: ${input_file}"
    exit 1
fi

# Limpa a tela
clear

# Verifica se a URL e o token são válidos
check_api=$(curl -sk "${grafana_url}/api/org" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${grafana_token}" | jq .name)

if [[ "${check_api}" == null ]]; then
    echo "Verifique a URL e o token de acesso"
    exit 1
fi

# Loop para ler cada linha do arquivo e criar os folders
while IFS= read -r folder_name || [[ -n "${folder_name}" ]]; do
    # Ignora linhas em branco
    if [[ -z "${folder_name}" ]]; then continue; fi
    response=$(curl -sk -X POST "${grafana_url}/api/folders" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${grafana_token}" \
        -d "{\"title\": \"${folder_name}\"}")

    # Verifica se o folder foi criado com sucesso
    if [[ $(echo "${response}" | jq -e 'has("title")') == true ]]; then
        if [[ $(echo "${response}" | jq -r '.title') == "${folder_name}" ]]; then
            echo "Folder ${folder_name} criado com sucesso"
        fi
    fi

    # Verifica se houve erro ao criar o folder e exibe a mensagem de erro
    if [[ $(echo "${response}" | jq -e 'has("message")') == true ]]; then
        case $(echo "${response}" | jq -r '.message') in
        *"already exists"*)
            echo "Folder '${folder_name}' já existe"
            ;;
        "name cannot be empty")
            echo "O nome do folder '${folder_name}' não pode ser vazio"
            ;;
        *"need additional permissions")
            echo "Token não tem permissão para criar folders"
            ;;
        *)
            echo "Erro ao criar folder '${folder_name}': $(echo "${response}" | jq -r '.message')"
            ;;
        esac
    fi
done <"${input_file}" # Lê o arquivo de entrada
