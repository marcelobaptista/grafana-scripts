#!/usr/bin/bash

########################################################
# Script para criar usuários no Grafana usando sua API #
########################################################

# Este script solicita a senha de admin do Grafana
# e o nome do arquivo csv para criação dos usuários.
# O arquivo csv deve conter nome, email, nome de login, senha e orgId

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se o arquivo CSV foi passado como argumento
if [ $# -ne 1 ]; then
	echo "Uso do script: $0 arquivo.csv"
	exit 1
fi

grafana_url="" # URL do Grafana

# Solicita o token de acesso à API do Grafana
printf "\nDigite a senha de admin:\n\n"
read -r password
[[ -z "${password}" ]] && echo "Erro: Senha não pode ser vazia" && exit 1

# Codifica o usuário e senha para base64
auth_basic=$(echo -n "admin:${password}" | base64)

# Loop através das linhas do arquivo CSV, excluindo o cabeçalho
while IFS=',' read -r name email login user_password orgid; do
	# Monta o JSON para cada linha do CSV
	json_data=$(
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
		-d "${json_data}" 2>&1)

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
done <"$1" # Lê o arquivo CSV fornecido como argumento
