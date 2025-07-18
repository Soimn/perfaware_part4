@echo off

setlocal

cd %~dp0

if not exist build mkdir build

cd build

cl /nologo /W3 /O2 ..\src\math_test.c /link /incremental:no /opt:ref /out:math_test_c.exe

endlocal
