#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se a URL e o token foram passados como argumentos
if [ $# -lt 3 ]; then
	printf "\nUso do script: %s <grafana_url> <grafana_token> <arquivo csv>\n" "$0"
	exit 1
fi

# Argumentos passados para o script
grafana_url=$1
grafana_token=$2
input_file=$3

# Verifica se o arquivo existe
if [ ! -f "${input_file}" ]; then
	echo "Arquivo não encontrado: ${input_file}"
	exit 1
fi

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_url}/api/folders" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
  -o "folders.json"; then
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

rm -f folders.json

# Percorre as linhas do arquivo CSV para criar os folders
while IFS= read -r folder_name || [[ -n "${folder_name}" ]]; do

	# Ignora linhas em branco
	if [[ -z "${folder_name}" ]]; then continue; fi

	# Remove espaços em branco do início e fim
	folder_name=$(echo "${folder_name}" | xargs)
	parent_uid=$(echo "${parent_uid}" | xargs)

	# Monta o JSON do body baseado na presença do parent_uid
	if [[ -z "${parent_uid}" ]]; then
		# Folder raiz (sem parent)
		json_body="{\"title\": \"${folder_name}\"}"
	else
		# Folder com parent
		json_body="{\"title\": \"${folder_name}\", \"parentUid\": \"${parent_uid}\"}"
	fi

	response=$(curl -sk -X POST "${grafana_url}/api/folders" \
		-H "Accept: application/json" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${grafana_token}" \
		-d "${json_body}")

	# Verifica se o folder foi criado com sucesso
	if [[ $(echo "${response}" | jq -e 'has("title")') == true ]]; then
		if [[ $(echo "${response}" | jq -r '.title') == "${folder_name}" ]]; then
			folder_uid=$(echo "${response}" | jq -r '.uid')
			if [[ -z "${parent_uid}" ]]; then
				echo "Folder '${folder_name}' (uid: ${folder_uid}) criado com sucesso"
			else
				echo "Folder '${folder_name}' (uid: ${folder_uid}) criado dentro de '${parent_uid}'"
			fi
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
		*"need additional permissions"*)
			echo "Token não tem permissão para criar folders"
			;;
		*"Parent folder not found"* | *"parent not found"*)
			echo "Erro: folder pai '${parent_uid}' não encontrado para '${folder_name}'"
			;;
		*)
			echo "Erro ao criar folder '${folder_name}': $(echo "${response}" | jq -r '.message')"
			;;
		esac
	fi

done <"${input_file}"
