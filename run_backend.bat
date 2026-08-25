@echo off
setlocal

rem Dung ky tu ASCII trong tep batch de cmd.exe doc on dinh tren cac code page Windows.
set "VMONITOR_ROOT=%~dp0"
set "VMONITOR_PYTHON=%VMONITOR_ROOT%.venv\Scripts\python.exe"

rem Dung som neu may moi chua tao moi truong Python cua du an.
if not exist "%VMONITOR_PYTHON%" (
    echo [ERROR] Python environment was not found at .venv.
    echo Follow the backend setup commands in README.md, then run this file again.
    exit /b 1
)

rem Chuyen vao backend de Alembic va pydantic-settings tim dung tep cau hinh.
pushd "%VMONITOR_ROOT%backend"
if errorlevel 1 (
    echo [ERROR] The backend directory could not be opened.
    exit /b 1
)
set "PYTHONPATH=%CD%"

rem Cap nhat schema truoc khi mo API de code va database luon cung revision.
"%VMONITOR_PYTHON%" -m alembic upgrade head
if errorlevel 1 (
    echo [ERROR] Database migration failed. The backend was not started.
    popd
    exit /b 1
)

rem app.server doc host, port va reload tu backend/.env.
"%VMONITOR_PYTHON%" -m app.server
set "VMONITOR_EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %VMONITOR_EXIT_CODE%
