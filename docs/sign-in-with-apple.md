# Sign in with Apple (iOS nativo)

Guideline 4.8 da App Store: com Google já no ecrã de login, o app também oferece **Sign in with Apple**.

Fluxo: `ASAuthorizationAppleIDButton` → identity token + `authorizationCode` + nonce → `POST /api/native/v1/auth/apple` → sessão Better Auth (`{ ok: true, token }`) no Keychain.

Bundle id (inalterado): `com.verse2note.app`.

## Apple Developer

1. Em [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), abra o App ID `com.verse2note.app`.
2. Ative a capability **Sign in with Apple** (Default).
3. Em **Keys**, crie uma chave **Sign in with Apple** ligada a esse App ID. Guarde o **Key ID** e o ficheiro `.p8` (só é mostrado uma vez).
4. Confirme o **Team ID** (Membership).
5. O perfil de provisionamento / entitlements do target já incluem `com.apple.developer.applesignin = [Default]` (`AppRelease.entitlements`).

Não é preciso Services ID para o fluxo nativo (o `aud` do identity token é o App ID). Services ID / return URLs de web (se existirem) continuam documentados em `docs/domain-cutover.md` — **não altere** a lógica de redirect verse2note.com ↔ katecheo.app.

## Variáveis na Vercel

| Nome | Obrigatório? | Uso |
| --- | --- | --- |
| `APPLE_CLIENT_ID` | **Sim** (para o botão aparecer) | App ID, tipicamente `com.verse2note.app`. Audience do JWT + client_id no exchange/revoke. |
| `APPLE_TEAM_ID` | Para exchange/revoke (e AASA) | Team ID de 10 caracteres. |
| `APPLE_SIGNIN_KEY_ID` | Para exchange/revoke | Key ID da chave Sign in with Apple (não a de APNs). |
| `APPLE_SIGNIN_PRIVATE_KEY` | Para exchange/revoke | Conteúdo do `.p8` (ou Base64). Quebras de linha podem ir como `\n`. |
| `APPLE_CLIENT_SECRET` | Só para Apple **web** via Better Auth | JWT client_secret pré-gerado. O nativo **não** depende disto. |

Com só `APPLE_CLIENT_ID`, o login nativo funciona (verificação JWKS). Sem a chave Sign in with Apple, o servidor regista um aviso e **salta** a troca do `authorizationCode` e o revoke no delete — a sessão é criada na mesma.

## Delete de conta

O caminho de delete já existente (`POST /api/native/v1/account/delete` e o delete web) chama `https://appleid.apple.com/auth/revoke` quando o utilizador tem `apple_sub` e um refresh token guardado. Sem env vars / token, o revoke é ignorado com aviso — a UI de delete não muda.

## Testes

- `src/lib/auth/apple-verify.test.ts` — JWT válido / aud errado / nonce errado / expirado
- `src/lib/auth/apple-link.test.ts` — find / link por email / create
- `npm run ios:check` — botão Apple no ecrã de login + entitlement
