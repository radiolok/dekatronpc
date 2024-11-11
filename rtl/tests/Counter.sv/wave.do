onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /counter_tb/Rst_n
add wave -noupdate /counter_tb/Clk
add wave -noupdate /counter_tb/Dec
add wave -noupdate /counter_tb/Set
add wave -noupdate /counter_tb/counter/In
add wave -noupdate /counter_tb/counter/Out
add wave -noupdate /counter_tb/counter/Ready
add wave -noupdate /counter_tb/counter/Request
add wave -noupdate /counter_tb/counter/delay_shifter
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {100 ps} 0}
configure wave -namecolwidth 257
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 208
configure wave -griddelta 8
configure wave -timeline 1
configure wave -timelineunits ps
update
WaveRestoreZoom {100 ps} {100 ps}