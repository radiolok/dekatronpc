onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb/Rst_n
add wave -noupdate /tb/Clk
add wave -noupdate /tb/Emulator/Clock_1us
add wave -noupdate /tb/Emulator/Clock_1ms
add wave -noupdate /tb/Emulator/Clock_1s
add wave -noupdate /tb/emulData
add wave -noupdate /tb/in12_write_anode
add wave -noupdate /tb/in12_write_cathode
add wave -noupdate /tb/ms6205_write_addr_n
add wave -noupdate /tb/ms6205_write_data_n
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