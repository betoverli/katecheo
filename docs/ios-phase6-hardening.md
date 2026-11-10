# Phase 6 — Hardening + importação do WebView

## O que havia só no WebView (pré–PR #44)

O shell Capacitor carregava **`https://verse2note.com`** (não `capacitor://`), então o
estado local ficava no `WKWebsiteDataStore` default desse origin. **Não havia IndexedDB**
para o caderno — tudo era `localStorage`:

| Chave | Conteúdo |
| --- | --- |
| `cita-settings` | zustand persist: notas (≤200), speakers (≤80), prefs, `myCollections`, `planProgress`, … |
| `verse2note-outbox` | fila offline: `note.*`, `speaker.*`, `collection.*`, `prefs`, `plan.*` |
| `grok-auth.bearer-token` | bearer (backup se o cookie não migrar) |
| cookie `__Host-grok-auth.session_token` | já coberto por `NativeSessionBootstrap` |

## Importação (uma vez)

`LegacyWebStorageImporter` (@MainActor, main thread):

1. Abre um `WKWebView` oculto em `https://verse2note.com/auth/native-config`.
2. Lê as chaves acima via `evaluateJavaScript`.
3. Converte notas legadas → **NoteDocumentV1** (`LegacyNoteConverter`).
4. Faz merge no `LocalNoteCache` (mesmo `id` → fica o `updatedAt` mais novo).
5. Enfileira upserts no `NativeOutbox` (prefs / speakers / collections).
6. **Nunca** enfileira deletes — importação não apaga dados do servidor.
7. Marca `UserDefaults` `katecheo.legacyWebImport.v1` (`empty` / `extracted` / `completed`).
8. Seguro para retry: reextrair WebKit só em `pending`; depois só faz flush da outbox.

Coleções: `POST /api/native/v1/my-collections` aceita `id` do cliente (upsert idempotente).

## Hardening

- **Outbox nativa** (`NativeOutbox`): persistência em Application Support, dedupe, backoff
  exponencial (`2^n` s), flush no cold start / foreground / após login.
- **401**: `NativeAPIClient.handleUnauthorized` limpa Keychain e posta
  `nativeSessionDidExpire` → `SceneDelegate` apresenta login de novo.
- **Estados vazios / erros** em **pt-BR** (caderno, grupos, login, exclusão, sessão).
- Saves offline no editor: local + outbox (`Salvo no aparelho — sincroniza quando houver rede.`).

## O que o Beto deve testar (TestFlight)

1. Atualizar a partir de um build Cap antigo (com notas só no aparelho / outbox pendente) e
   confirmar que as notas aparecem no Caderno nativo sem duplicar no servidor.
2. Abrir o app offline, editar uma nota, voltar online → outbox sincroniza.
3. Forçar sessão expirada (token inválido) → pede login; após entrar, outbox retoma.
4. Confirmar textos em português do Brasil (Entre / Excluir / Senha / Salvar — não
   “Inicia / Apagar / Palavra-passe / Guardar”).
5. Smoke: criar nota, speakers, grupo, perfil, versículos; miolo nativo (Fase 7)
   é o único editor WebView.
