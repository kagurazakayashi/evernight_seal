@ECHO OFF
SETLOCAL
REM Build for Android platform
REM Prerequisite: run build_assets.bat first
REM Usage: run from project root as script\build_android.bat

SET "PROJECT_DIR=%~dp0.."
PUSHD "%PROJECT_DIR%\flutter-build-all"

ECHO Building Android...
CALL dart run flutter_build_all:build_all --config "%PROJECT_DIR%\build.ini" --target "android"
IF ERRORLEVEL 1 GOTO :error

POPD
ECHO Android built.
EXIT /B 0

:error
POPD
ECHO Error: Android build failed.
EXIT /B 1
