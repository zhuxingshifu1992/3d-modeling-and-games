@echo off
chcp 65001 >nul
setlocal
if not defined BLENDER_BIN set "BLENDER_BIN=blender"
"%BLENDER_BIN%" "%~dp0废土充电场.blend"
