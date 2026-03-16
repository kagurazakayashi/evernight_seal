@ECHO OFF
SETLOCAL
REM Build for Web platform (built-in resource mode)
REM Prerequisite: run build_assets.bat first
REM Usage: run from project root as script\build_web.bat

SET "PROJECT_DIR=%~dp0.."
PUSHD "%PROJECT_DIR%\flutter-build-all"

ECHO Building Web...
CALL dart run flutter_build_all:build_all --config "%PROJECT_DIR%\build.ini" --target "web"
IF ERRORLEVEL 1 GOTO :error

POPD
ECHO Web built.
EXIT /B 0

:error
POPD
ECHO Error: Web build failed.
EXIT /B 1
