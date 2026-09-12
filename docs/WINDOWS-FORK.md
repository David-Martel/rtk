# David-Martel Windows fork

This fork supports the shared Windows Codex and Claude installation. The
2026-09-12 reconciliation merges upstream `rtk-ai/rtk` develop at `fc19d7a`
(0.48.0) into fork develop at `40ded5a` (0.42.4). It preserves upstream history.

## Retained behavior

- Successful stdout-only filters still emit the captured stderr. Otherwise a
  successful command can silently lose warnings without producing a failure tee.
- Git log requests with explicit formats or unrestricted history, and exact Git
  diff modes, retain their original semantics.
- `RTK_CONFIG_DIR` and `RTK_AUDIT_DIR` support isolated Windows configuration and
  audit locations. Composite Claude wrappers identify themselves with
  `RTK_HOOK_COMPOSITE=1`; installation detection does not mistake them for a
  missing RTK hook.
- Windows search shims retain compatible parse flags and avoid GNU-only
  buffering options. Ripgrep uses `-e` for patterns; single-pattern grep puts
  `--` before the pattern, so leading dashes cannot become options.
- Hook unit tests inject empty configuration at the centralized decision layer.
  Production and subprocess integration tests still use real configuration;
  exclusion tests explicitly supply their parameters.

Upstream now provides the native grep `-l` and `-m` handling previously fixed in
this fork. Its centralized hook-decision architecture replaces the old fork
decision implementation; the fork's regression cases remain.

## Client integration

The maintained wrappers live in `dtm-codex/hooks/bin/pre-tool-use-chain.ps1` and
`dtm-claude/scripts/pre-tool-use-chain.ps1`. They evaluate policy first and only
accept an exact `rtk ` prefix for a narrow set of plain build/test commands.
Quoting, Windows paths, shell syntax, search commands and machine-readable output
remain unchanged. Non-command policy fields survive accepted optimization, and
denials cannot carry an input mutation.

Updating this binary does not require `rtk init`; running the installer over
these composite wrappers would discard deployment-specific integration.

## Local validation and deployment

Use PowerShell 7 and CargoTools with a repository-local target directory. Pass
an explicit argument array when a Cargo command contains `--`: PowerShell's
advanced-function binder can otherwise consume the separator before CargoTools
receives it.

```powershell
Import-Module CargoTools -Force
Test-BuildEnvironment -Detailed
$env:CARGO_TARGET_DIR = Join-Path (Get-Location) 'target'
$env:RUSTFLAGS = '-C link-arg=/DEBUG:FULL'
Invoke-CargoWrapper -ArgumentList @('--raw', 'fmt', '--all')
Invoke-CargoWrapper -ArgumentList @('--raw', 'clippy', '--all-targets', '--', '-D', 'warnings')
Invoke-CargoWrapper -ArgumentList @('--raw', 'test', '--all')
Invoke-CargoWrapper -ArgumentList @('--raw', 'build', '--release', '--locked')
pwsh -NoProfile -File scripts/test-windows-fork.ps1
```

Raw mode bypasses wrapper autofix orchestration; each listed verification step
must still succeed. Preserve previous executables and compare SHA-256 after
copying the release artifact to both `~/bin/rtk.exe` and
`~/.local/bin/rtk.exe`. The extensionless `.local/bin/rtk` is a Git Bash launcher
for the latter executable. Run client fidelity tests against the new binary
and retain a machine-local provenance receipt with the source commit and hashes.
