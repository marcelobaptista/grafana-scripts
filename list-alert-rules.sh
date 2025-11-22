#!/bin/bash

# Habilita o modo de saída de erro
set -euo pipefail

# Verifica se a URL e o token foram passados como argumentos
if [ $# -lt 2 ]; then
  printf "\nUso do script: %s <grafana_url> <grafana_token>\n" "$0"
  exit 1
fi

# Argumentos passados para o script
grafana_url=$1
grafana_token=$2

# Define a data atual
date_now=$(date +%Y-%m-%d)

# Nome do arquivo de saída
output_file="${date_now}-grafana-alert-rules.csv"

# Função para fazer requisições na API do Grafana
get_api()
{
  local endpoint="$1"
  curl -sk "${grafana_url}${endpoint}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${grafana_token}" \
    -H "Content-Type: application/json"
}

# Consulta API do Grafana e salva a resposta em JSON (com tratamento de erro de conexão)
if ! get_api "/api/v1/provisioning/alert-rules" | jq -r '[.[]]' >alert-rules.json; then
  printf "\nErro: falha na conexão com a URL ou problema de resolução DNS.\n"
  rm -f "alert-rules.json"
  exit 1
fi

# Verifica se o token é inválido ou sem permissão suficiente
if grep -iq "invalid API key" "alert-rules.json"; then
  printf "\nErro: chave de API inválida.\n"
  rm -f "alert-rules.json"
  exit 1
elif grep -iq "Access denied" "alert-rules.json" || grep -iq "Permissions needed" "alert-rules.json"; then
  printf "\nErro: token sem permissão suficiente.\n"
  rm -f "alert-rules.json"
  exit 1
fi

# Cria lista de UIDs das regras de alerta
jq -r '.[].uid' alert-rules.json >alert-rules-uids.txt

# Itera sobre cada alert rule UID e extrai informações
while IFS= read -r uid; do

  # Salva o alerta em um arquivo JSON
  jq -r --arg uid "${uid}" '.[] | select(.uid == $uid)' alert-rules.json >"alert-rule-${uid}.json"

  # Extrai rule group do alerta
  rule_group=$(jq -r '.ruleGroup | @uri' "alert-rule-${uid}.json")

  # Extrai folder UID do alerta
  folder_uid=$(jq -r '.folderUID' "alert-rule-${uid}.json")

  # Se folder UID estiver vazio ou nulo, pula para o próximo
  if [ -z "${folder_uid}" ] || [ "${folder_uid}" = "null" ]; then

  # Remove arquivo temporário
    rm -f "alert-rule-${uid}.json"
    continue
  fi

  # Extrai evaluation interval do rule group
  evaluation_interval=$(
    get_api "/api/v1/provisioning/folder/${folder_uid}/rule-groups/${rule_group}" | jq -r '.interval | if . != null then ((. / 60 | floor | tostring) + "m") else "-" end'
  )

  # Extrai nome do folder
  folder_title=$(get_api "/api/folders/${folder_uid}" | jq -r '.title')

  # Para cada datasource válido, gera uma linha no CSV
  jq -r --arg folder_title "${folder_title}" \
    --arg grafana_url "${grafana_url}" \
    --arg evaluation_interval "${evaluation_interval}" '
    . as $alert |
    .data[]? |
    select(.model.datasource.type != null and .model.datasource.type != "__expr__") |
    ($folder_title) + ";" +
    ($alert.title) + ";" +
    ($alert.ruleGroup) + ";" +
    (.model.datasource.type) + ";" +
    (.model.datasource.uid) + ";" +
    ($grafana_url) + "/alerting/grafana/" + ($alert.uid) + "/view;" +
    ($evaluation_interval) + ";" +
    ($alert.for) + ";" +
        ($alert.keep_firing_for) + ";" +
    ($alert.noDataState) + ";" +
    ($alert.execErrState) + ";" +
    ($alert.isPaused | tostring)
  ' "alert-rule-${uid}.json" >>"${output_file}"

  # Remove arquivo temporário
  rm -f "alert-rule-${uid}.json"

done <alert-rules-uids.txt

# Remove linhas duplicadas, se houver
sort -u "${output_file}" -o "${output_file}"

# Insere cabeçalho no arquivo CSV

sed -i '1i\
folderTitle;alertName;ruleGroup;datasourceType;datasourceUid;url;evaluationInterval;for;keepFiringFor;noDataState;execErrState;isPaused
' "${output_file}"

# Remove arquivos temporários
rm -f alert-rules{}.json,-uids.txt}