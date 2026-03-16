@ECHO OFF
SETLOCAL
REM Build for Windows platform
REM Prerequisite: run build_assets.bat first
REM Usage: run from project root as script\build_windows.bat

SET "PROJECT_DIR=%~dp0.."
PUSHD "%PROJECT_DIR%\flutter-build-all"

ECHO Building Windows...
CALL dart run flutter_build_all:build_all --config "%PROJECT_DIR%\build.ini" --target "windows"
IF ERRORLEVEL 1 GOTO :error

POPD
ECHO Windows built.
EXIT /B 0

:error
POPD
ECHO Error: Windows build failed.
EXIT /B 1
