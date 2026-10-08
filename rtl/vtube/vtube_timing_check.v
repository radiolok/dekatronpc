// Setup/hold checker for the trigger cells of vtube_cells.v, gate-level
// simulation only (synth_sim.sh -t).
//
// Icarus parses $setuphold and the SDF TIMINGCHECK entries but never
// checks them, so rtl/run/vtube_sdf.py puts one of these next to every
// DFF/DFFSR/DFFSR_n instance of the netlist, connected by hierarchical
// references to the cell's pins. D must not change in the window
// [posedge C - SETUP, posedge C + HOLD): a change exactly SETUP before or
// HOLD after the edge is still allowed. A trigger is two latches in a row:
// SETUP is the master's time to take D, HOLD the time until the master
// is closed off by the slave.
//
// Checks are off while the asynchronous set/clear holds the trigger
// (ASYNC: 0 DFF, 1 DFFSR with S/R active high, 2 DFFSR_n with R active
// low) and before the first rising edge of C. Recovery/removal of S/R
// against C is not checked.
module vtube_setuphold #(
	parameter real SETUP = 0.0,	// ns
	parameter real HOLD = 0.0,	// ns
	parameter ASYNC = 0,
	parameter MAX_REPORTS = 5	// messages per instance, then only counted
)(
	input C, D, S, R
);
	timeunit 1ns;
	timeprecision 1ps;

	integer setup_cnt = 0;
	integer hold_cnt = 0;
	realtime t_c = -1.0e12;
	realtime t_d = -1.0e12;
	reg seen_c = 1'b0;

	wire held = (ASYNC == 1) ? (S | R) :
	            (ASYNC == 2) ? (S | ~R) : 1'b0;

	always @(posedge C) begin
		if (seen_c && held !== 1'b1 && $realtime - t_d < SETUP) begin
			setup_cnt = setup_cnt + 1;
			if (setup_cnt + hold_cnt <= MAX_REPORTS)
				$display("VTUBE SETUP %m: D changed %0.1f ns before C at %0.1f ns (needs %0.1f)",
				         $realtime - t_d, $realtime, SETUP);
		end
		t_c = $realtime;
		seen_c = 1'b1;
	end

	always @(D) begin
		if (seen_c && held !== 1'b1 && $realtime - t_c < HOLD) begin
			hold_cnt = hold_cnt + 1;
			if (setup_cnt + hold_cnt <= MAX_REPORTS)
				$display("VTUBE HOLD  %m: D changed %0.1f ns after C at %0.1f ns (needs %0.1f)",
				         $realtime - t_c, $realtime, HOLD);
		end
		t_d = $realtime;
	end
endmodule
