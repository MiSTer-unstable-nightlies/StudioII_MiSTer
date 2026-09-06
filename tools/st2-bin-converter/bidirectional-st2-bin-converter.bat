@echo off
title RCA Studio II ST2/BIN Converter
echo Processing files...
echo =======================================

python "%~dp0st2_converter.py" %*

echo =======================================
pause