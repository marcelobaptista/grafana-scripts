#!/bin/bash

token="" # Token de acesso ao Grafana
grafana_url="" # URL do Grafana

# (Data atual – prazo estabelecido), no caso abaixo, 2 meses atrás
# Outro exemplo: date —date="2 days ago" +%Y-%m-%d (2 dias atrás)
# Editar conforme necessário
activeat=$(date --date="2 months ago" +%Y-%m)

# Endpoints para para alert rules e rule groups
endpoint_alerts="${grafana_url}/api/prometheus/grafana/api/v1/alerts?includeInternalLabels=true"
endpoint_alert_rules="${grafana_url}/api/v1/provisioning/alert-rules"

# Lista todas as regras de alerta configuradas
curl -sk "${endpoint_alert_rules}" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" |
  jq -r >alert-rules.json

# Lista os alertas e respectivos status
curl -sk "${endpoint_alerts}" \
  -H "Authorization: Bearer ${token}" |
  jq -r >alerts.json


# Seleciona alertas em status "Alerting", "Alerting (NoData)" ou "Error" com o prazo declarado em "activeat"
jq -r --arg activeat "${activeat}" '
  .data.alerts[] |
  select(
    (
      .state == "Alerting" or
      .state == "Alerting (NoData)" or
      .state == "Error"
    ) and
    (.activeAt | startswith($data))
  )
' alerts.json >alerting.json

# Lista os UID's dos alertas
jq -r '.labels.alertruleuid' alerting.json >alertUIDs.txt
sort -u alertUIDs.txt -o alertUIDs.txt

# Loop para ler cada alerta
while IFS= read -r uid; do
  jq -r --arg uid "${uid}" '
    .[] |
    select(.uid == "'"${uid}"'")
  ' alert-rules.json >temp.json

  # Variável para ser utilizada no comentário
  date=$(TZ="America/Sao_Paulo" date +"%d/%m/%Y %H:%M:%S")

  # Insere a label "comment" no alerta e armazena em variável
  # para ser utilizada no comentário. Edite conforme necessário.
  # Configura isPaused como true para pausar o alerta.
  data_raw=$(
    jq --arg date "${date}" '
      .annotations.comment = "Pausado em: "
      + $date| .isPaused = true
      ' temp.json
  )

  # Atualiza a regra de alerta no Grafana
  curl -sk -X 'PUT' \
    "${endpoint_alert_rules}/${uid}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${token}" \
    -d "${data_raw}" \
    >/dev/null 2>&1

  #
  rulegroup=$(jq -r '.ruleGroup' temp.json)
  folderUID=$(jq -r '.folderUID' temp.json)

  # Define o endpoint rule groups para o escopo do folder do alerta
  endpoint_rule_groups="${grafana_url}/api/v1/provisioning/folder/${folderUID}/rule-groups"

  # Trata espaços na URL
  url="${endpoint_rule_groups}/${rulegroup}"
  url="${url// /%20}"

  # Atualiza rule groupos sem alterar o conteúdo,
  # pois alert rules se tornam não editáveis
  # ao serem atualizados por meio de API,
  # e usando o endpoint de rule group voltam a ser editáveis.
  curl -sk "${url}" \
    -H "Authorization: Bearer ${token}" |
    jq -r >"temp.json"
  curl -sk -X PUT "${url}" \
    -H "Accept: application/json" \
    -H "X-Disable-Provenance: true" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${token}" \
    -d @temp.json
done <alertUIDs.txt
rm -f {alert-rules,alerting,alerts,temp}.json alertUIDs.txt