# iOS M0 native build validation

Recorded on 2026-10-20. Inputs and ownership rules: [native provenance](../../native/idevice/PROVENANCE.md). Binary hashes: [idevice-sha256.txt](idevice-sha256.txt). Machine-readable receipt: [build-receipt.json](build-receipt.json).

Follow-up on 2026-10-21: signed installation and Flutter launch on iPhone 16 Pro / iOS 27.0.1 passed. A separate Mac `devicectl` simulation passed WeChat 8.0.79 location-picker A/B and visible recovery checks. This does not validate the app's idevice transport, local pairing or LocalDevVPN path; those remain pending. See the [device report](../../docs/validation/2026-10-21-ios-mac-location.md). The sections below retain the original build-only evidence.

## Passed without a phone

- Fixed idevice source plus the recorded MIT patch built with `cargo build --offline --locked --release --no-default-features --features ring,remote_pairing,tunnel_tcp_stack,dvt,location_simulation -p idevice-ffi` for `aarch64-apple-ios`, `aarch64-apple-ios-sim` and `x86_64-apple-ios`.
- Rust unit test `pairable_host::tests::cancelled_accept_is_repeatable_and_clears_the_output`: **1 passed**, exercising repeated cancellation, null output and release of the single active pairing slot.
- Production Swift `PairingAttemptGate` test (`sh native/idevice/scripts/test-swift-pairing-gate.sh`) passes current-attempt delivery, cancellation, retry, reused operation ID and repeated teardown checks. This test runs on macOS without a phone and does not emulate SRP.
- All handwritten Swift and generated Pigeon Swift passed `swiftc -typecheck -warnings-as-errors -swift-version 5 -target arm64-apple-ios27.0`, using the generated C module and Flutter framework.
- A clang iOS arm64 executable linked the generated C header and archive, referencing pairing accept/cancel and error free. It was **linked only, not run on a phone**.
- XCFramework: arm64 iOS and arm64+x86_64 iOS Simulator; `lipo` confirmed slices and `nm` confirmed pairing, RSD and DVT set/clear exports. Header copies match byte-for-byte.
- SwiftPM binary target and CocoaPods vendored framework point to that same XCFramework. Podspec Ruby syntax and XCFramework plist validation pass.
- Root agent reported `flutter build ios --no-codesign --debug` success including complete Runner.app linking; signed installation is separate.

The Rust upstream emits 13 unused-code/import warnings for the reduced feature set; no Rust build errors were ignored. Swift actor-isolated Flutter registration and Core Location delegates use `@preconcurrency` conformance because Flutter registration is on the main thread and the CLLocationManager is created on the main actor's run loop. FFI pointers are used exclusively by the serial engine queue. Upstream TCP adapters use Send+Sync channels, and DVT remote server drop aborts its reader task.

## Lifecycle review

Clear increments generation before queuing work, so a late set or connect cannot publish its former result over clear. In-flight synchronous FFI calls complete or hit their native timeout before the queue runs clear; their pointers are never freed from the main actor while borrowed. New sets are rejected during the stop barrier. Failed set/clear invalidates the engine connection and keeps recovery unresolved. Restart never replays a set and reports recovery unknown.

Pairing retains callback ownership until the 180-second, cancellable Rust accept returns. Strings are copied before callback return. Cancelling stops Bonjour/relay and requests Rust cancellation; the active slot is not reused until the worker has returned. Credentials serialize directly into Keychain `AfterFirstUnlockThisDeviceOnly` without a plaintext intermediate file. Notifications containing a pairing code are removed at completion/cancellation, and codes are never stored in ordinary snapshots.

## Pending device acceptance

No phone was operated by these checks. iPhone 16 Pro / iOS 27.0.1 still requires user-driven signing and installation, Developer Mode, Xcode/DDI preparation, LocalDevVPN, actual six-digit pairing, authenticated device-service connection, set/clear and independent observations in Apple Maps plus the target App. App background time, lock, cellular changes, process termination and restart have separate unverified behavior.

M0 uses external LocalDevVPN only and has no continuous transport heartbeat; a lost session is identified by the next native operation. Pairing while switching to Settings depends on iOS's finite background grant and cancels if that grant expires. Clear/close retain unresolved recovery if a fresh non-simulated sample is unavailable within the 15-second observation window.
