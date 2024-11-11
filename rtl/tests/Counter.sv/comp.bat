vlib work
vlog -sv  -incr -f files

if %errorlevel% neq 0 exit /b %errorlevel%

vsim -gui  -do "do wave.do; run -all" counter_tb
rem vsim -c -do  "run 100 ; echo [simstats]; quit -f" -c work.tb