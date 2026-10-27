
@echo off
setlocal

set "QUARTUS_BIN=C:\Tools\altera\13.1\quartus\bin"
set "PROJECT=top"
set "REVISION=top"

rem -----------------------------------------
rem Navigate timestamp script
rem -----------------------------------------
cd ..
cd ..
cd riscv_soc_shell
cd rtl_common
cd script
python generate_timestamp_pkg.py
cd ..
cd ..
cd ..
cd build
cd de0

rem -----------------------------------------
rem Navigate to Quartus project
rem -----------------------------------------

cd prj
if errorlevel 1 exit /b 1

rem -----------------------------------------
rem Quartus compilation
rem -----------------------------------------

"%QUARTUS_BIN%\quartus_map.exe" ^
    --read_settings_files=on ^
    --write_settings_files=off ^
    %PROJECT% ^
    -c %REVISION%
if errorlevel 1 exit /b 1

"%QUARTUS_BIN%\quartus_fit.exe" ^
    --read_settings_files=off ^
    --write_settings_files=off ^
    %PROJECT% ^
    -c %REVISION%
if errorlevel 1 exit /b 1

"%QUARTUS_BIN%\quartus_asm.exe" ^
    --read_settings_files=off ^
    --write_settings_files=off ^
    %PROJECT% ^
    -c %REVISION%
if errorlevel 1 exit /b 1

"%QUARTUS_BIN%\quartus_sta.exe" ^
    %PROJECT% ^
    -c %REVISION%
if errorlevel 1 exit /b 1

echo.
echo Compilation completed successfully.

endlocal
exit /b 0
