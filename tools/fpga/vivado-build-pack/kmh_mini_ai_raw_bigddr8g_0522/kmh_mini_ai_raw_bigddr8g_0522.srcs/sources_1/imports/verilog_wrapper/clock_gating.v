`timescale 1ns / 1ps

module clock_gating(
    input sys_clk,
    input enable,
    input rstn,
    output gated_clk
    );

BUFGCE inst_bufgce (
    .O(gated_clk),
    .I(sys_clk),
    .CE(!rstn || enable)
);

//assign gated_clk = sys_clk;

endmodule
