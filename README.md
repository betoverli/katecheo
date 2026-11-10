# Verse2Note

Picker de referências bíblicas. Escolha livro, capítulo e versos; copie um texto rico com deep link para o app de Bíblia (YouVersion, Logos, Tecarta e outros). Coleções por tema. Planos de leitura de capítulos inteiros.

Live: [verse2note.com](https://verse2note.com)

Português, English, Español. PWA offline. Conta opcional (Google ou e-mail).

## Local

```bash
npm install
npm run dev
```

Abre em `http://localhost:8080`.

## Stack

TanStack Start, React, Tailwind v4. Persistência no aparelho (`localStorage`).

## Login com Google

O botão **Continuar com Google** usa o Google OAuth do Better Auth (credenciais próprias no Google Cloud). Não usa o login da plataforma antiga.

No servidor (Vercel → Settings → Environment Variables), em **Production**:

| Nome | O que é |
| --- | --- |
| `GOOGLE_CLIENT_ID` | Client ID do cliente OAuth do tipo **Web application** |
| `GOOGLE_CLIENT_SECRET` | Client secret desse cliente. Nunca no repositório, e nunca numa variável `VITE_` (essa chega ao navegador) |

As duas têm de existir. Se faltar uma, o site continua no ar, o botão Google não aparece, e entrar com e-mail e senha fica igual. O build não precisa destas variáveis: o servidor lê-as quando arranca. Depois de as gravar, publique de novo para o processo as ver.

`BETTER_AUTH_URL` hoje é `https://verse2note.vercel.app`. O Better Auth monta o callback como `{origem}/api/auth/callback/google`.

No Google Cloud Console → APIs & Services → Credentials → OAuth client ID → **Web application**, em **Authorized redirect URIs**:

Agora (o site que está no ar):

- `https://verse2note.vercel.app/api/auth/callback/google`

Neste computador (os dois endereços são diferentes para o Google):

- `http://localhost:8080/api/auth/callback/google`
- `http://127.0.0.1:8080/api/auth/callback/google`

Mais tarde, quando `verse2note.com` apontar para este site. Não mude o DNS agora; o domínio ainda está noutro sítio:

- `https://verse2note.com/api/auth/callback/google`
- `https://www.verse2note.com/api/auth/callback/google`

Origens JavaScript autorizadas, se o formulário as pedir:

- `https://verse2note.vercel.app`
- `http://localhost:8080`
- `http://127.0.0.1:8080`
- `https://verse2note.com`
- `https://www.verse2note.com`

O regresso do app de iPhone não entra nesta lista. A Apple e o Google só vêem o callback acima; o app volta depois, com um código de uso único.

## App iOS

O site continua a ser o site. O app de iPhone é uma capa nativa (Capacitor) cuja janela abre `https://verse2note.com`. Ícone, ecrã de abertura, avisos da Apple, folha de partilha e abertura da Bíblia (YouVersion e outras) são nativos. O login com Google abre o navegador do sistema e volta para o app, porque a Apple e o Google recusam esse login dentro da janela embutida. E-mail e senha continuam na janela do app. O regresso do login traz só um código de uso único, preso a um segredo que fica no app.

Quem usa o site no navegador não vê diferença. As funções nativas só acordam dentro do app.

### Liquid Glass (barra de cima, abas e botão +)

No iPhone a capa desenha uma barra de navegação mínima (título e botões), a barra de abas (Versículos, Grupos, Caderno, Planos, Perfil) e os botões de nova nota / novo grupo por cima da página, em UIKit. O toque volta para o site: mudar de aba, voltar, o sino, importar, e criar nota ou grupo. A busca do Caderno, dos Planos, dos Grupos e das coleções é um ícone de lupa nessa barra. Tocar abre o campo no lugar do título. Não há uma segunda faixa de busca sempre visível.

A lista desenha-se **por baixo** do título e por baixo da barra de abas. Uma placa `UIGlassEffect` por cima da web view não vê a página: pinta um retângulo liso. Foi isso que o build 43 mostrou — cabeçalho branco opaco, e uma faixa branca debaixo da pílula das abas. A capa deixa as barras transparentes. O desfoque de cima está na página (`backdrop-filter`), que vê a grelha de verdade. No iOS 26 a pílula das abas é a do sistema, sem uma segunda faixa atrás. A cópia em HTML esconde-se enquanto o chrome nativo está no ecrã. O editor de uma nota fica em HTML.

- **iOS 26 ou mais novo, binário feito com o SDK do iOS 26 (Xcode 26):** título e botões nativos, sem placa. A pílula das abas é a do sistema. O + usa o vidro proeminente. O desfoque atrás do título vem do site.
- **iOS 15 a 25, ou um binário compilado com um Xcode mais antigo:** a mesma barra transparente. O desfoque de cima e o da barra de abas vêm do site, porque o desfoque UIKit também não vê a web view. O + é um botão preenchido.
- **Site no navegador e Android:** o plugin não existe. Continuam as barras em HTML/CSS, incluindo o campo de busca no sítio onde sempre esteve. Não fica um buraco vazio.

Isto exige **as duas coisas** outra vez, depois do merge: um **binário novo no TestFlight** e **publicar o site**. A capa tira as placas opacas. O site desenha o desfoque e deixa a grelha entrar debaixo das barras. Uma só das duas não chega:

- Site novo + app do build 43: as placas opacas continuam por cima da página.
- App novo + site do build 43: as placas somem, mas o desfoque de cima e o encaixe da grelha debaixo do título ainda não estão.

O salto da lista continua só no miolo (`.screen-body`). As barras nativas são irmãs da web view, não andam com o puxão. O login com Google, o cookie de sessão e o regresso `katecheo://` não mudam.

Para ver: instale o build novo **e** o site novo. Em Versículos, a grelha entra debaixo do título (já no repouso, um pouco) e debaixo da pílula das abas. Não há uma faixa branca de ponta a ponta por baixo da pílula. Role a grelha: os livros passam desfocados atrás do título, e o título não anda com o puxão. Caderno, Planos e Grupos: a busca só depois da lupa. O sino, voltar, as cinco abas, o + de nota e o + de grupo continuam. Uma nota abre com a barra HTML. Entre com Google e confirme a sessão. No Safari e no Android a busca continua visível no cabeçalho.

Não é preciso um Mac para o dia a dia. O GitHub Actions compila num Mac da nuvem. O fluxo escolhe o Xcode 26 mais recente cuja plataforma de simulador está mesmo instalada na imagem — a app do Xcode 26.1 pode existir sem o runtime do iOS 26.1, e nesse caso o vidro entra na mesma por um Xcode 26 mais novo. Sem nenhum SDK 26 com runtime, o binário fica no chrome clássico.

### O endereço é http ou https?

`http://verse2note.com` já responde com um redirecionamento para `https://verse2note.com` e o site pede HTTPS aos navegadores (HSTS). O app abre o endereço **https**.

Não há exceção de rede insegura no app, de propósito. A Apple bloqueia sites `http://` dentro do app, e o cookie de sessão (`__Host-…`, marcado como seguro) nem sequer é gravado em HTTP. Se alguém apontar o app para um endereço `http://`, o login deixa de funcionar. Não mude isso.

### Login do app

O navegador do sistema volta para o app com um código de uso único. Outro app poderia tentar registrar o mesmo nome `verse2note`. Por isso o código sozinho não entra na conta: o app gerou um segredo, mandou só a impressão digital dele, e apresenta o segredo na hora de trocar o código pela sessão. Quem copiar o código não consegue usá-lo.

Com esta versão do site, o app que está no TestFlight pede o regresso `katecheo://`. O binário já abre essa folha. Não pede `https://verse2note.com/auth/native-return`: nessa folha o iPhone recusa ou cancela o login quando a associação de domínio falta ou está velha, e o ecrã trata o cancelamento como desistência — não tenta o esquema a seguir. `/auth/native-config` responde `universalLinks: false` para o script que já está no iPhone pedir o esquema, mesmo que ainda não tenha carregado o script novo. Publicar o site chega. Não é preciso um TestFlight novo.

`https://verse2note.com/auth/native-return` continua no servidor para um app que o peça de propósito. Isso exige iOS 17.4 e os dois serviços no ficheiro da Apple: `applinks:katecheo.app` e `webcredentials:katecheo.app`. Com só o `applinks`, essa folha não abre. `APPLE_TEAM_ID` publica os dois. Não apague a variável.

Se um dia o esquema `verse2note` deixar de voltar ao app — é o mesmo nome que a capa Capacitor usa — aí será preciso um binário novo com outro esquema. O site só pode passar a usá-lo depois desse binário existir.

O código dura 90 segundos e só serve uma vez. No banco fica a sessão cifrada (AES-GCM), não o token legível. Se não houver chave nenhuma, o login do app recusa e não grava nada. O login do site no navegador não usa esta tabela.

### O que já corre sem conta de programador Apple

Em cada pull request, o fluxo **iOS** compila o app para o simulador **sem assinatura**. Isso prova que o projeto abre. Não instala no iPhone e não envia avisos.

### Quando a conta Apple Developer estiver paga

A conta custa cerca de 99 dólares por ano, em [developer.apple.com](https://developer.apple.com). Sem ela não há TestFlight nem App Store, e os avisos nativos não saem do aparelho.

O identificador do app é `com.verse2note.app`. Use esse nome em todo o lado. A versão visível está em `ios/App/Katecheo.xcodeproj/project.pbxproj` (`MARKETING_VERSION`, hoje `1.0`). O número de build do TestFlight sobe sozinho a cada envio.

#### 1. No site da Apple

1. Em Certificates, Identifiers & Profiles, crie um App ID `com.verse2note.app` e marque **Push Notifications** e **Associated Domains**.
2. Crie uma chave **Apple Push Notifications service (APNs)**. Transfira o ficheiro `.p8` uma única vez. Anote o Key ID e o Team ID (10 letras/números).
3. Crie um certificado **Apple Distribution**, exporte-o do Porta-chaves como `.p12` com uma senha, e passe a Base64:
   `base64 -i certificado.p12 | pbcopy` (num Mac) ou peça a alguém com Mac. Guarde a senha.
4. Crie um perfil de provisionamento **App Store** para esse App ID, com esse certificado. Transfira o `.mobileprovision` e passe a Base64 da mesma forma.
5. Em Users and Access → Integrations, crie uma chave de API do App Store Connect com acesso de desenvolvedor. Transfira o `.p8`. Anote o Issuer ID e o Key ID (é outra chave, diferente da de avisos).
6. Em App Store Connect, crie a ficha do app Verse2Note com o mesmo identificador.

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

O envio do aviso fica no site, ao lado dos avisos que o navegador já recebe. Na Vercel (ou onde o site corre), acrescente:

| Nome | O que é |
| --- | --- |
| `APNS_KEY_ID` | Key ID da chave de avisos |
| `APNS_TEAM_ID` | O mesmo Team ID |
| `APNS_PRIVATE_KEY` | Conteúdo do `.p8` de avisos. Se a quebra de linha desaparecer, troque cada quebra por `\n` |
| `APNS_TOPIC` | Opcional. Por omissão `com.verse2note.app` |
| `APNS_ENVIRONMENT` | Opcional. `production` para TestFlight e App Store. `sandbox` só para um app instalado pelo Xcode em modo de desenvolvimento |
| `APPLE_TEAM_ID` | Opcional até a conta existir. Os mesmos 10 caracteres do Team ID. Publica `applinks` e `webcredentials` no ficheiro da Apple. O login do app no TestFlight volta por `katecheo://` mesmo com esta variável definida. Não a apague: o site já pede o esquema |
| `NATIVE_AUTH_HANDOFF_KEY` | Opcional. 32 bytes em Base64 ou 64 caracteres hex. Cifra a sessão guardada por 90 segundos. Se faltar, o servidor usa `BETTER_AUTH_SECRET`, que o site já tem. Se as duas faltarem, o login do app para e o banco não recebe o token |

Sem as variáveis de avisos o site continua igual e os avisos do navegador continuam. Os avisos do iPhone só passam a sair depois disto **e** de publicar esta versão do site.

Depois de gravar `APPLE_TEAM_ID`, publique o site. O ficheiro `https://verse2note.com/.well-known/apple-app-site-association` tem de listar `TEAMID.com.verse2note.app` em `applinks` e em `webcredentials`. A Apple guarda uma cópia e pode demorar algumas horas a vê-la. O login do TestFlight não espera por essa cópia: publica-se o site e o botão Continuar com Google do build já instalado passa a abrir a folha `katecheo://` e a voltar com a sessão. Não é preciso um binário novo, nem alterar o Google Cloud, o `Info.plist` ou o `capacitor.config.ts`. No Google Cloud o redirect autorizado continua a ser `https://verse2note.com/api/auth/callback/google` — não se acrescenta o esquema `verse2note`. O `Info.plist` já tem esse esquema, e o `capacitor.config.ts` não deve passar a abrir `accounts.google.com` dentro da janela do app. O perfil de provisionamento tem de incluir Associated Domains (cobre `applinks` e `webcredentials`).

#### 4. Publicar o site

O app mostra o site que está no ar. Ícone e ecrã de abertura já vêm no app. Partilha nativa, avisos e o login pelo navegador do sistema passam a funcionar quando esta versão estiver em verse2note.com.

### Desenvolvimento

```bash
npm run ios:check
npm run ios:sync
```

`ios:sync` copia a configuração para o projeto Xcode. Para apontar o app a outro site HTTPS durante um teste: `CAPACITOR_SERVER_URL=https://exemplo.com npm run ios:sync`. Não use `http://`.

## API / agentes

- Docs: [/for-ai](https://verse2note.com/for-ai)
- `GET /api/link?ref=João+3:16`
- `GET /api/collections?id=salvation`
- `GET /api/plans?id=gospels-30&day=1`
- Skill: [/skill.md](https://verse2note.com/skill.md)
- MCP: `POST /api/mcp` (`verse2note_link`, `verse2note_collection`, `verse2note_plan`)
- LLMs: [/llms.txt](https://verse2note.com/llms.txt)
- Sitemap: [/sitemap.xml](https://verse2note.com/sitemap.xml)
