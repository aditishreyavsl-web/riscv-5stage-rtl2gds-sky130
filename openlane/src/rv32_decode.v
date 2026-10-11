// Main control decoder (RV32I)
module rv32_decode (
    input  [31:0] instr,
    output reg    reg_write,
    output reg    mem_read,
    output reg    mem_write,
    output reg    branch,
    output reg    jal,
    output reg    jalr,
    output reg    alu_src_imm,
    output reg    lui,
    output reg    auipc,
    output reg    uses_rs1,
    output reg    uses_rs2,
    output reg [3:0] alu_ctrl
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] f3     = instr[14:12];
    wire       f7b5   = instr[30];

    always @(*) begin
        reg_write = 0; mem_read = 0; mem_write = 0; branch = 0; jal = 0; jalr = 0;
        alu_src_imm = 0; lui = 0; auipc = 0; uses_rs1 = 0; uses_rs2 = 0; alu_ctrl = 4'd0;
        case (opcode)
            7'b0110011: begin // OP
                reg_write = 1; uses_rs1 = 1; uses_rs2 = 1;
                case (f3)
                    3'b000: alu_ctrl = f7b5 ? 4'd1 : 4'd0;
                    3'b001: alu_ctrl = 4'd2;
                    3'b010: alu_ctrl = 4'd3;
                    3'b011: alu_ctrl = 4'd4;
                    3'b100: alu_ctrl = 4'd5;
                    3'b101: alu_ctrl = f7b5 ? 4'd7 : 4'd6;
                    3'b110: alu_ctrl = 4'd8;
                    3'b111: alu_ctrl = 4'd9;
                endcase
            end
            7'b0010011: begin // OP-IMM
                reg_write = 1; uses_rs1 = 1; alu_src_imm = 1;
                case (f3)
                    3'b000: alu_ctrl = 4'd0;
                    3'b001: alu_ctrl = 4'd2;
                    3'b010: alu_ctrl = 4'd3;
                    3'b011: alu_ctrl = 4'd4;
                    3'b100: alu_ctrl = 4'd5;
                    3'b101: alu_ctrl = f7b5 ? 4'd7 : 4'd6;
                    3'b110: alu_ctrl = 4'd8;
                    3'b111: alu_ctrl = 4'd9;
                endcase
            end
            7'b0000011: begin reg_write = 1; mem_read = 1;  uses_rs1 = 1; alu_src_imm = 1; end // LOAD
            7'b0100011: begin mem_write = 1; uses_rs1 = 1; uses_rs2 = 1; alu_src_imm = 1; end   // STORE
            7'b1100011: begin branch = 1; uses_rs1 = 1; uses_rs2 = 1; end                       // BRANCH
            7'b1101111: begin reg_write = 1; jal = 1; end                                       // JAL
            7'b1100111: begin reg_write = 1; jalr = 1; uses_rs1 = 1; alu_src_imm = 1; end       // JALR
            7'b0110111: begin reg_write = 1; lui = 1; alu_src_imm = 1; end                      // LUI
            7'b0010111: begin reg_write = 1; auipc = 1; alu_src_imm = 1; end                    // AUIPC
            default: ;                                                                          // NOP / unsupported
        endcase
    end
endmodule
