# Drives the Dart analysis server directly (same server `flutter analyze` uses)
# because the sandbox denies nested process spawns with piped stdio.
param([string]$ProjectDir = (Get-Location).Path)
$ErrorActionPreference = 'Stop'
$sdk = 'C:\KuromiLab\flutter\flutter\bin\cache\dart-sdk'
$rt = Join-Path $sdk 'bin\dartaotruntime.exe'
$sn = Join-Path $sdk 'bin\snapshots\analysis_server_aot.dart.snapshot'

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $rt
$psi.Arguments = "`"$sn`" --client-id=dsh-analyze --disable-server-feature-completion --disable-server-feature-search --sdk `"$sdk`""
$psi.WorkingDirectory = $ProjectDir
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = [System.Diagnostics.Process]::Start($psi)

function Send([string]$id, [string]$method, $params) {
  $msg = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 5
  $p.StandardInput.WriteLine($msg)
}

Send '0' 'server.setSubscriptions' @('STATUS')
Send '1' 'server.getVersion' @{}
Send '2' 'analysis.setAnalysisRoots' @{ included = @($ProjectDir); excluded = @() }

$done = $false
$started = $false
$errCount = 0
$warnCount = 0
$infoCount = 0
$lines = [System.Collections.Generic.List[string]]::new()
while (-not $done) {
  if ($p.HasExited) { Write-Output "SERVER EXITED: $($p.ExitCode)"; break }
  $line = $p.StandardOutput.ReadLine()
  if ($null -eq $line) { break }
  if ($line.Length -lt 2) { continue }
  try { $m = $line | ConvertFrom-Json } catch { Write-Output "RAW: $line"; continue }
  if ($m.event -eq 'server.status') {
    if ($null -ne $m.params.analysis -and $m.params.analysis) { $started = $true }
    elseif ($null -eq $m.params.analysis -and $started) { $done = $true }
  } elseif ($m.event -eq 'analysis.errors') {
    foreach ($e in $m.params.errors) {
      $rel = $e.location.file
      if ($rel -and $rel.StartsWith($ProjectDir)) { $rel = $rel.Substring($ProjectDir.Length + 1) }
      $lines.Add(("[$($e.severity)] ${rel}:$($e.location.startLine): $($e.message)"))
      if ($e.severity -eq 'ERROR') { $errCount++ }
      elseif ($e.severity -eq 'WARNING') { $warnCount++ }
      else { $infoCount++ }
    }
  }
}
if (-not $p.HasExited) { try { $p.Kill() } catch {} }
foreach ($l in $lines) { Write-Output $l }
Write-Output ("RESULT: errors=$errCount warnings=$warnCount infos=$infoCount")
