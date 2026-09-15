@echo off
chcp 65001 >nul
call "%~dp0启动游戏.cmd" -- --low-quality
exit /b %errorlevel%
