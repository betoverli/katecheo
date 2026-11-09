# Build 238 — bolinhas + limites

## Cinco fixes (preservados)

1. Editor Light opcional  
2. Tags sob o título salvam  
3. Confirmações nativas de delete  
4. Lists empty alinhado  
5. Themes + Reading search até puxar  

## Escopo Beto — implementado (sem merge/deploy)

| # | Endpoint nativo Bearer | Wrap / mudança |
| --- | --- | --- |
| 1 | `GET/POST links*` | list / search / request / accept / decline |
| 2 | `GET notes/granted` | listGrantedNotes |
| 3 | `GET notifications` (+ cursor) · `summary` · `POST read` | inbox paginado + `read_at` |

## Limites resolvidos

1. `POST /links/request` + `GET /links/search` — Amigos busca/@handle + cancel via decline  
2. Inbox cursor (`created_at,id`) + `GET /notifications/summary`; unread nunca trimado  
3. Push → `handlePushHint` → refresh servidor; `ingestPush` é no-op  

## Limitações restantes (honestas)

- Sem notification-center UI (só bolinhas + destinos)  
- `searchPeople` / request usam @handle como o web (não email/código)  
- Offline: push não inventa dots; estado local anterior permanece até rede  

## Fora de escopo até nova aprovação

Merge · TestFlight · deploy produção · mutações live manuais
