@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
if not defined GODOT_BIN set "GODOT_BIN=godot"
if not exist "%GODOT_BIN%" (
  where "%GODOT_BIN%" >nul 2>nul
  if errorlevel 1 (
    echo 请先安装 Godot 4.7.2，并将 godot 加入 PATH，或设置 GODOT_BIN 为程序路径。
    pause
    exit /b 1
  )
)
"%GODOT_BIN%" --headless --editor --path "%~dp0." --import
if errorlevel 1 exit /b 1
"%GODOT_BIN%" --path "%~dp0." %*
exit /b %errorlevel%
