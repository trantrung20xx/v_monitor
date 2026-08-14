@echo off
echo Đang khởi động Backend v_monitor...
cd /d "%~dp0backend"
set PYTHONPATH=%cd%
call ..\.venv\Scripts\activate.bat
if "%API_HOST%"=="" set API_HOST=0.0.0.0
if "%API_PORT%"=="" set API_PORT=8000
uvicorn app.main:app --host %API_HOST% --port %API_PORT% --reload
