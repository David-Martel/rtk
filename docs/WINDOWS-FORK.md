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
executable identity and record source commit and hashes before installing a
qualified build. Keep mapped images and unique work; remove superseded redundant
executables after replacement acceptance. Do not create backup copies by default.
Validate client fidelity against the actual installed binary separately.

## Security dependency refresh

The stable CLI retains ureq2 while updating rustls to 0.23.46,
rustls-webpki to 0.103.16, the trust-store parent to 1.0.10, crossbeam-epoch
to 0.9.20 and quick-xml to 0.41. The XML migration reconstructs contiguous
text/reference events before testing an MTP boolean or retaining escaped TRX
diagnostic text. Attribute values use the supported XML 1.0 normalization API.
No untrusted XML resolver or network access is enabled.

The security CI step now runs [check-security-audit.ps1](../scripts/check-security-audit.ps1)
and its positive/negative controls. Any vulnerability fails except the precise
webpki-roots 0.26.11 compatibility shim for RUSTSEC-2026-0381, and only after
proving its registry/checksum identity, exact reexport source and resolved registry
parent>=1.0.10. Changed source, an old/foreign/unresolved parent or another
advisory fails. Cargo.lock must retain the same hash through audit and metadata.
This is a conditional source proof, with no global advisory ignore. See the
[RustSec advisory](https://rustsec.org/advisories/RUSTSEC-2026-0381.html).

Recorded source review (2026-10-20): the independent shared-hooks Codex lane
reviewed the XML event migration and isolated reminder-fixture changes; root
reviewed the new audit gate and replayed all 15 controls and actual audit/metadata.
The complete Windows no-default-feature suite passed 4231 tests with 8 existing
skips, including both new XML regressions. Strict Clippy and release qualification
are separate gates and must pass before deploying the successor.

| Selector / reviewed behavior | Source SHA256 |
|---|---|
| `test_mtp_property_entities_preserve_boolean_semantics`: numeric entity true; compound, spaced, unknown and comment-split false controls | `1A2B071FFE880E530F455B93A20AE2FD100143B4BCEAE62CDA4CD2C1D84EC12A` (`dotnet_cmd.rs`) |
| `test_trx_diagnostic_references_preserve_original_text`: escaped diagnostics, decoded attribute references and literal attribute newline | `E76155EF41FF5682EE461DAF616750983BA45BBA3AACA532390325104498D08C` (`dotnet_trx.rs`) |
| `diff_byte_accuracy_test`: exact payload/error assertions retained; private reminder suppression | `021E41484241AA3704485D98FEC83A0439C715DA99837A3B797D3537207DDB2F` |
| `guard_integration_test`: guard/exit assertions retained; private reminder suppression | `97FD66FC02F9E2D496DB9CF6D7E83FD727D6DE86064E8534ACE9BF0D0A76E73E` |
| Audit `-SelfTest` 15 selectors and actual fail-closed gate, independently replayed | `8DD49FE76F32AE1EDC4E4D9A4B6F4E5B085BE5C3BBE37C99D864FFB818C3E49D` |
