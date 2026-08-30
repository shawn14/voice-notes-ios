#!/usr/bin/env node
import { loadCloudKitSnapshot } from './cloudkit.js'

const snapshot = await loadCloudKitSnapshot()

const result = {
  source: snapshot.source ?? 'cloudkit',
  vault: snapshot.vault,
  notes: snapshot.notes.length,
  articles: snapshot.articles.length,
  last_change: snapshot.lastChange ?? null,
  error: snapshot.error ?? null,
  samples: snapshot.notes.slice(0, 5).map((note) => ({
    id: note.id,
    title: note.title,
    date: note.date,
    updated: note.updated
  }))
}

console.log(JSON.stringify(result, null, 2))

if (snapshot.error) {
  process.exit(1)
}
