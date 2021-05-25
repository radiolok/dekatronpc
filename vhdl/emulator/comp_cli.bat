vlib work
vlog -sv -incr -f files

rem vsim -gui -novopt -do "do wave.do; run -all" work.tb
rem vsim -c -do  "run 10 ; echo [simstats]; quit -f" -c work.tb