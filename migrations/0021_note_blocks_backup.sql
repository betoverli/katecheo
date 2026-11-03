-- Phase 7: keep original HTML/legacy payload when converting blocks → NoteDocumentV1.
alter table notebook_notes add column if not exists blocks_backup text;
