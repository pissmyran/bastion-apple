# Sync format

Bastion for Apple is the **source** of the sync format. The Swift models in `Sources/SSHCore/` (`Host`, `HostStore`, `Snippet`, `SyncEngine` and `SyncCrypto`) define the format, and the fixtures in `Tests/fixtures/` are the contract the other platforms test against.

## What is synced

`SyncState` is the JSON document a transport reads and writes:

| Field | Contents |
| --- | --- |
| `hosts` | The host list |
| `snippets` | Snippets. Added after the format was in use, so a missing field is read as no snippets |
| `tombstones` | Deleted IDs with deletion time, shared by hosts and snippets |

`SyncCrypto` encrypts the document for transports that store it elsewhere: the key is derived with PBKDF2-HMAC-SHA256 and the payload is sealed with AES-256-GCM, in an envelope that starts with `BSYNC1`. SSHCore provides `FolderSyncProvider` (a plain JSON file) and `EncryptedFolderSyncProvider`; the apps add Dropbox (iOS and macOS only), Google Drive and OneDrive.

## Fixtures

| File | Read by | Contract |
| --- | --- | --- |
| `host-wire-format.json` | `HostStoreTests` | A host on the wire |
| `sync-state-wire-format.json` | `SyncEngineTests` | A whole `SyncState` |
| `tailscale-stable-index.json` | none of the Swift tests | Not part of the sync format |

## The other platforms

- **[Linux](https://github.com/Pissmyran/bastion-linux)** keeps copies of the fixtures in `LinuxApp/tests/fixtures/`.
- **[Windows](https://github.com/Pissmyran/bastion-windows)** has its own sync implementation with its own fixture (`csharp-hosts-fixture.json`), not copies of these. Its `SyncState` has only `hosts` and `tombstones`: it does not read snippets, and a document it writes has no `snippets` field.
- **[Android](https://github.com/Pissmyran/bastion-android)** has no sync yet.

## When the format changes

1. Change the Swift model and the fixture in the same PR, and say in the PR that the format changed.
2. Open an issue in every platform repo that implements sync (today [Linux](https://github.com/Pissmyran/bastion-linux) and [Windows](https://github.com/Pissmyran/bastion-windows)) with a link to the PR, so their fixtures and readers get updated.
3. Never change a fixture just to make a test pass. A failing test means the format changed, and the question is what happens to files users have already saved.
