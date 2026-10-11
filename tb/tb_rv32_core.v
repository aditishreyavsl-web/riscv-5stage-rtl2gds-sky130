`timescale 1ns/1ps
// Self-checking testbench: loads sw/test.hex into IMEM, runs until the program
// stores to TOHOST (0xFF0). value 1 = PASS, 0xDEAD00nn = FAIL in test nn.
module tb_rv32_core;
    parameter HEX = "sw/test.hex";
    parameter TOHOST = 32'h0000_0FF0;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;                 // 100 MHz functional sim clock

    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_re;

    rv32_core dut (.clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .dmem_re(dmem_re), .dmem_rdata(dmem_rdata));

    reg [31:0] imem [0:1023];
    reg [31:0] dmem [0:1023];
    assign imem_rdata = imem[imem_addr[11:2]];
    assign dmem_rdata = dmem[dmem_addr[11:2]];

    always @(posedge clk) if (|dmem_wstrb) begin
        if (dmem_wstrb[0]) dmem[dmem_addr[11:2]][7:0]   <= dmem_wdata[7:0];
        if (dmem_wstrb[1]) dmem[dmem_addr[11:2]][15:8]  <= dmem_wdata[15:8];
        if (dmem_wstrb[2]) dmem[dmem_addr[11:2]][23:16] <= dmem_wdata[23:16];
        if (dmem_wstrb[3]) dmem[dmem_addr[11:2]][31:24] <= dmem_wdata[31:24];
    end

    integer i, cycles = 0, retired_est = 0;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin imem[i] = 32'h13; dmem[i] = 32'b0; end
        $readmemh(HEX, imem);
        `ifdef VCD $dumpfile("sim/tb_rv32_core.vcd"); $dumpvars(0, tb_rv32_core); `endif
        repeat (4) @(posedge clk);
        rst_n = 1;
    end

    always @(posedge clk) if (rst_n) begin
        cycles = cycles + 1;
        if (|dmem_wstrb && {dmem_addr[31:2], 2'b00} == TOHOST) begin
            if (dmem_wdata == 32'd1) begin
                $display("[TB] PASS after %0d cycles", cycles);
                $finish;
            end else begin
                $display("[TB] FAIL: tohost = 0x%08h (test #%0d)", dmem_wdata, dmem_wdata[7:0]);
                $finish;
            end
        end
        if (cycles > 20000) begin $display("[TB] TIMEOUT"); $finish; end
    end
endmodule
