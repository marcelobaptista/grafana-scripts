# Script de geração de lab Grafana, Prometheus, Node Exporter, Alert Manager e k6

Este script Bash automatiza a configuração inicial do Grafana e Prometheus usando Docker Compose. Ele realiza as seguintes tarefas:

- Cria e inicia os containers do Grafana, Prometheus, Node Exporter, Alert Manager usando um arquivo docker-compose (`monitoring.yml`).
- Atualiza o nome da organização do Grafana para "Org1".
- Cria uma conta de serviço com permissões de administrador no Grafana.
- Gera um token de acesso para a conta de serviço criada.
- Configura datasource Prometheus no Grafana.
- Importa dashboard k6

## Requisitos

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [cURL](https://curl.se/download.html)
- [jq](https://jqlang.github.io/jq/download/)

## Uso

1. Clone este repositório:

    ```bash
    git clone https://github.com/marcelobaptista/grafana-scripts.git
    ```

2. Navegue até o diretório do projeto:

    ```bash
    cd grafana-scripts/lab-grafana
    ```

3. Execute o script Bash:

    ```bash
    bash lab-grafana.sh
    ```

## Observações

- Será gerado um arquivo chamado tokeinAPI.txt contendo o token da API
- Certifique-se de que as portas necessárias (3000 para Grafana, 9090 para Prometheus) não estão sendo usadas por outros serviços.
- Você pode ajustar as configurações do Grafana e do Prometheus editando o arquivo `monitoring.yml`.
- O dashboard (`k6.json`) importado para o Grafana deve estar presente no mesmo diretório que este script.
