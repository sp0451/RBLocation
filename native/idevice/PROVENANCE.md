# iOS native runtime source and ABI

CLocation embeds the MIT idevice FFI. No Roam, StikDebug or other proprietary/AGPL implementation is included.

## Pinned inputs

| Input | Source / revision | SHA-256 |
| --- | --- | --- |
| idevice source archive | <https://github.com/jkcoxson/idevice/tree/e98264c4194e6980173c576ac79a58adce95492b> | `2f7951cad7b85b6f8ecb1cb05ceb3f9a4a2158b3e78e100fc66d2cff5d15cbc9` |
| Aurora iOS patch | <https://github.com/AuroraNest/Aurora-Location/blob/e475b071ef092090e459836d1c4c48bc89f490b8/Vendor/idevice/aurora-ios.patch> | `01d7f11701c83ee9e3167bd9376ea2aa9ae70b6bef84f97f651154b6a72c79e0` |
| Cargo.lock | Same Aurora revision; exact dependency resolution | `735ead5f87f6b44b2ba033abfef3159e0d27dbf7a1bad44da4a305378e4f1131` |

The archive is checked in under `source/`. The upstream source uses MIT (`licenses/idevice-MIT.txt`). The applied patch and adapted Network.framework relay derive from Aurora Location and Locus under MIT; their complete notices are retained in `licenses/`. `licenses/dependency-LICENSES.txt` is the source project's collected dependency notices for this exact lockfile and feature set. All notices are bundled in the Flutter plugin's `ThirdPartyNotices.txt` for SwiftPM and CocoaPods distribution.

Swift `IdeviceEngine`, `PairingCoordinator` and `PairableHostAdvertiser` use the same documented ABI and ownership rules as those MIT references, with Keychain-only credentials and a separate native session state machine. Locus reference revision: <https://github.com/ChrisMack32/Locus/tree/83c8fb324983728e8f44759cfd834dc637ee38b5>.

## ABI and evidence

The Aurora patch bounds Remote Pairing to 180 seconds and provides cancellation; regular tunnel/RSD/DVT calls use the global 10-second operation timeout. A dropped/failed DVT operation invalidates the retained connection. FFI resources are freed in reverse dependency order: location client, remote server, RSD handshake, adapter.

The patched DVT `set` and `clear` send without waiting for a service reply. CLocation labels these outcomes **sent**, never acknowledged or observed. The pairing handshake itself is authenticated; possessing a saved pairing record alone is not a successful handshake. The external `10.7.0.1:49152` LocalDevVPN endpoint is fixed for M0, and tunnel traffic authenticates with the native pairing record. There is no public stable local UDID API; target identity relies on authenticated pairing, and an additional hardware-identity comparison is not claimed.

Swift MainActor owns snapshots and sequence/generation watermarks. One serial engine queue owns FFI pointers. Clear establishes a barrier and invalidates earlier set/connect completions before entering that queue. Existing synchronous FFI work is not force-freed from another thread: it finishes or times out before clear runs. New sets are rejected during clear. No reconnection replays a set. App restart reports location effect as unknown (`recoveryRequired = true`).

Core Location observations include source simulation flag, timestamp and accuracy when available. A fresh non-simulated sample acquired after clear can confirm recovery only for this App. Close waits at most 15 seconds for such a sample, then frees the connection while preserving unresolved recovery. Abrupt process death cannot promise cleanup. Session network loss is currently detected by the next FFI operation, not a continuous heartbeat.

Pairing codes are ephemeral callbacks and a removable local notification, never part of snapshots or Keychain records. The system's finite background grant is used while the user switches to Settings; its expiration cancels pairing. There is no silent-audio keep-alive, background-location entitlement, or promise of long-running locked/background simulation.

Each pairing attempt has its public operation ID and a fresh native token. C callbacks, deferred Flutter sends, relay failures and background-expiration callbacks verify that token. Cancelling or finishing invalidates it before teardown; a late callback from a prior attempt cannot publish during a retry, including accidental reuse of the operation ID. Responses must match an interaction issued by the active attempt. Pairing notifications use attempt-specific identifiers and remove late additions after invalidation. Messages already sent across the Flutter channel carry the operation ID so Dart can reject obsolete in-flight PINs.

## Rebuild

Install Rust **1.99.1** plus `aarch64-apple-ios`, `aarch64-apple-ios-sim` and `x86_64-apple-ios`, and use Xcode 27 / iPhoneOS 27 SDK. Run `sh native/idevice/scripts/build-ios.sh` from any directory. The script verifies pinned input hashes, builds with `--locked`, generates the header from that same source, strips debug symbols and creates the XCFramework. `CLOCATION_CARGO` and `CLOCATION_RUSTC` can select an isolated toolchain. `CARGO_HOME` and `RUSTUP_HOME` follow standard Rust semantics.

Only generated headers/libraries in `IdeviceRuntime.xcframework` should change after a source upgrade, never one without the other. Build receipts are under `artifacts/ios/`; hashes are build evidence, not device protocol evidence. A successful compile, signed installation, actual DVT handshake, and independent location observation are distinct acceptance steps. No device has been paired or moved by these build checks.
