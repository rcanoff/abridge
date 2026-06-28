The submitted diff references new Rust modules that are not included in the patch. On a clean checkout of `main`, applying this diff leaves the crate and its integration tests uncompilable.

Full review comments:

- [P1] Include the new `http` module in the patch — /Users/rcanoff/Projects/apple-bridge/rust/apple_bridge_core/src/lib.rs:6-6
  Applying this diff on top of `main` does not compile: `lib.rs` now declares `mod http;`, but `git diff 7f2eac04d25a4949a2797d3d4f5f8d0fa6c3345a` does not include `rust/apple_bridge_core/src/http.rs`. On a clean checkout this fails with `E0583: file not found for module 'http'`, so the HTTP server changes cannot build as submitted.

- [P1] Add the new `tests/support/port.rs` helper to the patch — /Users/rcanoff/Projects/apple-bridge/rust/apple_bridge_core/tests/support/mod.rs:1-2
  The updated tests now import `support::port`, but the diff does not add `rust/apple_bridge_core/tests/support/port.rs`. After the library module issue is fixed, a clean application of this patch still fails to compile the integration tests with `E0583` for the missing `port` module, so `cargo test` cannot pass from the submitted diff alone.
