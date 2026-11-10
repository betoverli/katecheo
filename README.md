# Katecheo

Picker de referências bíblicas. Escolha livro, capítulo e versos; copie um texto rico com deep link para o app de Bíblia (YouVersion, Logos, Tecarta e outros). Coleções por tema. Planos de leitura de capítulos inteiros. Caderno de reunião, grupos e perfil com conta opcional.

Live: [katecheo.app](https://katecheo.app)

Repositório: [github.com/betoverli/katecheo](https://github.com/betoverli/katecheo)

Português, English, Español. PWA offline. Conta opcional (Google ou e-mail). Backend em **Vercel** + **Neon**. App nativo iOS em `ios/App/Katecheo.xcodeproj`.

> Antes chamava-se Verse2Note. O domínio legado `verse2note.com` redireciona para `katecheo.app` (com exclusões para builds antigos do iOS e OAuth — ver `docs/domain-cutover.md`).

## Local

```bash
git clone https://github.com/betoverli/katecheo.git
cd katecheo
npm install
npm run dev
```

Abre em `http://localhost:8080`.

## Stack

- Web: TanStack Start, React, Tailwind v4
- Auth: Better Auth (Google / e-mail)
- Dados: Neon (Postgres)
- Deploy: Vercel
- iOS: UIKit / Swift nativo (`ios/App/Katecheo.xcodeproj`; bundle id `com.verse2note.app`)

## Login com Google

O botão **Continuar com Google** usa o Google OAuth do Better Auth (credenciais próprias no Google Cloud).

No servidor (Vercel → Settings → Environment Variables), em **Production**:

| Nome | O que é |
| --- | --- |
| `GOOGLE_CLIENT_ID` | Client ID do cliente OAuth do tipo **Web application** |
| `GOOGLE_CLIENT_SECRET` | Client secret desse cliente. Nunca no repositório, e nunca numa variável `VITE_` (essa chega ao navegador) |

As duas têm de existir. Se faltar uma, o site continua no ar, o botão Google não aparece, e entrar com e-mail e senha fica igual. O build não precisa destas variáveis: o servidor lê-as quando arranca. Depois de as gravar, publique de novo para o processo as ver.

`BETTER_AUTH_URL` deve ser a origem canónica, tipicamente `https://katecheo.app`. O Better Auth monta o callback como `{origem}/api/auth/callback/google`.

No Google Cloud Console → APIs & Services → Credentials → OAuth client ID → **Web application**, em **Authorized redirect URIs**:

Produção (canónico):

- `https://katecheo.app/api/auth/callback/google`
- `https://www.katecheo.app/api/auth/callback/google` (opcional se o www já 308 para o apex)

Legado (manter até o cutover acabar — ver `docs/domain-cutover.md`):

- `https://verse2note.com/api/auth/callback/google`
- `https://www.verse2note.com/api/auth/callback/google`

Neste computador (os dois endereços são diferentes para o Google):

- `http://localhost:8080/api/auth/callback/google`
- `http://127.0.0.1:8080/api/auth/callback/google`

Origens JavaScript autorizadas, se o formulário as pedir:

- `https://katecheo.app`
- `https://www.katecheo.app`
- `http://localhost:8080`
- `http://127.0.0.1:8080`
- `https://verse2note.com`
- `https://www.verse2note.com`

O regresso do app de iPhone não entra nesta lista. A Apple e o Google só vêem o callback acima; o app volta depois, com um código de uso único.

## App iOS

O site em [katecheo.app](https://katecheo.app) é o produto web. O app de iPhone é **nativo** (Swift / UIKit), projeto em `ios/App/Katecheo.xcodeproj`. Fala com a API em `katecheo.app` (Better Auth + `/api/native/v1`). O identificador do app continua `com.verse2note.app` (e o tópico APNs).

Ícone, ecrã de abertura, avisos da Apple, folha de partilha e abertura da Bíblia (YouVersion e outras) são nativos. O login com Google abre o navegador do sistema e volta para o app (`katecheo://`), porque a Apple e o Google recusam esse login dentro de WebView. O regresso do login traz só um código de uso único, preso a um segredo que fica no app.

### HTTPS

O site pede HTTPS (HSTS). O app usa **https://katecheo.app**. Pedidos a `verse2note.com` redirecionam para `katecheo.app`, salvo exclusões para builds antigos e OAuth (`docs/domain-cutover.md`).

### Login do app

O navegador do sistema volta para o app com um código de uso único. O código sozinho não entra na conta: o app gerou um segredo, mandou só a impressão digital dele, e apresenta o segredo na hora de trocar o código pela sessão.

Com a versão atual do site, o app no TestFlight pede o regresso `katecheo://`. `/auth/native-config` responde `universalLinks: false` para o script já instalado pedir o esquema. Publicar o site chega para muitos builds; binário novo só quando o esquema ou Associated Domains mudarem.

`https://katecheo.app/auth/native-return` (e o equivalente legado em verse2note.com, enquanto exclusões existirem) exige iOS 17.4 e os serviços no ficheiro da Apple: `applinks:katecheo.app` e `webcredentials:katecheo.app`. `APPLE_TEAM_ID` publica os dois. Não apague a variável.

O código dura 90 segundos e só serve uma vez. No banco fica a sessão cifrada (AES-GCM), não o token legível. O login do site no navegador não usa esta tabela.

### O que já corre sem conta de programador Apple

Em cada pull request, o fluxo **iOS** compila o app para o simulador **sem assinatura** (“Simulador sem assinatura”). Isso prova que o projeto abre. Não instala no iPhone e não envia avisos.

### Quando a conta Apple Developer estiver paga

A conta custa cerca de 99 dólares por ano, em [developer.apple.com](https://developer.apple.com). Sem ela não há TestFlight nem App Store, e os avisos nativos não saem do aparelho.

O identificador do app é `com.verse2note.app`. Use esse nome em todo o lado. A versão visível está em `ios/App/Katecheo.xcodeproj/project.pbxproj` (`MARKETING_VERSION`). O número de build do TestFlight sobe sozinho a cada envio.

#### 1. No site da Apple

1. Em Certificates, Identifiers & Profiles, crie um App ID `com.verse2note.app` e marque **Push Notifications** e **Associated Domains**.
2. Crie uma chave **Apple Push Notifications service (APNs)**. Transfira o ficheiro `.p8` uma única vez. Anote o Key ID e o Team ID (10 letras/números).
3. Crie um certificado **Apple Distribution**, exporte-o do Porta-chaves como `.p12` com uma senha, e passe a Base64:
   `base64 -i certificado.p12 | pbcopy` (num Mac) ou peça a alguém com Mac. Guarde a senha.
4. Crie um perfil de provisionamento **App Store** para esse App ID, com esse certificado. Transfira o `.mobileprovision` e passe a Base64 da mesma forma.
5. Em Users and Access → Integrations, crie uma chave de API do App Store Connect com acesso de desenvolvedor. Transfira o `.p8`. Anote o Issuer ID e o Key ID (é outra chave, diferente da de avisos).
6. Em App Store Connect, crie a ficha do app **Katecheo** com o mesmo identificador.

#### 2. Segredos no GitHub (compilação e TestFlight)

No repositório: Settings → Secrets and variables → Actions → New repository secret.

| Nome | O que é |
| --- | --- |
| `APPLE_TEAM_ID` | Team ID, 10 caracteres |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID da chave de API |
| `APP_STORE_CONNECT_KEY_ID` | Key ID da chave de API (não a de avisos) |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Conteúdo do `.p8` da API, ou o mesmo ficheiro em Base64 |
| `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | O `.p12` em Base64 |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Senha desse `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | O `.mobileprovision` em Base64 |

Quando os sete existirem: Actions → **iOS** → Run workflow → marque **Enviar ao TestFlight**. Sem os segredos, esse passo recusa e não envia nada. O build do simulador não precisa deles.

#### 3. Variáveis no servidor (para os avisos saírem)

O envio do aviso fica no site. Na Vercel, acrescente:

| Nome | O que é |
| --- | --- |
| `APNS_KEY_ID` | Key ID da chave de avisos |
| `APNS_TEAM_ID` | O mesmo Team ID |
| `APNS_PRIVATE_KEY` | Conteúdo do `.p8` de avisos. Se a quebra de linha desaparecer, troque cada quebra por `\n` |
| `APNS_TOPIC` | Opcional. Por omissão `com.verse2note.app` |
| `APNS_ENVIRONMENT` | Opcional. `production` para TestFlight e App Store. `sandbox` só para um app instalado pelo Xcode em modo de desenvolvimento |
| `APPLE_TEAM_ID` | Opcional até a conta existir. Os mesmos 10 caracteres do Team ID. Publica `applinks` e `webcredentials` no ficheiro da Apple |
| `NATIVE_AUTH_HANDOFF_KEY` | Opcional. 32 bytes em Base64 ou 64 caracteres hex. Cifra a sessão guardada por 90 segundos. Se faltar, o servidor usa `BETTER_AUTH_SECRET` |

Sem as variáveis de avisos o site continua igual e os avisos do navegador continuam. Os avisos do iPhone só passam a sair depois disto **e** de publicar esta versão do site.

Depois de gravar `APPLE_TEAM_ID`, publique o site. O ficheiro `https://katecheo.app/.well-known/apple-app-site-association` tem de listar `TEAMID.com.verse2note.app` em `applinks` e em `webcredentials`. A Apple guarda uma cópia e pode demorar algumas horas a vê-la. No Google Cloud o redirect autorizado canónico é `https://katecheo.app/api/auth/callback/google` (mantenha também os de verse2note.com até o cutover). O perfil de provisionamento tem de incluir Associated Domains.

#### 4. Publicar o site

O app nativo fala com a API que está no ar em katecheo.app. Ícone e ecrã de abertura vêm no app. Partilha nativa, avisos e o login pelo navegador do sistema passam a funcionar com esta versão publicada.

### Desenvolvimento

```bash
npm run ios:check
npm run ios:sync
```

`ios:sync` actualiza metadados Capacitor residuais (o UI host já não é Capacitor — ver `docs/ios-phase7-native-editor.md`).

## API / agentes

- Docs: [/for-ai](https://katecheo.app/for-ai)
- `GET /api/link?ref=João+3:16`
- `GET /api/collections?id=salvation`
- `GET /api/plans?id=gospels-30&day=1`
- Skill: [/skill.md](https://katecheo.app/skill.md)
- MCP: `POST /api/mcp` (`katecheo_link`, `katecheo_collection`, `katecheo_plan`)
- LLMs: [/llms.txt](https://katecheo.app/llms.txt)
- Sitemap: [/sitemap.xml](https://katecheo.app/sitemap.xml)
