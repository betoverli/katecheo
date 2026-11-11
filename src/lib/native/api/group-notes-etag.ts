/**
 * Weak ETag fingerprint for a group's notes list (id + updatedAt).
 * Pure helper — safe to unit-test without Postgres.
 */
export function groupNotesEtag(
  notes: Array<{ note: { id: string; updatedAt: string } }>,
): string {
  const parts = notes.map((card) => `${card.note.id}:${card.note.updatedAt}`).sort();
  // FNV-1a 32-bit — enough for conditional GET, no crypto dependency.
  let hash = 0x811c9dc5;
  const input = parts.join("|");
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return `W/"gnotes-${(hash >>> 0).toString(16)}-${notes.length}"`;
}
