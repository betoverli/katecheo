# Build 238 — plano de conclusão das bolinhas

## Cinco fixes (preservados)

1. Editor Light opcional  
2. Tags sob o título salvam  
3. Confirmações nativas de delete  
4. Lists empty alinhado  
5. Themes + Reading search até puxar  

## Escopo aprovado (implementado no PR — sem merge/deploy)

| # | Endpoint nativo Bearer | Wrap de | iOS |
| --- | --- | --- | --- |
| 1 | `GET /links`, `POST /links/accept\|decline` | `listLinks` / `acceptLink` / `declineLink` | Amigos com aceitar/recusar; pending até decisão |
| 2 | `GET /notes/granted` (+ GET `/notes/:id` via grant) | `listGrantedNotes` / grant read | Chip **Compartilhadas** (sem secção nova) |
| 3 | `GET /notifications`, `POST /notifications/read` | `listInbox` / `markRead` (`read_at`) | Digest leitura, groups, shares, friend accepted; seen cross-device |

## Semântica das bolinhas

- Parent tab **não** marca tudo lido  
- Pending friend → só accept/decline  
- Reading due → dismiss/conclusão (+ `markRead`)  
- Shared → abrir nota (+ `markRead`)  
- Sync em foreground / troca de conta (`V2NActivitySync`)  
- Sem notification-center UI  

## Limitações (honestas)

- Inbox nativo herda `limit` do web (`MAX_INBOX`) — sem cursor/pagination além disso  
- `requestLink` (enviar pedido) **não** está neste pacote  
- Push ainda pode pré-acender dots offline até o próximo reconcile  

## Fora de escopo até nova aprovação

Merge · TestFlight · deploy produção · mutações manuais live
