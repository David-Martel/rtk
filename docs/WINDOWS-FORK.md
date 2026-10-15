# David-Martel Windows fork

## Stable upstream reconciliation

The `sync/upstream-stable` branch merges upstream `rtk-ai/rtk` stable
`v1.0.1` (`4ef8730`) into fork `develop` (`e080c06`). Both histories are
preserved. This is the stable release line; upstream prerelease `develop` is
not the deployment source. Validation below targets the Apache-2.0 CLI with
`-p rtk --no-default-features`; the optional engine and separate proxy are
outside this reconciliation's runtime acceptance.

## Retained fork contracts

- Explicit Git log formats and unrestricted selectors preserve native output.
  Upstream raw patch/stat paths retain their default ten-commit cap and visible
  cap notice, including their existing regression tests. Explicit native format
  and history behavior is compared byte-for-byte against Git in a repository
  with more than fifty commits.
- `RTK_CONFIG_DIR` selects the directory containing `config.toml`, including on
  Windows where XDG variables do not redirect known folders. Empty overrides
  fall back to the platform default. Access goes through upstream `user_dirs`
  and `user_env`, retaining upstream test isolation.
- Hook audit writing and `rtk hook audit` share `RTK_AUDIT_DIR` and home fallback
  resolution. Private directory/file creation remains upstream's implementation.
- Composite Claude hooks may identify themselves with the exact
  `RTK_HOOK_COMPOSITE=1` environment marker; unmarked wrappers remain unknown.
- On Windows, grep uses `-n -H -Z` parse aids and avoids injecting GNU-only
  buffering options. Single-pattern grep places `--` before the pattern.
  Multiple-pattern grep is passed through unchanged; ripgrep retains upstream
  `-e` handling. Other platforms retain upstream GNU grep behavior.

## Superseded fork implementations

Upstream now supplies successful stdout-only stderr forwarding, native grep
`-l`/`-m` handling, exact Git diff handling and hermetic user-location/environment
accessors. Their current architecture and regression tests replace the old fork
implementations. In particular, the fork's old `cfg(test)` decision shortcut is
removed: unit tests exercise the production decision path with isolated inputs.
The old fork-added Windows stream-test exclusions are removed too. The retained
Unix stderr regression still requires Unix shell permissions and now uses the
shared isolated subprocess helper. The native Windows smoke covers successful
stderr forwarding through an actual `.cmd` fixture on Windows.

The upstream Cargo stack-size setting uses the equivalent table form so Cargo
can merge it with this workstation's existing table-valued environment settings.

## Client integration

Maintained client wrappers live in `dtm-codex/hooks/bin/pre-tool-use-chain.ps1`
and `dtm-claude/scripts/pre-tool-use-chain.ps1`. They evaluate policy first and
accept only an exact RTK prefix for a narrow set of plain build/test commands.
Quoting, Windows paths, shell syntax, search and exact evidence output stay raw.
Updating the binary does not require `rtk init`; running that installer over
composite wrappers can replace deployment-specific integration.

## Validation and deployment

Use PowerShell 7 and CargoTools with a repository-local target directory. Pass
an explicit argument array to preserve Cargo's argument separator.

```powershell
Import-Module CargoTools -Force
Test-BuildEnvironment -Detailed
$env:CARGO_TARGET_DIR = Join-Path (Get-Location) 'target'
# Upstream stream/search tests execute native sh/grep from Git for Windows.
$env:PATH = 'C:\Program Files\Git\usr\bin;' + $env:PATH
Invoke-CargoWrapper -ArgumentList @('--raw', 'fmt', '--all')
Invoke-CargoWrapper -ArgumentList @('--raw', 'check', '-p', 'rtk', '--no-default-features', '--locked')
Invoke-CargoWrapper -ArgumentList @('--raw', 'clippy', '-p', 'rtk', '--no-default-features', '--all-targets', '--', '-D', 'warnings')
Invoke-CargoWrapper -ArgumentList @('--raw', 'test', '-p', 'rtk', '--no-default-features', '--locked')
pwsh -NoProfile -File scripts/test-windows-fork.ps1 -RtkPath target/debug/rtk.exe
```

A source sync or successful check is not deployment acceptance. Preserve prior
executables and record source commit and hashes before installing a qualified
build. Validate client fidelity against the actual installed binary separately.
