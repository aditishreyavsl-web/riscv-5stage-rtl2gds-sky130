// 32x32 register file, 2 async read ports, 1 sync write port, x0 = 0,
// write-through bypass (WB -> ID same-cycle)
module rv32_regfile (
    input         clk,
    input         we,
    input  [4:0]  waddr,
    input  [31:0] wdata,
    input  [4:0]  raddr1,
    input  [4:0]  raddr2,
    output [31:0] rdata1,
    output [31:0] rdata2
);
    reg [31:0] regs [1:31];
`ifdef SIM
    integer i;
    initial for (i = 1; i < 32; i = i + 1) regs[i] = 32'b0;
`endif
    always @(posedge clk)
        if (we && waddr != 5'd0) regs[waddr] <= wdata;

    wire [31:0] r1 = (raddr1 == 5'd0) ? 32'b0 : regs[raddr1];
    wire [31:0] r2 = (raddr2 == 5'd0) ? 32'b0 : regs[raddr2];
    assign rdata1 = (we && waddr != 5'd0 && waddr == raddr1) ? wdata : r1;
    assign rdata2 = (we && waddr != 5'd0 && waddr == raddr2) ? wdata : r2;
endmodule
