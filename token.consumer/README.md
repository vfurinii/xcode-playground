# AI Token Consumer Widget

Widget macOS para acompanhar gasto em USD e consumo de tokens da OpenAI no mes atual.

O app salva a OpenAI Admin Key no Keychain do macOS. Nenhuma API key deve ser commitada no repositorio.

## Requisitos

- macOS com suporte a WidgetKit.
- Xcode instalado.
- Uma OpenAI Admin Key com permissao de leitura para usage/costs da organizacao.
- Uma conta Apple Developer configurada no Xcode para assinar o app e o widget.

## Rodando localmente

1. Clone o repositorio:

   ```sh
   git clone <url-do-repositorio>
   cd ai-token-consumer-widget
   ```

2. Abra o projeto no Xcode:

   ```sh
   open token.consumer/token.consumer.xcodeproj
   ```

3. Em `Signing & Capabilities`, selecione o seu Team para os dois targets:

   - `token.consumer`
   - `TokenConsumerWidgetExtension`

4. Troque os identificadores de exemplo por identificadores unicos seus:

   - `PRODUCT_BUNDLE_IDENTIFIER`: use algo como `com.seu-nome.token-consumer`.
   - `APP_GROUP_IDENTIFIER`: use algo como `group.com.seu-nome.token-consumer`.

   Configure o mesmo `APP_GROUP_IDENTIFIER` nos dois targets. O app e o widget usam esse App Group para compartilhar preferencias e a referencia do Keychain.

5. Confirme que os dois targets tem as capabilities abaixo:

   - App Groups, usando o mesmo App Group.
   - Keychain Sharing, usando o mesmo access group.
   - Outgoing Connections/Network Client, para chamar a API da OpenAI.

6. Rode o target `token.consumer`.

7. No app, informe a `OpenAI Admin Key` e clique em `Salvar chave`.

8. Opcionalmente informe:

   - Project ID.
   - Referencia mensal de tokens.
   - Orcamento mensal em USD.

9. Adicione o widget `AI Token Usage` na Central de Notificacoes do macOS.

O widget pede atualizacao a cada 5 minutos. O macOS pode atrasar ou agrupar atualizacoes para economizar energia, entao isso nao e tempo real garantido.

## Instalando no Mac

Para usar fora do Xcode:

1. No Xcode, selecione o scheme `token.consumer`.
2. Use `Product > Archive`.
3. Na janela Organizer, exporte o app para distribuicao local ou Developer ID, conforme sua conta Apple.
4. Copie o app exportado para `/Applications`.
5. Abra o app uma vez, salve a Admin Key e depois adicione o widget no macOS.

Se o macOS bloquear o app por assinatura/notarizacao, confira as opcoes de exportacao no Xcode e as permissoes em `System Settings > Privacy & Security`.

## Dados usados

O projeto chama diretamente:

- `GET https://api.openai.com/v1/organization/usage/completions`
- `GET https://api.openai.com/v1/organization/costs`

A busca usa `start_time` no inicio do mes atual, `bucket_width=1d` e `limit=31`.

## Seguranca

- Nao coloque sua OpenAI Admin Key em arquivos do projeto, README, issues ou commits.
- A chave digitada no app fica no Keychain compartilhado entre o app e o widget.
- Preferencias nao sensiveis ficam em `UserDefaults(suiteName:)` dentro do App Group.
- Se uma chave real foi commitada por acidente, revogue essa chave no dashboard da OpenAI e gere outra. Remover do codigo nao invalida uma chave que ja ficou publica.

## Observacoes

- A chave precisa ter permissao administrativa de organizacao para consultar usage/costs.
- O valor de custo vem da Costs API. Se essa chamada falhar, o widget ainda tenta mostrar tokens.
- A metrica principal do widget e o gasto em USD retornado pela Costs API.
- O alerta local e enviado uma vez por mes quando o gasto passa de 50% do orcamento mensal configurado. Se nao houver orcamento/custo, ele usa tokens como fallback.
- Um app macOS nao envia notificacoes locais diretamente para o Apple Watch. Para isso, e necessario um app iOS/watchOS, push via APNs, ou um servico intermediario com app no Watch.
