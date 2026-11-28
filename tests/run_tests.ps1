#  run_tests.ps1 -- 一条命令跑完所有集成测试。负责人：丙。
#
#  用法（任意目录都行）：
#      powershell -ExecutionPolicy Bypass -File tests\run_tests.ps1
#
#  如果 swipl 不在 PATH 上，先设环境变量：
#      $env:SWIPL = 'F:\new-desk\KnowlegeRepresent\tools\swipl\bin\swipl.exe'
#
#  退出码 0 表示全部通过，非 0 表示有失败（可以直接挂到 CI 里）。

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$swipl = if ($env:SWIPL) { $env:SWIPL } else { 'swipl' }

if (-not (Get-Command $swipl -ErrorAction SilentlyContinue)) {
    Write-Host "swipl not found: install SWI-Prolog or set `$env:SWIPL" -ForegroundColor Red
    exit 2
}

$suites = @('t_bridge', 't_runner', 't_execution', 't_domain')
$failed = @()

foreach ($s in $suites) {
    $file = Join-Path $root "tests\integration\$s.pl"
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host " $s" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    & $swipl -q -g "main, halt" $file
    if ($LASTEXITCODE -ne 0) { $failed += $s }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "ALL PASS ($($suites.Count) suites)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
