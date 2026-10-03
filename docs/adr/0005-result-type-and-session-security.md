# 5. Typed failures and on-device security

- Status: accepted

## Context

Exceptions crossing layer boundaries are easy to forget to catch, and raw
error text (`DioException [bad response]…`) leaks into UIs. A finance app also
needs defence in depth on the device itself.

## Decision

### Errors

- Repositories return a sealed `Result<T>` (`Ok` / `Err`) carrying a sealed
  `Failure` (`NetworkFailure`, `AuthFailure`, `InsufficientFundsFailure`, …).
- The compiler forces callers to handle both branches with `switch`.
- The UI maps failures to localized messages in one place
  (`AppLocalizations.failureMessage`). Technical details stay in
  `Failure.detail` for logs.

### Session and tokens

- Access and refresh tokens are stored in the Keychain / Keystore
  (`flutter_secure_storage`), with an in-memory cache.
- The refresh token **rotates** on use. The `AuthInterceptor` refresh is
  single-flight: concurrent 401s wait for one refresh, then replay.
- A refresh rejected with 401 ends the session. A refresh that fails because
  of the network does not, so the user is not logged out by a tunnel.

### App lock

- A 6-digit PIN is stored as a salted, iterated SHA-256 hash, never in plain
  text. It is compared in constant time.
- Five wrong attempts wipe the PIN and local data. The counter is persisted, so
  restarting the app does not reset it.
- Biometric unlock is opt-in, with the PIN always available as a fallback.
- The app locks after 30 s in the background.
- On Android, `FLAG_SECURE` blocks screenshots and recording. On both
  platforms, a cover hides balances in the app-switcher snapshot.

## Not done (and why)

- **Certificate pinning.** There is no real backend to pin against. With one, it
  would go in the Dio `HttpClientAdapter`, with backup pins and a remote kill
  switch.
- **PBKDF2/Argon2 for the PIN.** The iterated hash plus the attempt limit and
  the hardware-backed store are adequate for a 6-digit app lock. A memory-hard
  KDF would be the next step.
- **Root/jailbreak detection.** It is easy to bypass and creates support
  burden. It is better handled server-side with device attestation.
