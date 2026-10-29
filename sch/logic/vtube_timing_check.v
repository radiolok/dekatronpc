// Setup/hold checker for the trigger cells of vtube_cells.v, gate-level
// simulation only (synth_sim.sh -t).
//
// Icarus parses $setuphold and the SDF TIMINGCHECK entries but never
// checks them, so rtl/run/vtube_sdf.py puts one of these next to every
// DFF_J2N16/DFFSR/DFFSR_n instance of the netlist, connected by hierarchical
// references to the cell's pins. D must not change in the window
// [edge - SETUP, edge + HOLD) around the capturing edge of C (falling with NEGEDGE): a change exactly SETUP before or
// HOLD after the edge is still allowed. A trigger is two latches in a row:
// SETUP is the master's time to take D, HOLD the time until the master
// is closed off by the slave.
//
// Checks are off while the asynchronous set/clear holds the trigger
// (ASYNC: 0 DFF_J2N16, 1 DFFSR with S/R active high, 2 DFFSR_n with R active
// low) and before the first capturing edge of C. Recovery/removal of S/R
// against C is not checked.
//
// QUALIFY = 1: a trigger whose value matters only when the next cycle
// consumes it (vtube_timing.json "masked", e.g. the cathode readings that
// DekatronCounter latches every Clk; doc/vtube_sdf_timing.md §3.5). A
// violation around edge E is held until edge E+1 and counted only if EN
// (the consumer, e.g. valid & ready) is 1 there; otherwise it goes to
// masked_cnt. Such a trigger samples asynchronous cathodes, so a violation
// is expected while nothing reads it.
module vtube_setuphold #(
	parameter real SETUP = 0.0,	// ns
	parameter real HOLD = 0.0,	// ns
	parameter ASYNC = 0,
	parameter MAX_REPORTS = 5,	// messages per instance, then only counted
	parameter QUALIFY = 0,		// 1: count only when EN at the next edge
	parameter NEGEDGE = 0		// 1: the trigger captures on the falling edge of C
)(
	input C, D, S, R,
	input EN
);
	timeunit 1ns;
	timeprecision 1ps;

	integer setup_cnt = 0;
	integer hold_cnt = 0;
	integer masked_cnt = 0;
	// QUALIFY: violations waiting for the next edge, and their messages
	integer pend_setup = 0;
	integer pend_hold = 0;
	string  pend_msg = "";
	realtime t_c = -1.0e12;
	realtime t_d = -1.0e12;
	reg seen_c = 1'b0;

	wire ck = NEGEDGE ? ~C : C;
	wire held = (ASYNC == 1) ? (S | R) :
	            (ASYNC == 2) ? (S | ~R) : 1'b0;

	task automatic report(input string msg);
		if (setup_cnt + hold_cnt <= MAX_REPORTS)
			$display("%s", msg);
	endtask

	always @(posedge ck) begin
		// Violations of the previous edge: count them if the value is used
		if (pend_setup + pend_hold > 0) begin
			if (EN === 1'b1) begin
				setup_cnt = setup_cnt + pend_setup;
				hold_cnt  = hold_cnt + pend_hold;
				report({pend_msg, " (value used)"});
			end
			else
				masked_cnt = masked_cnt + pend_setup + pend_hold;
			pend_setup = 0;
			pend_hold  = 0;
			pend_msg   = "";
		end
		if (seen_c && held !== 1'b1 && $realtime - t_d < SETUP) begin
			if (QUALIFY) begin
				pend_setup = pend_setup + 1;
				if (pend_msg == "")
					pend_msg = $sformatf("VTUBE SETUP %m: D changed %0.1f ns before C at %0.1f ns (needs %0.1f)",
					                     $realtime - t_d, $realtime, SETUP);
			end
			else begin
				setup_cnt = setup_cnt + 1;
				report($sformatf("VTUBE SETUP %m: D changed %0.1f ns before C at %0.1f ns (needs %0.1f)",
				                 $realtime - t_d, $realtime, SETUP));
			end
		end
		t_c = $realtime;
		seen_c = 1'b1;
	end

	always @(D) begin
		if (seen_c && held !== 1'b1 && $realtime - t_c < HOLD) begin
			if (QUALIFY) begin
				pend_hold = pend_hold + 1;
				if (pend_msg == "")
					pend_msg = $sformatf("VTUBE HOLD  %m: D changed %0.1f ns after C at %0.1f ns (needs %0.1f)",
					                     $realtime - t_c, $realtime, HOLD);
			end
			else begin
				hold_cnt = hold_cnt + 1;
				report($sformatf("VTUBE HOLD  %m: D changed %0.1f ns after C at %0.1f ns (needs %0.1f)",
				                 $realtime - t_c, $realtime, HOLD));
			end
		end
		t_d = $realtime;
	end
endmodule
