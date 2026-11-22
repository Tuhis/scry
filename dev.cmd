@echo off
where py >nul 2>nul && (py -3 "%~dp0tools\dev.py" %*) || (python "%~dp0tools\dev.py" %*)
