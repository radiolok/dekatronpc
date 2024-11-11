onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /Rst_n
add wave -noupdate /Clk
add wave -noupdate /Address
add wave -noupdate /Insn
add wave -noupdate /Request
add wave -noupdate /Ready
add wave -noupdate /Busy
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