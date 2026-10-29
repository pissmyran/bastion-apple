# Sync format

Bastion for Apple is the **source** of the sync format. The Swift models in `Sources/SSHCore/` (`Host`, `HostStore`, `Snippet`, `SyncEngine` and `SyncCrypto`) define the format, and the fixtures in `Tests/fixtures/` are the contract the other platforms test against.

## When the format changes

1. Change the Swift model and the fixture in the same PR, and say in the PR that the format changed.
2. Open an issue in every affected platform repo ([Linux](https://github.com/pissmyran/bastion_linux), [Windows](https://github.com/pissmyran/bastion_windows)) with a link to the PR, so their fixture copies and readers get updated.
3. Never change a fixture just to make a test pass. A failing test means the format changed, and the question is what happens to files users have already saved.
