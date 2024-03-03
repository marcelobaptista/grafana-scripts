# Scripts para Grafana

Este repositório contém scripts para automatizar tarefas no Grafana, usando sua API. 

## Requisitos

Antes de usar os scripts, certifique-se de ter os seguintes requisitos instalados:

- [jq](https://stedolan.github.io/jq/)
- [curl](https://curl.se/)

## Como Executar os Scripts

1. Faça o download, por exemplo, do script `create_folders.sh`.
2. Abra um terminal e navegue até o diretório onde o script está localizado.
3. Execute o seguinte comando para tornar o script executável:

    ```bash
    chmod +x create_folders.sh
    ```

4. Execute o script usando o seguinte comando:

    ```bash
    ./create_folders.sh
    ```

5. Siga as instruções fornecidas para inserir a URL do Grafana, o token de acesso, etc.
6. Sempre que houver necessidade de ter algum arquivo auxiliar, o script irá solicitar a inserção do arquivo.

## Limitações dos scripts

Os scripts trabalham com somente uma [Organization](https://grafana.com/docs/grafana/latest/administration/organization-management/) do Grafana (em andamento)

## Contribuindo

Contribuições são bem-vindas! Sinta-se à vontade para abrir problemas para relatar bugs ou solicitar novos recursos. Se você deseja contribuir com código, abra uma solicitação de pull request.

## Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE).

