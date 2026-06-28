The new server lifecycle wiring leaves observable state inconsistent on startup and runtime failures. Those cases make the public status API misleading and can wedge a `ServerHandle` in a permanently-running state after the background task exits.

Full review comments:

- [P2] Record bind failures in `ServerStatus.last_error` before returning — /Users/rcanoff/Projects/apple-bridge/rust/apple_bridge_core/src/server.rs:137-142
  When `start()` fails on `inner.runtime.block_on(start_http_server(...))` (for example because the port is already in use), the `?` returns immediately and leaves `inner.status` at the initial value with `last_error: None`. Any caller that checks `server_status()` after a failed start therefore sees a clean stopped state and has no way to surface the startup error through the status API this type already exposes.

- [P2] Transition out of running state when the Axum task exits unexpectedly — /Users/rcanoff/Projects/apple-bridge/rust/apple_bridge_core/src/server.rs:82-90
  The spawned server task only logs `axum::serve` failures and never clears `running_server` or flips `status.running` back to `false`. In any environment where the accept loop terminates on its own, `server_status()` will continue to report the server as running and subsequent `start()` calls will keep returning `AlreadyRunning`, even though nothing is listening anymore.
