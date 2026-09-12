param([string]$RtkPath = (Join-Path $PSScriptRoot '../target/release/rtk.exe'))

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This smoke test requires Windows.' }
$RtkPath = (Resolve-Path -LiteralPath $RtkPath).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('rtk-windows-fork-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null

function Invoke-FixtureCommand {
    param([string[]]$Arguments, [int]$TimeoutMilliseconds = 30000)
    $start = [Diagnostics.ProcessStartInfo]::new($RtkPath)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $fixture
    $start.Environment['PATH'] = $fixture + [IO.Path]::PathSeparator + $env:PATH
    $start.Environment['RTK_CONFIG_DIR'] = Join-Path $fixture 'config'
    $start.Environment['RTK_DB_PATH'] = Join-Path $fixture 'tracking.db'
    $start.Environment['RTK_AUDIT_DIR'] = Join-Path $fixture 'audit'
    $start.Environment['RTK_TEE_DIR'] = Join-Path $fixture 'tee'
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $remaining = [Math]::Max(0, $TimeoutMilliseconds - [int]$deadline.ElapsedMilliseconds)
        if (-not $process.WaitForExit($remaining)) {
            $process.Kill($true)
            [void]$process.WaitForExit(1000)
            throw "RTK fixture command timed out: $($Arguments -join ' ')"
        }
        $remaining = [Math]::Max(0, $TimeoutMilliseconds - [int]$deadline.ElapsedMilliseconds)
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), $remaining)) {
            throw "RTK fixture output drain timed out: $($Arguments -join ' ')"
        }
        [pscustomobject]@{ Code = $process.ExitCode; Stdout = $stdout.GetAwaiter().GetResult(); Stderr = $stderr.GetAwaiter().GetResult() }
    } finally {
        $process.Dispose()
    }
}

try {
    [IO.File]::WriteAllText((Join-Path $fixture 'pytest.cmd'), "@echo off`r`necho 3 passed in 0.10s`r`necho RTK_WINDOWS_STDERR_MARKER 1>&2`r`nexit /b 0`r`n")
    $result = Invoke-FixtureCommand -Arguments @('pytest', 'fixture')
    if ($result.Code -ne 0 -or $result.Stderr.Trim() -cne 'RTK_WINDOWS_STDERR_MARKER' -or $result.Stdout -notmatch '3.*passed') {
        throw "Successful stderr preservation failed: $($result | ConvertTo-Json -Compress)"
    }
    Write-Output '[ok] successful stdout-only filter preserves native Windows stderr'

    [IO.File]::WriteAllText((Join-Path $fixture '-file.txt'), "alpha -needle beta`n")
    $result = Invoke-FixtureCommand -Arguments @('rg', '--', '-needle', '-file.txt')
    if ($result.Code -ne 0 -or $result.Stdout -notmatch 'alpha -needle beta') {
        throw "Dash-pattern/path search failed: $($result | ConvertTo-Json -Compress)"
    }
    Write-Output '[ok] ripgrep treats dash-leading pattern and path as operands'

    $result = Invoke-FixtureCommand -Arguments @('rg', '--', 'missing-pattern', '-file.txt')
    if ($result.Code -ne 1) { throw "No-match search must exit 1, got $($result.Code)" }
    Write-Output '[ok] no-match search preserves exit code 1'

    $result = Invoke-FixtureCommand -Arguments @('rg', 'missing-pattern', '-file.txt')
    if ($result.Code -ne 2) { throw "Invalid native option must exit 2, got $($result.Code)" }
    Write-Output '[ok] invalid native option preserves exit code 2'
} finally {
    # Keep the bounded fixture as evidence; no wildcard or cross-shell cleanup.
    Write-Output "Fixture retained: $fixture"
}
