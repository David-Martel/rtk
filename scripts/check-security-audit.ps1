#requires -Version 7.0
param([switch] $SelfTest)

# Protects: TLS distrust fixes and every other cargo-audit vulnerability gate.
# Detects: stale roots, changed shim code, unresolved/foreign parents and new CVEs.
# Needs: cargo-audit, locked Cargo metadata and downloaded registry sources;
# -SelfTest instead uses private, inert stdlib-only fixtures.
# Breadcrumbs: Cargo.lock; .github/workflows/ci.yml Security Scan;
# https://rustsec.org/advisories/RUSTSEC-2026-0381.html
# https://github.com/rustls/webpki-roots/blob/v/0.26.11/webpki-roots/src/lib.rs
# The 0.26.11 source contains only a reexport of parent::TLS_SERVER_ROOTS.
# This exception is conditional source/dependency proof, never an advisory ignore.
# Review binding: root records this script's final SHA256 and exact selectors in
# docs/WINDOWS-FORK.md after independent review. No completed review is implied here.
$ErrorActionPreference = 'Stop'
$ShimSourceSHA256 = '405994D07740114787A7354A19005294DF92CAFC592FBCCD1B459149C6661636'
$Registry = 'registry+https://github.com/rust-lang/crates.io-index'

function Assert-SecurityAudit {
    param([hashtable] $Audit, [hashtable] $Metadata, [int] $AuditExit)
    $v = $Audit.vulnerabilities
    if ($v -isnot [hashtable] -or $v.list -isnot [array] -or
        $v.found -isnot [bool] -or $v.count -isnot [long] -and $v.count -isnot [int] -or
        $v.count -ne $v.list.Count -or $v.found -ne ($v.list.Count -gt 0)) {
        throw 'Malformed or inconsistent cargo-audit vulnerability result'
    }
    if (($v.count -eq 0 -and $AuditExit -ne 0) -or
        ($v.count -gt 0 -and $AuditExit -ne 1)) {
        throw "cargo-audit operational exit was not a valid audit result: $AuditExit"
    }
    foreach ($finding in $v.list) {
        if ($finding.advisory.id -cne 'RUSTSEC-2026-0381' -or
            $finding.advisory.package -cne 'webpki-roots' -or
            $finding.package.name -cne 'webpki-roots' -or
            $finding.package.version -cne '0.26.11' -or
            $finding.package.source -cne $Registry -or
            $finding.package.checksum -cne '521bc38abb08001b01866da9f51eb7c5d647a19260e00054a8c7fd5f9e57f7a9') {
            throw "Unadmitted vulnerability: $($finding.advisory.id) $($finding.package.name) $($finding.package.version)"
        }
        if ($Metadata.version -ne 1 -or $Metadata.packages -isnot [array] -or
            $Metadata.resolve.nodes -isnot [array]) { throw 'Missing resolved Cargo metadata' }
        $shim = @($Metadata.packages | Where-Object {
            $_.name -ceq 'webpki-roots' -and $_.version -ceq '0.26.11' -and $_.source -ceq $Registry
        })
        if ($shim.Count -ne 1) { throw 'Expected exactly one canonical registry shim' }
        $node = @($Metadata.resolve.nodes | Where-Object { $_.id -ceq $shim[0].id })
        if ($node.Count -ne 1 -or $node[0].deps -isnot [array] -or
            $node[0].deps.Count -ne 1 -or $node[0].deps[0].name -cne 'parent') {
            throw 'Shim must resolve exactly its canonical parent alias'
        }
        $parent = @($Metadata.packages | Where-Object { $_.id -ceq $node[0].deps[0].pkg })
        if ($parent.Count -ne 1 -or $parent[0].name -cne 'webpki-roots' -or
            $parent[0].source -cne $Registry -or $parent[0].version -cnotmatch '^1\.[0-9]+\.[0-9]+$' -or
            ([version] $parent[0].version) -lt [version] '1.0.10') {
            throw 'Shim parent is not the patched canonical webpki-roots >=1.0.10'
        }
        $lib = Join-Path ([IO.Path]::GetDirectoryName($shim[0].manifest_path)) 'src/lib.rs'
        $file = Get-Item -LiteralPath $lib -Force
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (Get-FileHash -LiteralPath $lib -Algorithm SHA256).Hash -cne $ShimSourceSHA256) {
            throw 'Shim source differs from the exact reviewed reexport'
        }
    }
    [ordered]@{
        status = 'PASS'; vulnerabilities = $v.count
        conditionalShimExceptions = $v.count
        proof = if ($v.count) { 'exact 0.26.11 reexport source and resolved patched registry parent' } else { 'no known vulnerabilities' }
    }
}

function Invoke-CargoJson {
    param([string] $Cargo, [string[]] $Arguments, [string] $Root)
    $info = [Diagnostics.ProcessStartInfo]::new($Cargo)
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.WorkingDirectory = $Root
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::new(); $child.StartInfo = $info
    try {
        [void] $child.Start()
        $stdout = $child.StandardOutput.ReadToEndAsync(); $stderr = $child.StandardError.ReadToEndAsync()
        # Infrastructure-only bound: fail closed on stalled registry/database access;
        # it never changes production hook budgets or converts an error to success.
        if (-not $child.WaitForExit(180000)) { $child.Kill($true); throw 'Owned cargo audit/metadata child exceeded three minutes' }
        $text = $stdout.GetAwaiter().GetResult()
        [void] $stderr.GetAwaiter().GetResult()
        # Parse the complete stdout: truncated, mixed or trailing output must fail.
        @{ exit = $child.ExitCode; json = ($text | ConvertFrom-Json -AsHashtable) }
    } finally { $child.Dispose() }
}

if ($SelfTest) {
    # Selector group: exact positive admission plus changed source, old/foreign/
    # unresolved parent, another advisory/version and malformed/operational output
    # controls. Protects the exception boundary using the SAME validator and an
    # actual private source file; detects a gate which always succeeds.
    $root = Join-Path ([IO.Path]::GetTempPath()) ('rtk-audit-fixture-' + [guid]::NewGuid().ToString('N'))
    $src = Join-Path $root 'src'; [void] [IO.Directory]::CreateDirectory($src)
    $lib = Join-Path $src 'lib.rs'
    $canonical = @'
//! A compiled-in copy of the root certificates trusted by Mozilla.
//!
//! To use this library with rustls 0.22:
//!
//! ```rust
//! let root_store = rustls::RootCertStore {
//!   roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
//! };
//! ```
//!
//! This library is suitable for use in applications that can always be recompiled and instantly deployed.
//! For applications that are deployed to end-users and cannot be recompiled, or which need certification
//! before deployment, consider a library that uses the platform native certificate verifier such as
//! [rustls-platform-verifier]. This has the additional benefit of supporting OS provided CA constraints
//! and revocation data.
//!
//! This crate version is a semver trick to webpki-roots v1.  Users of it should
//! migrate their dependency to webpki-roots v1 at their leisure.
//!
//! [rustls-platform-verifier]: https://docs.rs/rustls-platform-verifier

#![no_std]
#![forbid(unsafe_code, unstable_features)]
#![deny(
    elided_lifetimes_in_paths,
    trivial_casts,
    trivial_numeric_casts,
    unused_import_braces,
    unused_extern_crates,
    unused_qualifications
)]

pub use parent::TLS_SERVER_ROOTS;
'@
    $canonical = $canonical.Replace("`r`n", "`n") + "`n"
    function New-Fixture {
        $finding = @{
            advisory = @{ id = 'RUSTSEC-2026-0381'; package = 'webpki-roots' }
            package = @{ name = 'webpki-roots'; version = '0.26.11'; source = $Registry
                checksum = '521bc38abb08001b01866da9f51eb7c5d647a19260e00054a8c7fd5f9e57f7a9' }
        }
        @{
            audit = @{ vulnerabilities = @{ found = $true; count = 1; list = @($finding) } }
            metadata = @{ version = 1; packages = @(
                @{ id = 'shim'; name = 'webpki-roots'; version = '0.26.11'; source = $Registry; manifest_path = (Join-Path $root 'Cargo.toml') },
                @{ id = 'parent'; name = 'webpki-roots'; version = '1.0.10'; source = $Registry }
            ); resolve = @{ nodes = @(@{ id = 'shim'; deps = @(@{ name = 'parent'; pkg = 'parent' }) }) } }
            exit = 1
        }
    }
    $cases = @(
        @{ name = 'exact-source-patched-parent'; pass = $true; mutate = {} },
        @{ name = 'newer-patched-parent'; pass = $true; mutate = { param($f) $f.metadata.packages[1].version = '1.0.11' } },
        @{ name = 'old-parent'; pass = $false; mutate = { param($f) $f.metadata.packages[1].version = '1.0.6' } },
        @{ name = 'foreign-parent'; pass = $false; mutate = { param($f) $f.metadata.packages[1].source = 'git+https://example.invalid/roots' } },
        @{ name = 'unresolved-parent'; pass = $false; mutate = { param($f) $f.metadata.resolve.nodes[0].deps[0].pkg = 'absent' } },
        @{ name = 'wrong-parent-alias'; pass = $false; mutate = { param($f) $f.metadata.resolve.nodes[0].deps[0].name = 'other' } },
        @{ name = 'changed-source'; pass = $false; mutate = { param($f) [IO.File]::AppendAllText($lib, '// changed') } },
        @{ name = 'different-advisory'; pass = $false; mutate = { param($f) $f.audit.vulnerabilities.list[0].advisory.id = 'RUSTSEC-2026-0382' } },
        @{ name = 'different-shim-version'; pass = $false; mutate = { param($f) $f.audit.vulnerabilities.list[0].package.version = '0.26.10' } },
        @{ name = 'mismatched-count'; pass = $false; mutate = { param($f) $f.audit.vulnerabilities.count = 0 } },
        @{ name = 'operational-failure'; pass = $false; mutate = { param($f) $f.exit = 2 } },
        @{ name = 'no-vulnerabilities'; pass = $true; mutate = { param($f) $f.audit.vulnerabilities = @{ found = $false; count = 0; list = @() }; $f.exit = 0 } }
    )
    try {
        foreach ($case in $cases) {
            [IO.File]::WriteAllText($lib, $canonical, [Text.UTF8Encoding]::new($false))
            $fixture = New-Fixture; & $case.mutate $fixture
            $accepted = $false
            try { $null = Assert-SecurityAudit $fixture.audit $fixture.metadata $fixture.exit; $accepted = $true } catch {}
            if ($accepted -ne $case.pass) { throw "Audit self-test failed: $($case.name) expected admission=$($case.pass), got=$accepted" }
            Write-Host "[ok] $($case.name)"
        }
        Write-Host "Passed $($cases.Count) fail-closed audit gate selectors"
    } finally {
        # Only the exact owned inert leaf and empty directories are removed.
        [IO.File]::Delete($lib); [IO.Directory]::Delete($src, $false); [IO.Directory]::Delete($root, $false)
    }
    exit 0
}

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cargo = (Get-Command cargo -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$lock = Join-Path $repo 'Cargo.lock'
$lockHash = (Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash
$audit = Invoke-CargoJson $cargo @('audit', '--json', '--file', $lock) $repo
if ((Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash -cne $lockHash) { throw 'Cargo.lock changed during audit' }
$metadata = Invoke-CargoJson $cargo @('metadata', '--locked', '--format-version', '1', '--all-features') $repo
if ((Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash -cne $lockHash) { throw 'Cargo.lock changed between audit and dependency proof' }
if ($metadata.exit -ne 0) { throw "Cargo metadata failed: exit $($metadata.exit)" }
Assert-SecurityAudit $audit.json $metadata.json $audit.exit | ConvertTo-Json -Depth 4
exit 0

