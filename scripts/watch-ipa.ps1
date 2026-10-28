# Shows a progress bar for the latest iOS CI build and, when it succeeds,
# replaces build/ipa with a single Meldo-latest.ipa for Sideloadly.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/watch-ipa.ps1 [runId]
param([string]$RunId)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$ipaDir = Join-Path $root "build\ipa"
# gh finds the repository from the current folder, so work from the project root.
Set-Location $root

# Only builds of pushed or manually started commits: a pull request (also from a fork)
# runs its own ios.yml and could upload any IPA under the same artifact name.
if (-not $RunId) {
    $RunId = gh run list --workflow ios.yml --event push --limit 1 --json databaseId -q ".[0].databaseId"
}
$runEvent = gh run view $RunId --json event -q ".event"
if ($runEvent -notin @("push", "workflow_dispatch")) {
    Write-Host "Run $RunId kommt von '$runEvent', nicht von einem Push. Keine IPA aus Pull Requests." -ForegroundColor Red
    exit 1
}

# Typical seconds per step on macos-26, used to estimate progress inside a step.
$expected = @{
    "Build Rust core XCFramework and Swift bindings" = 240
    "Install XcodeGen and xcbeautify"                = 40
    "Test MeldeCore package (Rust through UniFFI)"   = 150
    "Build and test app"                             = 480
    "Build unsigned device IPA"                      = 240
    "Upload unsigned IPA"                            = 10
}
$total = ($expected.Values | Measure-Object -Sum).Sum

while ($true) {
    $run = gh run view $RunId --json status,conclusion,headSha,jobs | ConvertFrom-Json
    $steps = $run.jobs[0].steps
    $done = 0
    $current = "Warten auf einen Mac"
    foreach ($s in $steps) {
        if (-not $expected.ContainsKey($s.name)) { continue }
        $weight = $expected[$s.name]
        if ($s.status -eq "completed") {
            $done += $weight
        } elseif ($s.status -eq "in_progress") {
            # [datetime] turns GitHub's UTC timestamp into local time.
            $start = [datetime]$s.startedAt
            if ($start.Kind -eq "Utc") { $start = $start.ToLocalTime() }
            $elapsed = [math]::Max(0, ((Get-Date) - $start).TotalSeconds)
            $done += [math]::Min($elapsed, $weight * 0.95)
            $current = $s.name
        }
    }
    $percent = [int][math]::Max(0, [math]::Min(99, 100 * $done / $total))
    $left = [int][math]::Max(1, ($total - $done) / 60)
    if ($run.status -eq "completed") { break }
    Write-Progress -Activity "Meldo IPA ($($run.headSha.Substring(0,7)))" -Status "$percent% - $current - noch ca. $left min" -PercentComplete $percent
    Start-Sleep -Seconds 15
}
Write-Progress -Activity "Meldo IPA" -Completed

if ($run.conclusion -ne "success") {
    Write-Host "Build fehlgeschlagen ($($run.conclusion)). Alte IPA bleibt." -ForegroundColor Red
    exit 1
}

$tmp = Join-Path $env:TEMP "meldo-ipa-$RunId"
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
gh run download $RunId -n MeldePlanner-unsigned-ipa -D $tmp
$new = Get-ChildItem $tmp -Filter *.ipa | Select-Object -First 1
New-Item -ItemType Directory -Force $ipaDir | Out-Null
Get-ChildItem $ipaDir -Filter *.ipa | Remove-Item -Force
Move-Item $new.FullName (Join-Path $ipaDir "Meldo-latest.ipa")
Remove-Item -Recurse -Force $tmp
Write-Host "Fertig: $ipaDir\Meldo-latest.ipa (Commit $($run.headSha.Substring(0,7)))" -ForegroundColor Green
