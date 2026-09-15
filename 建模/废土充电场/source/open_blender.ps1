$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $PSScriptRoot
$taskBlender = if ($env:BLENDER_BIN) { $env:BLENDER_BIN } else { (Get-Command blender -ErrorAction Stop).Source }
$taskBlend = Join-Path $taskProject '废土充电场.blend'
& $taskBlender $taskBlend
