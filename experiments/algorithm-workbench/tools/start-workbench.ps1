[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MilitaryRepo,
    [Parameter(Mandatory=$true)][string]$EconomyRepo,
    [string]$GodotExe = 'godot',
    [string]$PythonExe = 'python',
    [string]$AdapterPath = '',
    [int]$Port = 8787,
    [switch]$CheckOnly,
    [switch]$SkipInstall
)
$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
$launchArgs = @("$PSScriptRoot/start_workbench.py", '--military-repo', $MilitaryRepo, '--economy-repo', $EconomyRepo, '--godot', $GodotExe, '--port', "$Port")
if ($AdapterPath) { $launchArgs += @('--adapter', $AdapterPath) }
if ($CheckOnly) { $launchArgs += '--check-only' }
if ($SkipInstall) { $launchArgs += '--skip-install' }
& $PythonExe @launchArgs
exit $LASTEXITCODE
