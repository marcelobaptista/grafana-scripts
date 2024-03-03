# Script para automatização de criação de Folders no Grafana

Script em Bash para criar folders no Grafana usando sua API, e através de uma lista em formato texto. 

## Requisitos

Antes de usar este script, certifique-se de ter os seguintes requisitos instalados:

- [jq](https://stedolan.github.io/jq/)
- [curl](https://curl.se/)

Certifique-se de ter essas dependências instaladas e acessíveis no seu ambiente.

## Como Executar

1. Faça o download do script `create_folders.sh`.
2. No mesmo diretório, crie um arquivo de texto contendo os nomes dos folders que você deseja criar. Cada nome deve estar em uma linha separada.
3. Abra um terminal e navegue até o diretório onde o script está localizado.
4. Execute o seguinte comando para tornar o script executável:

    ```bash
    chmod +x create_folders.sh
    ```

4. Execute o script usando o seguinte comando:

    ```bash
    ./create_folders.sh
    ```

5. Siga as instruções fornecidas para inserir a URL do Grafana, o token de acesso e o nome do arquivo contendo os nomes dos folders a serem criados.

## Limitações

Este script tem as seguintes limitações:

- O script é capaz de criar apenas folders em uma única organização do Grafana. Não é possível criar folders em outras organizações usando este script. (em andamento)

## Contribuindo

Contribuições são bem-vindas! Sinta-se à vontade para abrir problemas para relatar bugs ou solicitar novos recursos. Se você deseja contribuir com código, abra uma solicitação de pull request.

## Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE).

