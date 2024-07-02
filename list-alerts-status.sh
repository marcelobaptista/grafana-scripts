#!/bin/bash

# Script para fornecer uma lista CSV dos alertas que estão no status "Alerting" ou "Error"

token=""
grafana_url=""
file=""

# Lista os alertas ativos e devidos status
curl -sk "${grafana_url}/api/prometheus/grafana/api/v1/alerts?includeInternalLabels=true" \
  -H "Authorization: Bearer ${token}" | jq -r >alerts.json

# Seleciona alertas em status "Alerting", "Alerting (NoData)" ou "Error"
# Pode também adicionar "Normal (NoData)" e "Normal"
jq -r '
  .data.alerts[] | 
  select(
    (
      .state == "Alerting" or 
      .state == "Alerting (NoData)" or 
      .state == "Error"
    ) 
  )
' alerts.json >alerting.json

# Formata e salva em um arquivo .csv
jq --arg grafana_url "${grafana_url}" '
  . | 
  "\(.labels.grafana_folder);\(.labels.alertname);${grafana_url}/alerting/\(.labels.__alert_rule_uid__)/edit?;\(.activeAt)"' alerting.json >"${file}.csv"

# Remove duplicatas, pois uma regra de alerta pode conter mais de uma instância
sort -u "${file}.csv" -o "${file}.csv"

# Adiciona cabeçalho no arquivo .csv
sed -i '' "1s/^/GrafanaFolder;AlertName;Url;ActiveAt\n/" "${file}.csv"

# Remove arquivos temporários
rm -f {alerts,alerting}.json
