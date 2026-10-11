// ALU for RV32I
module rv32_alu (
    input  [31:0] a,
    input  [31:0] b,
    input  [3:0]  ctrl,
    output reg [31:0] y
);
    localparam ALU_ADD=4'd0, ALU_SUB=4'd1, ALU_SLL=4'd2, ALU_SLT=4'd3, ALU_SLTU=4'd4,
               ALU_XOR=4'd5, ALU_SRL=4'd6, ALU_SRA=4'd7, ALU_OR=4'd8, ALU_AND=4'd9;
    wire signed [31:0] sa = a;
    always @(*) begin
        case (ctrl)
            ALU_ADD:  y = a + b;
            ALU_SUB:  y = a - b;
            ALU_SLL:  y = a << b[4:0];
            ALU_SLT:  y = {31'b0, ($signed(a) < $signed(b))};
            ALU_SLTU: y = {31'b0, (a < b)};
            ALU_XOR:  y = a ^ b;
            ALU_SRL:  y = a >> b[4:0];
            ALU_SRA:  y = sa >>> b[4:0];
            ALU_OR:   y = a | b;
            ALU_AND:  y = a & b;
            default:  y = 32'b0;
        endcase
    end
endmodule
