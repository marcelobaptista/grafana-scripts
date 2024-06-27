#!/usr/bin/bash

########################################################
# Script para criar usuários no Grafana usando sua API #
########################################################

# Este script solicita a URL do Grafana, senha de admin do Grafana
# e o nome do arquivo csv para criação dos usuários.
# O arquivo csv deve conter nome, email, nome de login, senha e orgId

# Habilita o modo de saída de erro
set -euo pipefail

# Função para exibir mensagem de erro e sair
exit_with_error() {
  echo "Erro: $1"
  exit 1
}

# Verifica se o arquivo CSV foi passado como argumento
if [ $# -ne 1 ]; then
  echo "Uso: $0 arquivo.csv"
  exit 1
fi

# Solicita a URL do Grafana
printf "Digite a URL do Grafana (ex: http://127.0.0.1:3000)\n\n"
read -r grafana_url
[[ -z "${grafana_url}" ]] && exit_with_error "URL do Grafana não pode ser vazia"

# Solicita o token de acesso à API do Grafana
printf "\nDigite a senha de admin:\n\n"
read -r password
[[ -z "${password}" ]] && exit_with_error "Senha não pode ser vazia"

auth_basic=$(echo -n "admin:${password}" | base64)

# Loop através das linhas do arquivo CSV, excluindo o cabeçalho
tail -n +2 "$1" | while IFS=',' read -r name email login user_password orgid; do
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
    -d "${json_data}" 2>&1) # Redireciona stderr para stdout para capturar mensagens de erro

  # Verifica o tipo de resposta usando case
  case "${response}" in
  *"already exists"*)
    echo "Usuário ${name} já existe"
    ;;
  *"permissions needed"*)
    echo "Verifique se tem permissões suficientes"
    exit_with_error
    ;;
  *"Invalid username or password"*)
    exit_with_error "Usuário ou senha inválidos"
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
done
