# Fase 7 — Editor nativo (sem WebView)

**Objetivo:** o app iOS edita o miolo da nota 100% em UIKit (`UITextView`),
lendo/gravando **NoteDocumentV1**. Não há mais `WKWebView` de produto para notas.

## O que mudou

| Antes (Fase 5/6) | Depois (Fase 7) |
| --- | --- |
| `NoteMioloEditorView` → `/native-editor` | `NativeNoteEditorView` (UITextView + toolbar) |
| Body em textarea HTML/JS | `NoteDocumentCodec` ↔ `NSAttributedString` |
| `blocks` legado ou HTML opaco | Envelope V1 `{"v":1,"blocks":[…]}` + `blocks_backup` |

## UX (pt-BR)

- Primeira linha = título (estilo Notas da Apple); restante = corpo.
  O título **não** aparece na navigation bar (só no corpo).
- Toolbar acima do teclado: título, listas, checklist, citação, negrito/itálico/
  sublinhado/riscado, inserir referência bíblica (grid de siglas como em Versículos).
- Secção de speaker: cartão com barra de cor, avatar (inicial) e nome.
- Listas com marcadores `•` / `1.` / ☐ (persistidos como `bullet`/`numbered`/`check` no V1;
  os glifos de marcador são só de apresentação).
- `@` abre menu inline de speakers; `/` abre menu inline (referência + blocos).
- Toque em `bibleRef` → abre a Bíblia (`resolveBibleLink` + prefs do Perfil);
  hit-test distingue o pill do texto/speaker ao lado.
- Insets do teclado + scroll do caret para o fim da nota continuar editável.
- Undo/redo do sistema; autosave com debounce → `LocalNoteCache` + outbox.
- Dynamic Type, dark mode, labels de VoiceOver.

## Testar (Beto)

1. Abrir uma nota existente — título e corpo aparecem sem WebView.
2. Digitar, formatar (negrito, lista, checklist), desfazer.
3. Inserir referência bíblica pela toolbar; tocar nela e confirmar que abre o app.
4. Matar o app / modo avião: edição fica no aparelho e sincroniza depois.
5. Confirmar que não há superfície WebView ao editar notas.

Schema Android: `docs/note-document-v1.md`.
