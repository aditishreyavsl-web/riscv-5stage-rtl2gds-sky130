// =============================================================================
// rv32_core : 5-stage in-order pipelined RV32I core (IF, ID, EX, MEM, WB)
//
//  * Full forwarding (EX/MEM -> EX, MEM/WB -> EX, WB -> ID regfile bypass)
//  * Load-use hazard: 1-cycle stall
//  * Branches/JAL/JALR resolved in EX, predict-not-taken, 2-cycle flush penalty
//  * Memory interface: combinational-read instruction and data ports
//    (core is intended to be hardened as a macro, memories live outside)
// =============================================================================
module rv32_core #(
    parameter RESET_VECTOR = 32'h0000_0000
) (
    input         clk,
    input         rst_n,
    // instruction memory
    output [31:0] imem_addr,
    input  [31:0] imem_rdata,
    // data memory
    output [31:0] dmem_addr,
    output [31:0] dmem_wdata,
    output [3:0]  dmem_wstrb,
    output        dmem_re,
    input  [31:0] dmem_rdata
);
    localparam [31:0] NOP = 32'h0000_0013; // addi x0,x0,0

    // ------------------------------------------------------------------ IF --
    reg  [31:0] pc;
    wire        stall;          // load-use stall (hold IF and ID)
    wire        redirect;       // taken branch / jump from EX
    wire [31:0] redirect_pc;

    assign imem_addr = pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        pc <= RESET_VECTOR;
        else if (redirect) pc <= redirect_pc;
        else if (!stall)   pc <= pc + 32'd4;
    end

    // IF/ID
    reg [31:0] ifid_pc, ifid_instr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifid_pc <= 32'b0; ifid_instr <= NOP;
        end else if (redirect) begin
            ifid_pc <= 32'b0; ifid_instr <= NOP;
        end else if (!stall) begin
            ifid_pc <= pc;    ifid_instr <= imem_rdata;
        end
    end

    // ------------------------------------------------------------------ ID --
    wire [4:0] id_rs1 = ifid_instr[19:15];
    wire [4:0] id_rs2 = ifid_instr[24:20];
    wire [4:0] id_rd  = ifid_instr[11:7];

    wire        d_reg_write, d_mem_read, d_mem_write, d_branch, d_jal, d_jalr;
    wire        d_alu_src_imm, d_lui, d_auipc, d_uses_rs1, d_uses_rs2;
    wire [3:0]  d_alu_ctrl;
    rv32_decode u_dec (
        .instr(ifid_instr), .reg_write(d_reg_write), .mem_read(d_mem_read),
        .mem_write(d_mem_write), .branch(d_branch), .jal(d_jal), .jalr(d_jalr),
        .alu_src_imm(d_alu_src_imm), .lui(d_lui), .auipc(d_auipc),
        .uses_rs1(d_uses_rs1), .uses_rs2(d_uses_rs2), .alu_ctrl(d_alu_ctrl)
    );

    wire [31:0] id_imm;
    rv32_imm_gen u_imm (.instr(ifid_instr), .imm(id_imm));

    // WB-stage signals (declared here, driven below)
    wire        wb_we;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    wire [31:0] id_rdata1, id_rdata2;
    rv32_regfile u_rf (
        .clk(clk), .we(wb_we), .waddr(wb_rd), .wdata(wb_data),
        .raddr1(id_rs1), .raddr2(id_rs2), .rdata1(id_rdata1), .rdata2(id_rdata2)
    );

    // ID/EX register
    reg [31:0] idex_pc, idex_rs1_val, idex_rs2_val, idex_imm;
    reg [4:0]  idex_rs1, idex_rs2, idex_rd;
    reg [2:0]  idex_f3;
    reg [3:0]  idex_alu_ctrl;
    reg        idex_reg_write, idex_mem_read, idex_mem_write, idex_branch, idex_jal,
               idex_jalr, idex_alu_src_imm, idex_lui, idex_auipc;

    // load-use hazard detection (instruction in EX is a load that ID needs)
    assign stall = idex_mem_read && (idex_rd != 5'd0) &&
                   ((d_uses_rs1 && idex_rd == id_rs1) ||
                    (d_uses_rs2 && idex_rd == id_rs2));

    wire idex_bubble = redirect | stall;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idex_pc <= 32'b0; idex_rs1_val <= 32'b0; idex_rs2_val <= 32'b0; idex_imm <= 32'b0;
            idex_rs1 <= 5'b0; idex_rs2 <= 5'b0; idex_rd <= 5'b0; idex_f3 <= 3'b0;
            idex_alu_ctrl <= 4'b0;
            idex_reg_write <= 0; idex_mem_read <= 0; idex_mem_write <= 0; idex_branch <= 0;
            idex_jal <= 0; idex_jalr <= 0; idex_alu_src_imm <= 0; idex_lui <= 0; idex_auipc <= 0;
        end else if (idex_bubble) begin
            // insert bubble: only control signals need clearing
            idex_rd <= 5'b0; idex_rs1 <= 5'b0; idex_rs2 <= 5'b0;
            idex_reg_write <= 0; idex_mem_read <= 0; idex_mem_write <= 0; idex_branch <= 0;
            idex_jal <= 0; idex_jalr <= 0; idex_lui <= 0; idex_auipc <= 0;
        end else begin
            idex_pc <= ifid_pc; idex_rs1_val <= id_rdata1; idex_rs2_val <= id_rdata2;
            idex_imm <= id_imm;
            idex_rs1 <= id_rs1; idex_rs2 <= id_rs2; idex_rd <= id_rd;
            idex_f3 <= ifid_instr[14:12];
            idex_alu_ctrl <= d_alu_ctrl;
            idex_reg_write <= d_reg_write; idex_mem_read <= d_mem_read;
            idex_mem_write <= d_mem_write; idex_branch <= d_branch;
            idex_jal <= d_jal; idex_jalr <= d_jalr; idex_alu_src_imm <= d_alu_src_imm;
            idex_lui <= d_lui; idex_auipc <= d_auipc;
        end
    end

    // ------------------------------------------------------------------ EX --
    // MEM/WB + EX/MEM state used for forwarding (declared below)
    reg  [31:0] exmem_result, exmem_rs2_val;
    reg  [4:0]  exmem_rd;
    reg  [2:0]  exmem_f3;
    reg         exmem_reg_write, exmem_mem_read, exmem_mem_write;
    reg  [31:0] memwb_data;
    reg  [4:0]  memwb_rd;
    reg         memwb_reg_write;

    // Note: load data is NOT forwarded from MEM (keeps dmem_rdata off the EX path);
    // load-use is handled by a 1-cycle stall + forwarding from MEM/WB instead.
    wire [31:0] mem_stage_value;   // MEM-stage result (ALU result or load data) -> MEM/WB

    reg [31:0] fwd_a, fwd_b;
    always @(*) begin
        if (exmem_reg_write && exmem_rd != 5'd0 && exmem_rd == idex_rs1)
            fwd_a = exmem_result;
        else if (memwb_reg_write && memwb_rd != 5'd0 && memwb_rd == idex_rs1)
            fwd_a = memwb_data;
        else
            fwd_a = idex_rs1_val;

        if (exmem_reg_write && exmem_rd != 5'd0 && exmem_rd == idex_rs2)
            fwd_b = exmem_result;
        else if (memwb_reg_write && memwb_rd != 5'd0 && memwb_rd == idex_rs2)
            fwd_b = memwb_data;
        else
            fwd_b = idex_rs2_val;
    end

    wire [31:0] alu_a = idex_lui ? 32'b0 : (idex_auipc ? idex_pc : fwd_a);
    wire [31:0] alu_b = idex_alu_src_imm ? idex_imm : fwd_b;
    wire [31:0] alu_y;
    rv32_alu u_alu (.a(alu_a), .b(alu_b), .ctrl(idex_alu_ctrl), .y(alu_y));

    // branch comparison
    reg br_taken;
    always @(*) begin
        case (idex_f3)
            3'b000:  br_taken = (fwd_a == fwd_b);
            3'b001:  br_taken = (fwd_a != fwd_b);
            3'b100:  br_taken = ($signed(fwd_a) <  $signed(fwd_b));
            3'b101:  br_taken = ($signed(fwd_a) >= $signed(fwd_b));
            3'b110:  br_taken = (fwd_a <  fwd_b);
            3'b111:  br_taken = (fwd_a >= fwd_b);
            default: br_taken = 1'b0;
        endcase
    end

    assign redirect    = idex_jal | idex_jalr | (idex_branch & br_taken);
    assign redirect_pc = idex_jalr ? ((fwd_a + idex_imm) & 32'hFFFF_FFFE)
                                   : (idex_pc + idex_imm);

    wire [31:0] ex_result = (idex_jal | idex_jalr) ? (idex_pc + 32'd4) : alu_y;

    // EX/MEM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exmem_result <= 32'b0; exmem_rs2_val <= 32'b0; exmem_rd <= 5'b0; exmem_f3 <= 3'b0;
            exmem_reg_write <= 0; exmem_mem_read <= 0; exmem_mem_write <= 0;
        end else begin
            exmem_result <= ex_result; exmem_rs2_val <= fwd_b; exmem_rd <= idex_rd;
            exmem_f3 <= idex_f3;
            exmem_reg_write <= idex_reg_write; exmem_mem_read <= idex_mem_read;
            exmem_mem_write <= idex_mem_write;
        end
    end

    // ----------------------------------------------------------------- MEM --
    assign dmem_addr = exmem_result;
    assign dmem_re   = exmem_mem_read;

    // store data alignment & byte strobes
    reg [31:0] st_data;
    reg [3:0]  st_strb;
    always @(*) begin
        case (exmem_f3[1:0])
            2'b00: begin st_data = {4{exmem_rs2_val[7:0]}};  st_strb = 4'b0001 << exmem_result[1:0]; end
            2'b01: begin st_data = {2{exmem_rs2_val[15:0]}}; st_strb = exmem_result[1] ? 4'b1100 : 4'b0011; end
            default: begin st_data = exmem_rs2_val;          st_strb = 4'b1111; end
        endcase
    end
    assign dmem_wdata = st_data;
    assign dmem_wstrb = exmem_mem_write ? st_strb : 4'b0000;

    // load data alignment & extension
    reg [31:0] ld_data;
    reg [7:0]  ld_byte;
    reg [15:0] ld_half;
    always @(*) begin
        case (exmem_result[1:0])
            2'd0: ld_byte = dmem_rdata[7:0];
            2'd1: ld_byte = dmem_rdata[15:8];
            2'd2: ld_byte = dmem_rdata[23:16];
            default: ld_byte = dmem_rdata[31:24];
        endcase
        ld_half = exmem_result[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
        case (exmem_f3)
            3'b000:  ld_data = {{24{ld_byte[7]}},  ld_byte};   // LB
            3'b001:  ld_data = {{16{ld_half[15]}}, ld_half};   // LH
            3'b100:  ld_data = {24'b0, ld_byte};               // LBU
            3'b101:  ld_data = {16'b0, ld_half};               // LHU
            default: ld_data = dmem_rdata;                     // LW
        endcase
    end

    assign mem_stage_value = exmem_mem_read ? ld_data : exmem_result;

    // MEM/WB
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memwb_data <= 32'b0; memwb_rd <= 5'b0; memwb_reg_write <= 0;
        end else begin
            memwb_data <= mem_stage_value; memwb_rd <= exmem_rd;
            memwb_reg_write <= exmem_reg_write;
        end
    end

    // ------------------------------------------------------------------ WB --
    assign wb_we   = memwb_reg_write;
    assign wb_rd   = memwb_rd;
    assign wb_data = memwb_data;
endmodule
