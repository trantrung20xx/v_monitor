@echo off
echo Dang khoi dong Backend v_monitor...
cd /d "%~dp0backend"
set PYTHONPATH=%cd%
if "%API_HOST%"=="" set API_HOST=0.0.0.0
if "%API_PORT%"=="" set API_PORT=8000

rem Cap nhat schema truoc khi khoi dong de code va database luon cung revision.
"%~dp0.venv\Scripts\python.exe" -m alembic upgrade head
if errorlevel 1 (
    echo Khong the cap nhat database. Backend chua duoc khoi dong.
    exit /b 1
)

"%~dp0.venv\Scripts\python.exe" -m uvicorn app.main:app --host %API_HOST% --port %API_PORT% --reload
