@echo off
echo Đang khởi động Backend v_monitor...
cd /d "%~dp0backend"
set PYTHONPATH=%cd%
call ..\.venv\Scripts\activate.bat
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
