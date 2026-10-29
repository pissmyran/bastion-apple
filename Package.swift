// swift-tools-version:5.9
import PackageDescription

// Bastion: core library plus a CLI that proves the SSH transport.
// SSHCore and bastion-cli build on Linux AND Apple platforms (pure SwiftNIO code).
// The terminal UI (SwiftTerm) lives in App/ and is only built in Xcode; see docs/architecture.md.
// The Linux, Windows and Android apps live in their own repos (bastion_linux,
// bastion_windows and bastion_android) and share no code with this package.
let package = Package(
    name: "bastion",
    platforms: [
        .macOS(.v13), .iOS(.v16),
    ],
    products: [
        .library(name: "SSHCore", targets: ["SSHCore"]),
        .executable(name: "bastion-cli", targets: ["bastion-cli"]),
    ],
    dependencies: [
        // Temporary branch until apple/swift-nio-ssh accepts swift-crypto 5.x.
        // Upstream fix: https://github.com/apple/swift-nio-ssh/pull/259
        // The branch reference floats; switch back to an official release once the fix ships.
        .package(url: "https://github.com/simonjbeaumont/swift-nio-ssh.git", branch: "widen-swift-crypto"),
        // Pinned exactly because of apple/swift-nio#3647: swift-nio's OWN
        // Sendable/IPPROTO compile errors on Windows, which only trigger when
        // its sources are compiled in Swift 6 strict-concurrency mode, decided by
        // the PACKAGE'S OWN declared tools version, not the consumer's.
        // The pin was first added at 2.86.2 (windows-gui.yml then went
        // green for the first time: 74 failed runs before, 0 successful)
        // and has since moved up with each release, so the pin does NOT hold
        // the version back. It only stops automatic bumps before
        // #3647 is fixed (the Renovate bump in PR #153 brought back exactly the bug
        // PR #149 fixed). Checked 2026-08-11: #3647 still open.
        // Switch back to `from:` once upstream really fixes #3647.
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
        // Keep a floating version range so Renovate can raise the minimum.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.3"),
    ],
    targets: [
        .target(
            name: "SSHCore",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .executableTarget(
            name: "bastion-cli",
            dependencies: ["SSHCore"]
        ),
        .testTarget(
            name: "SSHCoreTests",
            dependencies: [
                "SSHCore",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ]
        ),
    ]
)
