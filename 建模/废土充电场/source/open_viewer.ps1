$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
$taskUrl = 'http://127.0.0.1:8766/viewer/'
try {
    $taskResponse = Invoke-WebRequest -Uri $taskUrl -UseBasicParsing -TimeoutSec 2
    if ($taskResponse.Content -match '废土充电场') { Start-Process $taskUrl; exit 0 }
} catch { }
$taskPython = (Get-Command python -ErrorAction Stop).Source
$taskScript = Join-Path $PSScriptRoot 'serve_viewer.py'
Start-Process -FilePath $taskPython -ArgumentList @(('"' + $taskScript + '"'),'--no-browser') -WindowStyle Hidden
for ($taskAttempt=0; $taskAttempt -lt 20; $taskAttempt++) {
    try {
        $taskResponse = Invoke-WebRequest -Uri $taskUrl -UseBasicParsing -TimeoutSec 1
        if ($taskResponse.Content -match '废土充电场') { Start-Process $taskUrl; exit 0 }
    } catch { Start-Sleep -Milliseconds 250 }
}
throw '查看器未能启动。请运行 source/serve_viewer.py 查看原因。'
