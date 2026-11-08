# Build 238 — plano de conclusão das bolinhas (auditoria READ-ONLY)

Sem merges de heurística. Sem backend até Beto aprovar o escopo.

## Cinco fixes (já no PR — não negociar)

1. Editor Light opcional vs Dark/System do app  
2. Tags sob o título salvam de verdade  
3. Confirmações nativas de delete (notas/grupos)  
4. Lists empty alinhado  
5. Themes + Reading: search escondida até puxar  

## O que o iOS pode fazer **agora** (sem rotas novas)

| Sinal | Destino | Por quê |
| --- | --- | --- |
| Pedidos de grupo pendentes | Grupo → membros → aceitar/recusar | Já existe `GET …/groups/{id}/members` + `POST …/members/decide` |
| Atividade de grupo via APNs | Abre o grupo | Só device-local; limpa ao abrir |
| Digest/plano via APNs `/reading…` | Abre leitura | Só device-local; **não** é “dia sem marca = due” |
| Nota via APNs `/n/{id}` | Abre a nota | Reachable; **não** acende chip Compartilhadas |

## O que **não** está completo (e por quê)

| Pedido | Web já tem | Native `/api/native/v1` | Heurística iOS (recusada) |
| --- | --- | --- | --- |
| Friends pending + accept/reject + aceite | `listLinks`, `acceptLink`, `declineLink` (+ push `kind=friends`) | **Ausente** (router sem `links`/`friends`) | Bolinha em Perfil → Amigos sem ação = beco sem saída → **gate off** |
| Grants reais em Compartilhadas | `listGrantedNotes` (`note_grants`) | **Ausente** | `visibility == shared\|link` nas notes nativas nunca bate grants → **chip off** |
| Leitura agendada (digest) | `maybeSendDigests` → row `notifications` `kind=reading` 1×/dia | Sem inbox nativo | “Qualquer dia sem marca” ≠ digest → **reconcile off** |
| Unread estável de atividade de grupo | Inbox `kind=groups` + `read_at` | Sem inbox nativo | Push-only some ao matar o app / outro device |
| Seen cross-device / conta | `listNotifications` + `markNotificationsRead` (`read_at`) | **Ausente** | UserDefaults por device |

## Plano mínimo proposto (só wraps — lógica de negócio já existe)

Aprovar **um** pacote nativo Bearer espelhando o web (sem redesign):

1. **`GET/POST /api/native/v1/links`** (ou `/friends`)  
   - GET → shape de `listLinks` (`friends` / `incoming` / `outgoing`)  
   - POST accept / decline por `handle` → `acceptLink` / `declineLink`  
   - iOS: Amigos com ações reais + `friendsDotsEnabled = true`

2. **`GET /api/native/v1/notes/granted`**  
   - wrap de `listGrantedNotes`  
   - iOS: Compartilhadas lista grants + bolinha só em grant novo (baseline pós-login)

3. **`GET /api/native/v1/notifications` + `POST …/read`**  
   - wrap de `listInbox` / `markRead` (+ opcional `unreadCount`)  
   - Cobre: digest de leitura, eventos friends/shares/groups, **e** seen cross-device via `read_at`  
   - iOS: reconciliar store a partir do inbox; limpar local ao `markRead`

Opcional depois: `requestLink` nativo (enviar pedido). Não bloqueia accept/reject.

**Não** pedir schema novo: `user_links`, `note_grants`, `notifications.read_at` já existem.

## Gate honesto neste PR

- Bolinhas Shared / Friends / heuristic reading: **desligadas**  
- Grupos pending + push reachable: **ligadas**  
- Tela Amigos: mensagem explícita “aguarda API”; sem bolinha de Perfil  

## Fora de escopo até aprovação

Edits/deploys de backend · merge · TestFlight · fundir badges parciais como “feito”
