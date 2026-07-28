//! Regression: a wrapped tool that SUCCEEDS and writes to stderr must not have
//! that stderr silently discarded.
//!
//! `run_captured_filter` captures stdout and stderr separately. With
//! `RunOptions::stdout_only()` (37 call sites: pytest, ruff, prettier, gh,
//! glab, phpunit, phpstan, pint, psql, ...) both the filtered text and the
//! never-worse guard's reference are `raw_stdout`. `raw_stderr` was then read
//! only inside the `exit_code != 0` early-exit branch -- so on a SUCCESSFUL
//! run it was captured and never printed.
//!
//! Neither safety net catches it:
//!   * `guard::never_worse` compares ESTIMATED TOKEN COUNT, not content, so a
//!     short summary always "wins" and no fallback is forced.
//!   * `tee` defaults to `TeeMode::Failures`, whose `should_tee` returns None
//!     on exit 0 -- no recovery file, no "[full output: ...]" hint.
//!
//! So the loss was silent AND unrecoverable: a deprecation warning, a
//! "using defaults" notice, or an auth warning on an otherwise green run
//! simply vanished.

#![cfg(unix)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

const MARKER: &str = "RTK_TEST_MARKER_DEPRECATED_FIXTURE";

/// Builds a throwaway `pytest` on PATH that exits 0 while writing to BOTH
/// streams, then returns rtk's stdout+stderr combined.
fn run_rtk_against_shim(tool: &str) -> (bool, String) {
    let dir = std::env::temp_dir().join(format!("rtk_stderr_test_{}_{}", tool, std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("create shim dir");

    let shim = dir.join(tool);
    fs::write(
        &shim,
        format!("#!/bin/sh\necho '3 passed in 0.10s'\necho '{MARKER}' >&2\nexit 0\n"),
    )
    .expect("write shim");
    fs::set_permissions(&shim, fs::Permissions::from_mode(0o755)).expect("chmod shim");

    let path = format!(
        "{}:{}",
        dir.display(),
        std::env::var("PATH").unwrap_or_default()
    );

    let out = Command::new(env!("CARGO_BIN_EXE_rtk"))
        .arg(tool)
        .env("PATH", path)
        .current_dir(&dir)
        .output()
        .expect("run rtk against shim");

    let _ = fs::remove_dir_all(&dir);

    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    (out.status.success(), combined)
}

#[test]
fn stderr_survives_a_successful_stdout_only_filter() {
    let (success, combined) = run_rtk_against_shim("pytest");

    assert!(success, "the shim exits 0, so rtk must report success too");
    assert!(
        combined.contains(MARKER),
        "stderr from a SUCCESSFUL command was dropped -- it appeared on neither \
         of rtk's streams. A warning on a green run must not vanish. Got:\n{combined}"
    );
}
