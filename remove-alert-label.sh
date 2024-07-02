#!/bin/bash

folderUID=""   # uid do folder dos alertas a serem modificados
key=""         # label a ser removida do alerta. Ex.: ENV
token=""       # token de acesso ao Grafana
grafana_url="" # URL do Grafana

# Endpoints para alert rules e rule groups
endpoint_alert_rules="${grafana_url}/api/v1/provisioning/alert-rules"
endpoint_rule_groups="${grafana_url}/api/v1/provisioning/folder/${folderUID}/rule-groups"

# Lista todas as regras de alerta configuradas
curl -sk "${endpoint_alert_rules}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${token}" |
  jq -r >alert-rules.json

# Extrai UIDs dos alert rules
jq -r --arg folderUID "${folderUID}" \
  '.[] | select(.folderUID == "'"${folderUID}"'") | .uid' alert-rules.json >uids.txt

# Extrai folderUIDs dos rule groups
jq -r --arg folderUID "${folderUID}" \
  '.[] | select(.folderUID == "'"${folderUID}"'") | .ruleGroup' alert-rules.json >ruleGroups.txt

# Loop para cada UID
while IFS= read -r uid; do
  curl -sk "${endpoint_alert_rules}/${uid}" \
    -H "Authorization: Bearer ${token}" |
    jq -r >temp.json

  # deleta a label configurada
  data_raw=$(
    jq --arg key "${key}" '
    del(.labels[$key])
    ' temp.json
  )

  # Atualiza a regra de alerta no Grafana
  curl -sk -X PUT "${endpoint_alert_rules}/${uid}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${token}" \
    -d "${data_raw}" \
    >/dev/null 2>&1
done <"uids.txt"

while IFS= read -r rulegroup; do
  # Tratamento de espaços na URL
  url="${endpoint_rule_groups}/${rulegroup}"
  url="${url// /%20}"

  # Atualiza rule groupos, pois alert rules se tornam não editáveis
  # ao serem atualizados por meio de API.
  # Usando o endpoint de rule group voltam a ser editáveis
  curl -sk "${url}" \
    -H "Authorization: Bearer ${token}" |
    jq -r >temp.json
  curl -sk -X PUT "${url}" \
    -H "Accept: application/json" \
    -H "X-Disable-Provenance: true" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${token}" \
    -d @temp.json \
    >/dev/null 2>&1
done <"ruleGroups.txt"
rm -f {alert-rules,temp}.json {ruleGroups,uids}.txt
