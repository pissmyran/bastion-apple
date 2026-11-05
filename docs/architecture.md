# Architecture

Bastion for Apple is a shared core with three apps on top.

```text
              +--------------------+
              |      SSHCore       |
              |  SwiftNIO SSH, NIO |
              +---------+----------+
                        |
       +----------------+-----------------+
       |                |                 |
  bastion-cli      iOS and macOS        tvOS
     Swift         App/ (SwiftUI)     App/TVApp/
```

## SSHCore

`Sources/SSHCore/` holds everything that is not user interface. The core is built and tested with Swift Package Manager, without Xcode, on Linux and macOS.

| Area | Examples |
| --- | --- |
| SSH | Sessions, shell and exec, user authentication, key parsing, OpenSSH certificates, SSH agent, Secure Enclave keys |
| Host keys | Trust-on-first-use validation (`HostKeyValidator`) and `KnownHosts` |
| Transfer and forwarding | SFTP, archives, local, remote and dynamic (SOCKS) port forwarding, `ProxyJump` |
| Other connections | Telnet, serial, Wake-on-LAN, WireGuard profiles, Tailscale status |
| Data | The host list (`Host`, `HostStore`), snippets, command library, `~/.ssh/config` import, app settings, S3 connections |
| Sync | `SyncEngine`, `SyncProvider`, the folder transports and `SyncCrypto`; see [Sync format](sync-format.md) |
| Integrations | Docker, Kubernetes, Proxmox, TrueNAS, Unraid, Cloudflare, GitHub, Bitwarden and S3 clients, OAuth (PKCE) tokens |

Reading `~/.ssh/config` expands `Include` inline, skips cycles and reads only regular files. A load from disk stops at shared limits (256 file reads, 8 MiB, 100,000 entries and host patterns, 4,096 directory entries, 4,096 include patterns) and keeps what it read before the limit, so a hostile or runaway config cannot exhaust memory or time.

Importing an SSH config adds only aliases that do not exist yet and never changes existing hosts. A host whose `ProxyJump` cannot be linked (unresolved, pointing at itself, several hops, or a jump host that has its own jump, since connections support one hop) is skipped together with the hosts that depend on it, so the app never connects directly to a host that is meant to be reached through a jump.

Remote port forwarding reserves each remote port once per session, whatever the bind host. Port 0 (a server-assigned port) is allowed only while no other port is reserved. A listen request that gets no answer within 30 seconds fails and closes the session. `close()` stops routing, waits up to one second for the server to confirm the cancellation and releases the reservation only on that confirmation; a listen or cancel with an uncertain outcome keeps its reservation for the rest of the session.

Local and SOCKS forwards share one shutdown gate (`ForwardConnections`). `close()` first stops admitting new connections and SSH channel opens, then closes the listener and every active connection, and waits for pending SSH channel opens to resolve. That wait is bounded to 15 seconds, the same bound as the session drain; opens that still have not resolved are abandoned so a stuck open cannot block session cleanup or keep the forward alive.

`ExternalBinaryFetcher` caches a downloaded binary at `cacheDir/<checksum>/<binaryName>`. The SHA-256 is verified before the file is renamed into place, so a failed or mismatching download leaves an existing cache entry untouched.

The cache validates its input: `binaryName` must be a single file name (no separators, `.`, `..` or NUL), the checksum must be 64 lowercase hex characters, and `cacheDir` must be trusted. A cache hit must be a regular file opened without following symbolic links, so a link is never accepted even when its target matches the checksum. A directory in place of the file is replaced only after a verified download.

System metrics parsed from remote output (memory, disk, uptime) are range-checked. A value that is negative, larger than its total, not finite or whose kilobyte-to-byte conversion overflows is rejected: the memory probe returns no result and the disk probe skips that line.

OAuth token refreshes are serialized per provider. Each logout or login bumps a generation counter for the provider. A refresh result that arrives after the account changed (the generation differs) is discarded and never overwrites a newer login. Only `invalid_grant` means the refresh token is permanently invalid; it deletes the stored token and requires a new sign-in, unless a newer login has replaced it in the meantime. An expired token without a refresh token is never returned as valid.

The tvOS OAuth token store keeps tokens in the Keychain. It is compiled outside Xcode, with an in-memory Keychain, by `Tests/TVAppTests/run-token-store-tests.sh` (Linux only).

The package declares macOS 13 and iOS 16 as minimum platforms.

## The apps

- **iOS, iPadOS and macOS** share the code in `App/` and are separate targets (`Bastion`, `Bastion-macOS`). The terminal is built on SwiftTerm. The macOS app is sandboxed with network client and serial device entitlements.
- **tvOS** lives in `App/TVApp/` (`Bastion-tvOS`) and must not get SwiftTerm or APIs that tvOS lacks. Cloud sign-in uses the OAuth device flow.
- **Cloud sync** in the apps uses OAuth: Dropbox, Google Drive and OneDrive on iOS and macOS; Google Drive and OneDrive on tvOS.
- **Deployment targets** for the apps are iOS 17, macOS 14 and tvOS 17 (`App/project.yml`).
- **The Xcode project** is generated by XcodeGen through `App/generate-project.sh`, which uses `App/project.dependencies.yml`: it includes `App/project.yml` and pins SwiftTerm to the exact version in `App/Package.swift`. `App/Package.swift` is the dependency manifest that Renovate reads; it must never end up among the app's source files.

## Dependency boundaries

| Manifest | Owns |
| --- | --- |
| `Package.swift` | SSHCore and bastion-cli (swift-nio-ssh, swift-nio, swift-crypto) |
| `App/Package.swift` | The apps' Swift packages, for example SwiftTerm |
| `App/Gemfile` | fastlane |

Update a dependency in the manifest that actually owns it. Renovate opens the updates, using the shared configuration that `renovate.json` extends. Two pins in `Package.swift` are deliberate and explained in comments: swift-nio-ssh follows a branch until upstream accepts swift-crypto 5.x, and swift-nio is pinned exactly because of a Windows compile bug upstream.

## Signing and distribution

`App/project.yml` holds the signing settings: the development team, manual signing and the provisioning profile names for each target. `App/fastlane/Fastfile` has a `beta` lane for iOS and for tvOS that fetches certificates and profiles read-only with `match` and uploads to TestFlight. The App Store Connect API key, team ID and match credentials come from environment variables. The Fastfile refers to a `.github/workflows/testflight.yml` workflow, but no such workflow exists in the repo.

## Security boundary

SSHCore owns host key verification and authentication. The user interface must never build shortcuts around the core's checks. Keys and passwords are stored in the keychain, never in files in the repo or in test data. The exceptions are WireGuard profiles (`~/.bastion/wireguard.json`) and S3 connections (`~/.bastion/s3connections.json`), which hold private and secret keys in files: SSHCore writes them through `PrivateFile`, owner-only (0600, in a 0700 directory) from the moment they exist.

Key deployment (`KeyManagement`) appends exactly one `authorized_keys` record: it rejects empty keys and keys containing CR, LF or NUL before building the remote command, and generated public key lines drop comments containing those characters.

Local files reach the remote side only through SSHCore's guarded readers: SFTP uploads (`SFTPUploadSource`) open each entry relative to its parent directory descriptor and refuse symbolic links and special files, so a path swapped during an upload cannot redirect the read.

ZIP archives are extracted on the server by a Python 3 script (`ArchiveOperations.extractZipCommand`) instead of `unzip`: it rejects absolute paths, `..`, symbolic links and special files, refuses archives whose declared size exceeds the free space, and writes through directory descriptors so existing links in the destination cannot redirect writes. The server therefore needs Python 3 to extract ZIP files.
