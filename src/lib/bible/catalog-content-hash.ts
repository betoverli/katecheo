/**
 * Stable content hashing for Themes / Reading catalog versions.
 * Pure module (no catalog imports) so node:test can exercise it directly.
 */
import { createHash } from "node:crypto";

/** Recursive JSON with sorted object keys — key reorder does not change the hash. */
export function stableSerialize(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

function canonicalize(value: unknown): unknown {
  if (value === null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.map(canonicalize);
  const obj = value as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const key of Object.keys(obj).sort()) {
    out[key] = canonicalize(obj[key]);
  }
  return out;
}

/** Hex sha256 of stableSerialize(value). */
export function contentHash(value: unknown): string {
  return createHash("sha256").update(stableSerialize(value)).digest("hex");
}

export function themesVersionFromContent(collections: unknown): string {
  return `themes-${contentHash(collections)}`;
}

export function readingVersionFromContent(plans: unknown): string {
  return `reading-${contentHash(plans)}`;
}
