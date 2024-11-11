vlib work
vlog -sv  -f files

if %errorlevel% neq 0 exit /b %errorlevel%

rem vsim -gui  -do "do wave.do; run -all" ip_line_tb
vsim -c -do  "run -all ; echo [simstats]; quit -f" -c work.ip_line_tb