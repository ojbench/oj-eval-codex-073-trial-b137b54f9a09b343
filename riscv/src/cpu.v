`timescale 1ns/1ps

module cpu(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,
    output reg [31:0] pc,
    output reg [31:0] inst_addr,
    input wire [31:0] inst_in,
    output reg inst_sram_en,
    output reg [31:0] inst_sram_addr,
    input wire [31:0] inst_sram_rdata,
    output reg [31:0] data_addr,
    output reg [31:0] data_wdata,
    input wire [31:0] data_rdata,
    output reg [3:0] data_wen,
    output reg data_sram_en,
    output reg [31:0] data_sram_addr,
    output reg [31:0] data_sram_wdata,
    input wire [31:0] data_sram_rdata,
    output reg [3:0] data_sram_wen,
    input wire io_buffer_full,
    output reg io_buffer_we,
    output reg [7:0] io_buffer_data
);
    reg [31:0] regs [0:31];
    reg [31:0] ir;
    reg [31:0] rs1_val;
    reg [31:0] rs2_val;
    reg [31:0] next_pc;
    reg [31:0] result;
    reg do_wb;
    reg do_mem_read;
    reg do_mem_write;
    reg [31:0] mem_addr;
    reg [31:0] mem_wdata;
    reg [3:0] mem_wmask;
    reg [31:0] load_word;

    wire [6:0] opcode = ir[6:0];
    wire [2:0] funct3 = ir[14:12];
    wire [6:0] funct7 = ir[31:25];
    wire [4:0] rs1 = ir[19:15];
    wire [4:0] rs2 = ir[24:20];
    wire [4:0] rd = ir[11:7];

    function [31:0] sext12(input [11:0] x); begin sext12 = {{20{x[11]}}, x}; end endfunction
    function [31:0] sext13(input [12:0] x); begin sext13 = {{19{x[12]}}, x}; end endfunction
    function [31:0] sext20(input [19:0] x); begin sext20 = {{12{x[19]}}, x}; end endfunction

    function [31:0] load_result(input [2:0] f3, input [31:0] addr, input [31:0] word);
        begin
            case (f3)
                3'b000: load_result = {{24{word[8*addr[1:0]+7]}}, word[8*addr[1:0]+:8]};
                3'b001: load_result = addr[1] ? {{16{word[31]}}, word[31:16]} : {{16{word[15]}}, word[15:0]};
                3'b010: load_result = word;
                3'b100: load_result = {24'b0, word[8*addr[1:0]+:8]};
                3'b101: load_result = addr[1] ? {16'b0, word[31:16]} : {16'b0, word[15:0]};
                default: load_result = 32'b0;
            endcase
        end
    endfunction

    function [3:0] store_mask(input [2:0] f3, input [1:0] addr_low);
        begin
            case (f3)
                3'b000: store_mask = 4'b0001 << addr_low;
                3'b001: store_mask = addr_low[1] ? 4'b1100 : 4'b0011;
                3'b010: store_mask = 4'b1111;
                default: store_mask = 4'b0000;
            endcase
        end
    endfunction

    integer i;
    always @(posedge clk_in) begin
        if (rst_in) begin
            pc <= 0;
            inst_addr <= 0;
            inst_sram_en <= 1;
            inst_sram_addr <= 0;
            data_addr <= 0;
            data_wdata <= 0;
            data_wen <= 0;
            data_sram_en <= 0;
            data_sram_addr <= 0;
            data_sram_wdata <= 0;
            data_sram_wen <= 0;
            io_buffer_we <= 0;
            io_buffer_data <= 0;
            ir <= 0;
            for (i = 0; i < 32; i = i + 1) regs[i] <= 0;
        end else if (rdy_in) begin
            io_buffer_we <= 0;
            data_wen <= 0;
            data_sram_wen <= 0;
            data_sram_en <= 0;
            inst_sram_en <= 1;

            ir <= inst_sram_rdata;
            inst_addr <= pc;
            inst_sram_addr <= pc;
            rs1_val = regs[rs1];
            rs2_val = regs[rs2];
            next_pc = pc + 4;
            result = 0;
            do_wb = 0;
            do_mem_read = 0;
            do_mem_write = 0;
            mem_addr = 0;
            mem_wdata = 0;
            mem_wmask = 0;
            load_word = 0;

            case (opcode)
                7'b0110111: begin
                    result = {ir[31:12], 12'b0};
                    do_wb = (rd != 0);
                end
                7'b0010111: begin
                    result = pc + {ir[31:12], 12'b0};
                    do_wb = (rd != 0);
                end
                7'b1101111: begin
                    result = pc + 4;
                    next_pc = pc + sext20({ir[31], ir[19:12], ir[20], ir[30:21], 1'b0});
                    do_wb = (rd != 0);
                end
                7'b1100111: begin
                    result = pc + 4;
                    next_pc = (rs1_val + sext12(ir[31:20])) & 32'hffff_fffe;
                    do_wb = (rd != 0);
                end
                7'b1100011: begin
                    case (funct3)
                        3'b000: if (rs1_val == rs2_val) next_pc = pc + sext13({ir[31], ir[7], ir[30:25], ir[11:8], 1'b0});
                        3'b001: if (rs1_val != rs2_val) next_pc = pc + sext13({ir[31], ir[7], ir[30:25], ir[11:8], 1'b0});
                        3'b100: if ($signed(rs1_val) < $signed(rs2_val)) next_pc = pc + sext13({ir[31], ir[7], ir[30:25], ir[11:8], 1'b0});
                        3'b101: if ($signed(rs1_val) >= $signed(rs2_val)) next_pc = pc + sext13({ir[31], ir[7], ir[30:25], ir[11:8], 1'b0});
                        3'b110: if (rs1_val < rs2_val) next_pc = pc + sext13({ir[31], ir[7], ir[30:25], ir[11:8], 1'b0});
                        3'b111: if (rs1_val >= rs2_val) next_pc = pc + sext13({ir[31], ir[7], ir[30:25], ir[11:8], 1'b0});
                    endcase
                end
                7'b0000011: begin
                    mem_addr = rs1_val + sext12(ir[31:20]);
                    do_mem_read = 1;
                    result = 0;
                    do_wb = (rd != 0);
                    if (mem_addr == 32'h0003_0000) begin
                        case (funct3)
                            3'b000: result = {24'b0, 8'h00};
                            3'b100: result = {24'b0, 8'h00};
                            default: result = 0;
                        endcase
                    end else begin
                        case (funct3)
                            3'b000, 3'b100: load_word = data_sram_rdata;
                            3'b001, 3'b101: load_word = data_sram_rdata;
                            3'b010: load_word = data_sram_rdata;
                            default: load_word = 32'b0;
                        endcase
                        result = load_result(funct3, mem_addr, load_word);
                    end
                end
                7'b0100011: begin
                    mem_addr = rs1_val + sext12({ir[31:25], ir[11:7]});
                    mem_wdata = rs2_val;
                    mem_wmask = store_mask(funct3, mem_addr[1:0]);
                    do_mem_write = (mem_wmask != 0);
                end
                7'b0010011: begin
                    case (funct3)
                        3'b000: result = rs1_val + sext12(ir[31:20]);
                        3'b010: result = ($signed(rs1_val) < $signed(sext12(ir[31:20]))) ? 32'b1 : 32'b0;
                        3'b011: result = (rs1_val < sext12(ir[31:20])) ? 32'b1 : 32'b0;
                        3'b100: result = rs1_val ^ sext12(ir[31:20]);
                        3'b110: result = rs1_val | sext12(ir[31:20]);
                        3'b111: result = rs1_val & sext12(ir[31:20]);
                        3'b001: result = rs1_val << ir[24:20];
                        3'b101: result = ir[30] ? $signed(rs1_val) >>> ir[24:20] : rs1_val >> ir[24:20];
                    endcase
                    do_wb = (rd != 0);
                end
                7'b0110011: begin
                    case ({funct7, funct3})
                        {7'b0000000, 3'b000}: result = rs1_val + rs2_val;
                        {7'b0100000, 3'b000}: result = rs1_val - rs2_val;
                        {7'b0000000, 3'b001}: result = rs1_val << rs2_val[4:0];
                        {7'b0000000, 3'b010}: result = ($signed(rs1_val) < $signed(rs2_val)) ? 32'b1 : 32'b0;
                        {7'b0000000, 3'b011}: result = (rs1_val < rs2_val) ? 32'b1 : 32'b0;
                        {7'b0000000, 3'b100}: result = rs1_val ^ rs2_val;
                        {7'b0000000, 3'b101}: result = rs1_val >> rs2_val[4:0];
                        {7'b0100000, 3'b101}: result = $signed(rs1_val) >>> rs2_val[4:0];
                        {7'b0000000, 3'b110}: result = rs1_val | rs2_val;
                        {7'b0000000, 3'b111}: result = rs1_val & rs2_val;
                    endcase
                    do_wb = (rd != 0);
                end
                default: begin
                end
            endcase

            if (do_mem_write) begin
                if (mem_addr == 32'h0003_0004) begin
                    if (!io_buffer_full) begin
                        io_buffer_we <= 1;
                        io_buffer_data <= mem_wdata[7:0];
                    end
                end else if (mem_addr < 32'h0002_0000) begin
                    data_sram_en <= 1;
                    data_sram_addr <= mem_addr;
                    data_sram_wdata <= mem_wdata;
                    data_sram_wen <= mem_wmask;
                    data_addr <= mem_addr;
                    data_wdata <= mem_wdata;
                    data_wen <= mem_wmask;
                end
            end

            if (do_mem_read) begin
                if (mem_addr == 32'h0003_0000) begin
                    result = {24'b0, 8'h00};
                end else if (mem_addr < 32'h0002_0000) begin
                    data_sram_en <= 1;
                    data_sram_addr <= mem_addr;
                    data_addr <= mem_addr;
                    result = load_result(funct3, mem_addr, data_sram_rdata);
                end else begin
                    result = 32'b0;
                end
            end

            if (do_wb && rd != 0) begin
                regs[rd] <= result;
            end
            regs[0] <= 0;
            pc <= next_pc;
        end
    end
endmodule
