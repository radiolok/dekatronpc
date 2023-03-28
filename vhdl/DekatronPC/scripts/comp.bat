vlib work
vlog -sv -novopt -incr -f files

vsim -gui -novopt -do "do wave.do; run -all" work.tb
rem vsim -c -do  "run 100 ; echo [simstats]; quit -f" -c work.tb