vlib work
vlog -sv -novopt -incr -f files

vsim -c -do  "run 20 ; echo [simstats]; quit -f" -c work.tb