vlib work
vlog -sv -novopt -incr -f files

rem vsim -gui -novopt -do "do wave.do; run -all" work.tb
vsim -c -do  "run 10 ; echo [simstats]; quit -f" -c work.tb