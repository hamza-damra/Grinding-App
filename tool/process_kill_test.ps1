<#
.SYNOPSIS
  Real Android process-kill test for the START / COMPLETE idempotency
  invariant (clientRequestId persisted BEFORE the first request).

.DESCRIPTION
  For each mode (before_commit, after_commit):
    1. Phase 1 (its own app process): fresh state -> PIN -> READY order ->
       START -> confirm. The in-process fake network SIGKILLs the app when
       the request reaches the "server" (before_commit) or right after the
       server committed it (after_commit).
    2. The host checks the process is gone and reads the pending record
       straight from the app sandbox with `adb shell run-as` -- independent
       evidence of what was durably on disk when the process died.
    3. Phase 2 (a NEW app process, EXPECTED_ID = the id read by the host):
       the app must recover exactly that id, never call the id generator,
       send nothing before an explicit confirmation, resend the SAME id
       (after_commit -> replayed:true, no second transition) and clear the
       record.
  Logs go to tool/out/ (gitignored). No credentials are involved: the
  backend is the in-process fake.

.EXAMPLE
  pwsh tool/process_kill_test.ps1 -Device emulator-5554
#>
param(
  [string]$Device = 'emulator-5554',
  [ValidateSet('before_commit', 'after_commit')]
  [string[]]$Modes = @('before_commit', 'after_commit'),
  [int]$PhaseTimeoutSeconds = 600,
  # flutter executable (defaults to the one on PATH).
  [string]$Flutter = $($cmd = Get-Command flutter -ErrorAction SilentlyContinue; if ($cmd) { $cmd.Source } else { 'flutter' })
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$package = 'com.example.flutter_grinding_app'
$recordPath = 'files/grinding_pending_commands/pending_1042_start.json'
$outDir = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Invoke-Phase([string[]]$DartDefines, [string]$LogFile) {
  $arguments = @(
    'test', 'integration_test/process_kill_test.dart',
    '-d', $Device,
    # Keep the app (and its data) installed between the two processes.
    '--no-uninstall'
  ) + ($DartDefines | ForEach-Object { "--dart-define=$_" })
  $process = Start-Process -FilePath $Flutter -ArgumentList $arguments `
    -WorkingDirectory $root -NoNewWindow -PassThru `
    -RedirectStandardOutput $LogFile -RedirectStandardError "$LogFile.err"
  if (-not $process.WaitForExit($PhaseTimeoutSeconds * 1000)) {
    $process.Kill($true)
    Write-Host "  (flutter test did not exit within ${PhaseTimeoutSeconds}s; stopped)"
    return -1
  }
  return $process.ExitCode
}

function Get-AppPid {
  $appPid = (& adb -s $Device shell pidof $package 2>$null) -join ''
  return $appPid.Trim()
}

$results = @()
foreach ($mode in $Modes) {
  Write-Host "=== $mode / phase 1: persist, then SIGKILL around the request ==="
  $log1 = Join-Path $outDir "kill_${mode}_phase1.log"
  $exit1 = Invoke-Phase @('KILL_PHASE=1', "KILL_MODE=$mode") $log1
  Write-Host "  flutter test exit code: $exit1 (non-zero expected: the app died)"
  Start-Sleep -Seconds 2

  $alive = Get-AppPid
  if ($alive) { throw "[$mode] the app process is still alive (pid $alive)" }
  Write-Host '  app process: gone'

  $json = (& adb -s $Device shell run-as $package cat $recordPath) -join ''
  if (-not $json -or $json -notmatch 'clientRequestId') {
    throw "[$mode] no pending record on disk after the kill (read: '$json')"
  }
  $record = $json | ConvertFrom-Json
  $id = $record.clientRequestId
  if ($id -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') {
    throw "[$mode] persisted id is not a UUID v4: $id"
  }
  $tmpLeft = (& adb -s $Device shell run-as $package ls files/grinding_pending_commands) -join ' '
  Write-Host "  on disk (run-as): $recordPath -> clientRequestId=$id"
  Write-Host "  directory listing: $tmpLeft"
  $sentLine = Select-String -Path $log1 -Pattern 'KILL_TEST_ON_DISK_AT_SEND=\S*' |
    Select-Object -First 1
  if ($sentLine) { Write-Host "  app log: $($sentLine.Matches[0].Value)" }

  Write-Host "=== $mode / phase 2: relaunch, recover, explicit resend ==="
  $log2 = Join-Path $outDir "kill_${mode}_phase2.log"
  $exit2 = Invoke-Phase @('KILL_PHASE=2', "KILL_MODE=$mode", "EXPECTED_ID=$id") $log2
  if ($exit2 -ne 0) { throw "[$mode] phase 2 failed (exit $exit2); see $log2" }
  $pass = Select-String -Path $log2 -Pattern "KILL_TEST_RESULT=PASS mode=$mode id=$id minted=0" -Quiet
  if (-not $pass) { throw "[$mode] phase 2 did not report PASS; see $log2" }

  $after = (& adb -s $Device shell run-as $package ls files/grinding_pending_commands 2>&1) -join ' '
  if ($after -match 'pending_1042_start') {
    throw "[$mode] the record was not cleared after the confirmed resend"
  }
  Write-Host "  PASS: same id recovered and resent, no id minted, record cleared"
  $results += [pscustomobject]@{ Mode = $mode; ClientRequestId = $id; Result = 'PASS' }
}

& adb -s $Device uninstall $package | Out-Null
Write-Host ''
Write-Host '=== Summary ==='
$results | Format-Table -AutoSize
