#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se a URL e o token foram passados como argumentos
if [ $# -lt 3 ]; then
	printf "\nUso do script: %s <grafana_url> <grafana_token> <period[d|m]>\n" "$0"
	exit 1
fi

# Argumentos passados para o script
grafana_url=$1
grafana_token=$2
period=$3

# Endpoint para requisições
grafana_api_users="${grafana_url}/api/org/users"

# Define a data atual
date_now=$(date +%Y-%m-%d)

# Extrai valor (ex: 3 de "3d") e a unidade (ex: "d" ou "m")
value="${period%[dm]}"
unit="${period: -1}"

# Arquivo de log
logfile="${date_now}-folders-backup.log"

# Função de logging
logging() {
	local name=$1
	local last_seen_at=$2
	local last_seen_at_age=$3
	local message
	message="[$(date --iso-8601=seconds)] user: ${name}, last_seen_at: ${last_seen_at}, last_seen_at_age: ${last_seen_at_age}"
	echo "${message}" | tee -a "${logfile}"
}

# Verifica se o valor é numérico
if ! [[ ${value} =~ ^[0-9]+$ ]]; then
	echo "Erro: o valor deve ser um número inteiro."
	exit 1
fi

# Subtrai dias ou meses com base na unidade
if [[ ${unit} == "d" || ${unit} == "m" ]]; then
	period=$(date -d "${value} ${unit} ago" +%Y-%m-%d)
else
	echo "Erro: A unidade deve ser 'd' (dias) ou 'm' (meses)."
	exit 1
fi

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! curl -sk "${grafana_api_users}" \
	-H "Accept: application/json" \
	-H "Authorization: Bearer ${grafana_token}" \
	-H "Content-Type: application/json" \
	> "users.json"; then
	printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
	exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "users.json"; then
	printf "\nErro: chave de API inválida.\n"
	rm -f "users.json"
	exit 1
elif grep -iq "Access denied" "users.json" || grep -iq "Permissions needed" "users.json"; then
	printf "\nErro: token sem permissão suficiente.\n"
	rm -f "users.json"
	exit 1
fi

# Filtra usuários que não acessaram o Grafana no período definido e cria lista
jq -r --arg period "${period}" \
	'.[] | 
  select(.lastSeenAt <= $period) | 
  [ .userId, .name, .lastSeenAt, .lastSeenAtAge] | 
  @csv' users.json |
	sed 's/"//g' >users_to_delete.txt

# Verifica se há usuários para deletar
if [ ! -s users_to_delete.txt ]; then
	echo "Nenhum usuário foi deletado."
	exit 0
else

	# Deleta usuários
	while IFS=',' read -r user_id name last_seen_at last_seen_at_age; do

		# Ignora linhas vazias
		[ -z "${user_id}" ] && continue

		# Deleta o usuário e verifica a resposta
		if curl -skX DELETE "${grafana_api_users}/${user_id}" \
			-H "Accept: application/json" \
			-H "Authorization: Bearer ${grafana_token}" \
			-H "Content-Type: application/json" | grep -iq '"message":"User deleted"'; then

			# Registra no log
			logging "${name}" "${last_seen_at}" "${last_seen_at_age}"
		fi
	done <users_to_delete.txt
fi

# Remove arquivos temporários
rm -f users.json users_to_delete.txt
