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
- Toolbar acima do teclado: título, listas, checklist, citação, negrito/itálico/
  sublinhado/riscado, inserir referência bíblica (picker nativo da Fase 4).
- Toque em `bibleRef` → abre a Bíblia (`resolveBibleLink` + prefs do Perfil).
- Undo/redo do sistema; autosave com debounce → `LocalNoteCache` + outbox.
- Dynamic Type, dark mode, labels de VoiceOver.

## Testar (Beto)

1. Abrir uma nota existente — título e corpo aparecem sem WebView.
2. Digitar, formatar (negrito, lista, checklist), desfazer.
3. Inserir referência bíblica pela toolbar; tocar nela e confirmar que abre o app.
4. Matar o app / modo avião: edição fica no aparelho e sincroniza depois.
5. Confirmar que não há superfície WebView ao editar notas.

Schema Android: `docs/note-document-v1.md`.
