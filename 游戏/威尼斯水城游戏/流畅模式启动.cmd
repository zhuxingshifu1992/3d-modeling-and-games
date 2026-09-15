@echo off
chcp 65001 >nul
call "%~dp0开始游戏.cmd" --rendering-method gl_compatibility -- --low
exit /b %errorlevel%
