@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not defined GODOT_BIN set "GODOT_BIN=godot"
"%GODOT_BIN%" --headless --editor --path "%~dp0." --import
if errorlevel 1 (
  echo 请安装 Godot 4.7.2，并加入 PATH 或设置 GODOT_BIN。
  pause
  exit /b 1
)
start "" "%GODOT_BIN%" --path "%~dp0." %*
