#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se a URL, token e arquivo CSV foram passados como argumentos
if [ $# -lt 3 ]; then
	printf "\nUso do script: %s <grafana_url> <admin_user> <arquivo>\n" "$0"
	exit 1
fi

# Argumentos passados para o script
grafana_url=$1
admin_user=$2
file=$3

# Lê a senha de forma segura
printf "\nDigite a senha de admin:\n\n"
read -r password
[[ -z "${password}" ]] && echo "Erro: Senha não pode ser vazia" && exit 1

# Codifica o usuário e senha para base64
auth_basic=$(echo -n "${admin_user}:${password}" | base64)

# Percorre as linhas do arquivo CSV
while IFS=';' read -r name email login user_password orgid; do

	# Monta o JSON para cada linha do CSV
	json_body=$(
		cat <<EOF
{
  "name":"${name}",
  "email":"${email}",
  "login":"${login}",
  "password":"${user_password}",
  "OrgId": ${orgid}
}
EOF
	)

	# Faz a requisição usando curl para o endpoint desejado
	response=$(curl -sX POST "${grafana_url}/api/admin/users" \
		-H "Accept: application/json" \
		-H "Authorization: Basic ${auth_basic}" \
		-H "Content-Type: application/json" \
  	-o d "${json_body}" 2>&1)

	# Verifica o tipo de resposta usando case
	case "${response}" in
	*"already exists"*)
		echo "Usuário ${name} já existe"
		;;
	*"permissions needed"*)
		echo "Verifique se tem permissões suficientes"
		echo "Resposta da API: ${response}"
		exit 1
		;;
	*"Invalid username or password"*)
		echo "Erro: Usuário ou senha inválidos"
		echo "Resposta da API: ${response}"
		exit 1
		;;
	*)
		# Tenta extrair o id do usuário da resposta usando jq
		user_id=$(echo "${response}" | jq -r '.id')

		# Verifica se o id do usuário foi retornado e se é um número
		if [[ -n "${user_id}" && "${user_id}" =~ ^[0-9]+$ ]]; then
			echo "Usuário ${name} criado"
		else
			echo "Falha ao criar usuário ${name}"
			echo "Resposta da API: ${response}"
		fi
		;;
	esac
done <"${file}"
