import type { VaultSnapshot } from './model.js'
import { cloudKitSourceRequested, loadCloudKitSnapshot } from './cloudkit.js'
import { loadVault } from './vault.js'

export function loadMemorySnapshot(vaultPath: string): VaultSnapshot | Promise<VaultSnapshot> {
  if (cloudKitSourceRequested()) {
    return loadCloudKitSnapshot()
  }
  return loadVault(vaultPath)
}
