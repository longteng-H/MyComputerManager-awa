@echo off
REM ---------------------------------------------------------------
REM  MyComputerManager single-file packaging launcher.
REM  Pure ASCII on purpose: cmd.exe codepage would garble CJK text.
REM  All paths are derived from %~dp0 (this file's own folder),
REM  so the project may live in a path containing non-ASCII chars.
REM ---------------------------------------------------------------
setlocal

set "PS1=%~dp0build.ps1"

if not exist "%PS1%" (
    echo [ERROR] build.ps1 not found next to this launcher:
    echo         %PS1%
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Build finished: ALL CHECKS PASSED.
) else (
    echo Build finished with errors. Exit code = %RC%
)

pause
exit /b %RC%
