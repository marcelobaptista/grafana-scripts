#!/bin/bash

set -e
grafana_url="http://127.0.0.1:3000"

function recreateContainers() {
    docker ps -a -q | xargs docker container rm -f >/dev/null 2>&1
    docker volume ls -q | xargs docker volume rm >/dev/null 2>&1
    docker volume prune -f >/dev/null 2>&1
    docker-compose -f monitoring.yml up -d
    sleep 10
}

function updateOrg() {
    curl -X PUT "${grafana_url}/api/orgs/1" \
        -H 'Authorization: Basic YWRtaW46MTIzNDU2' \
        -H 'Content-Type: application/json' \
        -d '{"name":"Org1"}' >/dev/null 2>&1
}

function createServiceAccount() {
    service_account_id=$(
        curl -sk -X POST "${grafana_url}/api/serviceaccounts" \
            -H "Authorization: Basic YWRtaW46MTIzNDU2" \
            -H "Content-Type: application/json" \
            -d '{"name":"sa-1","role":"Admin","isDisabled": false}' |
            jq -r '.id'
    )
}

function createToken() {
    token_key=$(
        curl -sk -X POST "${grafana_url}/api/serviceaccounts/${service_account_id}/tokens" \
            -H "Authorization: Basic YWRtaW46MTIzNDU2" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"token-sa-${service_account_id}\"}" |
            jq -r '.key'
    )
    printf "token: %s\n" "${service_account_id}" "${token_key}" >tokeinAPI.txt
}

function createDatasources() {
    docker exec -i grafana sh -c 'cat <<EOF > /etc/grafana/provisioning/datasources/datasources.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    orgId: 1
    uid: prometheus
    url: http://prometheus:9090
    basicAuth: false
    isDefault: true
    version: 1
    editable: false
EOF'
    docker container restart grafana >/dev/null 2>&1
}

function createDashboard() {
    curl -sk -X POST "${grafana_url}/api/dashboards/db" \
        -H "Authorization: Bearer ${token_key}" \
        -H "Content-Type: application/json" \
        -d "@k6.json" >/dev/null 2>&1
}

if recreateContainers; then
    docker container ls --format '{{.Names}}' |
        sort | sed 's/^/Container /' | sed 's/$/ created/'
fi
if updateOrg; then printf "Organization updated\n"; fi
if createServiceAccount; then printf "Service Account created\n"; fi
if createToken; then printf "Token created\n"; fi
if createDashboard; then printf "Dashboard created\n"; fi
if createDatasources; then printf "Datasource created\n"; fi
