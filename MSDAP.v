module MSDAP(Sclk, Dclk, Start, Reset_n, Frame, InputL, InputR, InReady, OutReady, OutputL, OutputR);
    input Sclk, Dclk, Start, Reset_n, Frame, InputL, InputR;
    output InReady;
    output reg OutReady;
    output [39:0] OutputL, OutputR;
 
    wire [39:0] outL, outR;
    wire [15:0] dataL, dataR;
    wire [9:0] incount;
    reg [3:0] state;
    wire datavalid, disableclk, dataoutL, dataoutR, hasdata, started, firclk;
    wire start;
    reg rst, collecting, validnc, comp, starting, rstcount;

    assign firclk = Sclk & !disableclk;
    FIR firL(dataL, datavalid, firclk, rst, start, comp, outL, dataoutL);
    FIR firR(dataR, datavalid, firclk, rst, start, comp, outR, dataoutR);
    DFF40 outdffL(outL, dataoutL, rst, OutputL);
    DFF40 outdffR(outR, dataoutR, rst, OutputR);
    assign InReady = state > 0 && !disableclk;
    
    IO io(Dclk, start, Reset_n, rstcount, Frame, InputL, InputR, dataL, dataR, incount, datavalid, disableclk, hasdata);

    always @(posedge Sclk or negedge Start or posedge Reset_n) begin
        if(Reset_n) begin
            rst <= 1;
        end
        else if(!Start) begin
            starting <= 1;
            rst <= 0;
        end
    end

    DFF1 startdff(starting, Sclk, Start, started);
    assign start = !Start && !started;

    always @(posedge Sclk or posedge start or posedge Reset_n) begin
        if(start) begin
            OutReady <= 0;
            comp <= 0;
        end
        else if(Reset_n) begin
            OutReady <= 0;
            comp <= 0;
        end
        else begin
            if(dataoutL && dataoutR && state == 6 && comp) begin
                OutReady <= 1;
                comp <= 0;
            end
            else if(state == 6 && datavalid && !comp && hasdata && !disableclk) begin
                OutReady <= 0;
                comp <= 1;
            end
        end
    end

    always @(posedge Sclk or posedge start or posedge Reset_n) begin
        if(start) begin
            state <= 1;
            rstcount <= 0;
        end
        else if(Reset_n) begin
            state <= 5;
            rstcount <= 0;
        end
        else begin
            if(state == 1 && Frame) begin
                state <= 2;
                rstcount <= 1;
            end
            else if(state == 2 && incount == 16) begin
                state <= 3;
                rstcount <= 1;
            end
            else if(state == 3 && Frame) begin
                state <= 4;
                rstcount <= 1;
            end
            else if(state == 4 && incount == 512) begin
                state <= 5;
                rstcount <= 1;
            end
            else if(state == 5 && Frame) begin
                state <= 6;
                rstcount <= 1;
            end
            else begin
                rstcount <= 0;
            end
        end
    end
endmodule

module IO(clk, start, rst, rstcount, frame, inL, inR, outL, outR, incount, datavalid, disableclk, hasdata);
    input clk, start, rst, rstcount, frame, inL, inR;
    output reg [15:0] outL, outR;
    output reg [9:0] incount;
    output reg datavalid, hasdata;
    output disableclk;

    reg [9:0] zerocounter;
    reg [3:0] index;
    reg collecting, framerec, validnc;

    assign disableclk = zerocounter == 800;

    always @(posedge clk or posedge start or posedge rst or posedge rstcount or posedge frame) begin
        if(start) begin
            zerocounter <= 0;
            framerec <= 0;
            datavalid <= 0;
            incount <= 0;
            hasdata <= 0;
        end
        else if(rst) begin
            zerocounter <= 0;
            framerec <= 0;
            datavalid <= 0;
            incount <= 0;
            hasdata <= 0;
        end
        else if(rstcount) begin
            incount <= 0;
            zerocounter <= 0;
            hasdata <= 0;
        end
        else if(frame) begin
            framerec <= 1;
        end
        else begin
            framerec <= 0;
            if(validnc) begin
                if(outL == 0 && outR == 0 && zerocounter != 800) begin
                    zerocounter <= zerocounter + 1;
                end
                else if(outL != 0 || outR != 0) begin
                    zerocounter <= 0;
                end
                incount <= incount + 1;
                datavalid <= 1;
                hasdata <= 1;
            end
            else begin
                datavalid <= 0;
            end
        end
    end

    always @(negedge clk or posedge start or posedge rst) begin
        if(start) begin
            collecting <= 0;
            outL <= 0;
            outR <= 0;
            validnc <= 0;
            index <= 15;
        end
        else if(rst) begin
            collecting <= 0;
            outL <= 0;
            outR <= 0;
            validnc <= 0;
            index <= 15;
        end
        else begin
            if(framerec)
                collecting <= 1;
            if(collecting || framerec) begin
                outL[index] <= inL;
                outR[index] <= inR;
                index <= index - 1;
            end
            if(index == 0) begin
                validnc <= 1;
            end
            else begin
                validnc <= 0;
            end
        end
    end
endmodule

module FIR(x, datain, clk, rst, start, comp, out, dataout);
    input [15:0] x;
    input datain, clk, rst, start, comp;
    output [39:0] out;
    output dataout;

    parameter ORDER = 256;
    reg [10:0] count;
    reg [8:0] C [511:0];
    reg [15:0] X [(ORDER - 1):0];
    reg [7:0] Rj [15:0];
    reg r, c;
    integer i;

    always @(posedge datain or posedge start or posedge rst) begin
        if(start) begin
            r <= 0;
            c <= 0;
            count <= 0;
            for(i = 0; i < ORDER; i = i + 1)
                X[i] <= 0;
        end
        else if(rst) begin
            for(i = 0; i < ORDER; i = i + 1)
                X[i] <= 0;
        end
        else if(!rst) begin
            if(!r) begin
                Rj[count] <= x[7:0];
                count <= count + 1;
                if(count == 15) begin
                    r <= 1;
                    count <= 0;
                end
            end
            else if(!c) begin
                C[count] <= x[8:0];
                count <= count + 1;
                if(count == 511) begin
                    c <= 1;
                end
            end
            else if(c) begin
                for(i = 1; i < ORDER; i = i + 1)
                    X[i - 1] <= X[i];
                X[(ORDER - 1)] <= x;
            end
        end
    end

    wire [39:0] mux3out, outshift;
    wire [24:0] sum;
    wire [23:0] mux1out, mux2out, accout;
    wire [15:0] xxor;
    wire [9:0] Csel, srjout;
    wire [7:0] rj, negcoeff, xindex, isneg;
    wire [3:0] rjsel;
    wire [1:0] mux2sel;
    wire coeffcarryin, accclk, accrst, rjclk, rjm1clk, mux1sel, muxcsel, muxcout, eqz, accreset, mux3sel, outclk, reset, restart;

    assign negcoeff = ~(C[Csel][7:0]);
    assign xindex = 8'hff & negcoeff;
    assign coeffcarryin = C[Csel][8];
    
    XOR_1_16 muxxoutxor(coeffcarryin, X[xindex], xxor); 

    //Counter10 SRjm1(rjm1clk, restart, Csel);
    Counter10_e SRjm1(!clk, rjm1clkenable, restart, rst | start, Csel);
    
    //DFF10 SRj(sum[9:0], rjclk, restart, srjout);
    DFF10_e SRj(sum[9:0], !clk, rjclkenable, restart, rst | start, srjout);

    //Counter4 Rjno(rjnoclk, restart, rjsel);
    Counter4_e Rjno(!clk, rjnoclkenable, restart, rst | start, rjsel);
    
    assign isneg = xxor[15] ? 8'hff : 8'h00;
    Mux2_24 mux1(accout, {16'h0000, Rj[rjsel]}, mux1sel, mux1out);
    Mux4_24 mux2({isneg, xxor}, 24'h000000, {14'h0000, srjout}, out[39:16], mux2sel, mux2out);
    
    Mux2_1 muxc(coeffcarryin, 1'b0, muxcsel, muxcout);

    Adder24 add(mux1out, mux2out, muxcout, sum);
    
    assign accrst = restart | accreset;
    //DFF24 acc(sum[23:0], accclk, accrst, accout);
    DFF24_e acc(sum[23:0], !clk, accclkenable, accrst, rst | start, accout);

    FastEQ10 feq(Csel, srjout, eqz);
    
    Mux2_40 mux3({sum[23:0], out[15:0]}, outshift, mux3sel, mux3out);
    //DFF40 outdff(mux3out, outclk, restart, out);
    DFF40_e outdff(mux3out, clk, outclkenable, restart, rst | start, out);
    Shifter40 shifter(out, outshift);
    
    StateMachine sm(clk, rst, start, comp, eqz, rjsel, mux1sel, mux2sel, mux3sel, muxcsel, rjm1clkenable, rjclkenable, rjnoclkenable, accclkenable, accreset, outclkenable, dataout, reset);

    DFF1 resetpulse(reset, !clk, start | rst, hasreset);
    DFF1 resetpulse2(reset, clk, start | rst, hasresetd);

    assign restart = rst | (reset & !hasresetd);
endmodule

module StateMachine(clk, rst, start, comp, eqz, rjno, mux1sel, mux2sel, mux3sel, muxcsel, rjm1clkenable, rjclkenable, rjnoclkenable, accclkenable, accreset, outclkenable, dataout, reset);
    input clk, rst, start, comp, eqz;
    input [3:0] rjno;
    output mux1sel, mux3sel, muxcsel, rjclkenable, rjnoclkenable, rjm1clkenable, accclkenable, outclkenable, dataout, accreset, reset;
    output [1:0] mux2sel;

    reg [2:0] pstate, nstate;
    parameter A = 0;
    parameter B = 1;
    parameter C = 2;
    parameter D = 3;
    parameter E = 4;
    parameter F = 5;
    parameter G = 6;

    assign reset = pstate == G;
    assign dataout = pstate == F;
    assign accclkenable = pstate == C;
    assign outclkenable = pstate == D || pstate == E;
    assign rjm1clkenable = pstate == C;
    assign rjnoclkenable = pstate == B || (pstate == E && rjno != 0);
    assign rjclkenable = pstate == B || (pstate == E && rjno != 0);
    assign mux1sel = pstate == B || (pstate == E && rjno != 0);
    assign mux2sel[0] = pstate == D;
    assign mux2sel[1] = pstate == B || pstate == D || (pstate == E && rjno != 0);
    assign muxcsel = pstate == B || pstate == D || pstate == E;
    assign mux3sel = pstate == E;
    assign accreset = pstate == B || (pstate == E && rjno != 0);

    always @(posedge clk or posedge start or posedge rst) begin
        if(start) begin
            pstate <= A;
            nstate <= A;
        end
        else if(rst) begin
            pstate <= A;
            nstate <= A;
        end
        else if(comp) begin
            if(eqz && pstate == C) begin
                pstate <= D;
                nstate <= E;
            end
            else begin
                case(nstate)
                    A: begin
                        nstate <= B;
                    end
                    B: begin
                        nstate <= C;
                    end
                    C: begin
                        if(eqz) begin
                            nstate <= D;
                        end
                        else begin
                            nstate <= C;
                        end
                    end
                    D: begin
                        nstate <= E;
                    end
                    E: begin
                        if(rjno == 0 && eqz) begin
                            nstate <= F;
                        end
                        else begin
                            nstate <= C;
                        end
                    end
                    F: begin
                        nstate <= G;
                    end
                    G: begin
                        nstate <= B;
                    end
                    default: begin
                        nstate <= B;
                    end
                endcase
                pstate <= nstate;
            end
        end
    end
endmodule

module FastEQ10(one, two, out);
    input [9:0] one, two;
    output out;

    assign out = &(one | ~two);
endmodule

module DFF1(in, clk, rst, out);//1-bit D-flip flop
    input in;
    input clk, rst;
    output reg out;

    always @(posedge clk or posedge rst) begin
        if(rst)
            out <= 0;
        else
            out <= in;
    end
endmodule

module DFF4(in, clk, rst, out);//4-bit D-flip flop
    input [3:0] in;
    input clk, rst;
    output reg [3:0] out;

    always @(posedge clk or posedge rst) begin
        if(rst)
            out <= 0;
        else
            out <= in;
    end
endmodule

module Counter4(clk, rst, out);
    input clk, rst;
    output reg [3:0] out;

    always @(posedge clk or posedge rst) begin
        if(rst)
            out <= 0;
        else
            out <= out + 1;
    end
endmodule

module Counter4_e(clk, enable, rst, arst, out);
    input clk, enable, rst, arst;
    output reg [3:0] out;

    always @(posedge clk or posedge arst) begin
        if(arst)
            out <= 0;
        else if(rst)
            out <= 0;
        else if(enable)
            out <= out + 1;
    end
endmodule

module DFF10(in, clk, rst, out);//10-bit D-flip flop
    input [9:0] in;
    input clk, rst;
    output reg [9:0] out;

    always @(posedge clk or posedge rst) begin
        if(rst)
            out <= 0;
        else
            out <= in;
    end
endmodule

module DFF10_e(in, clk, enable, rst, arst, out);//10-bit D-flip flop
    input [9:0] in;
    input clk, enable, rst, arst;
    output reg [9:0] out;

    always @(posedge clk or posedge arst) begin
        if(arst)
            out <= 0;
        else if(rst)
            out <= 0;
        else if(enable)
            out <= in;
    end
endmodule

module Counter10(clk, rst, out);
    input clk, rst;
    output reg [9:0] out;

    always @(posedge clk or posedge rst) begin
        if(rst)
            out <= 0;
        else
            out <= out + 1;
    end
endmodule

module Counter10_e(clk, enable, rst, arst, out);
    input clk, enable, rst, arst;
    output reg [9:0] out;

    always @(posedge clk or posedge arst) begin
        if(arst)
            out <= 0;
        else if(rst)
            out <= 0;
        else if(enable)
            out <= out + 1;
    end
endmodule

module DFF11(in, clk, rst, out);//11-bit D-flip flop
    input [10:0] in;
    input clk, rst;
    output reg [10:0] out;

    always @(posedge clk or posedge rst) begin
        if(rst)
            out <= 0;
        else
            out <= in;
    end
endmodule

module DFF16(in, clk, rst, out);//16-bit D-flip flop
    input [15:0] in;
    input clk, rst;
    output reg [15:0] out;

    always @(posedge clk or posedge rst) begin
        if(rst)
            out <= 0;
        else
            out <= in;
    end
endmodule

module DFF24(in, clk, rst, out);//24-bit D-flip flop
    input [23:0] in;
    input clk, rst;
    output reg [23:0] out;

    always @(posedge clk or posedge rst) begin
        if(rst)
            out <= 0;
        else
            out <= in;
    end
endmodule

module DFF24_e(in, clk, enable, rst, arst, out);//24-bit D-flip flop
    input [23:0] in;
    input clk, enable, rst, arst;
    output reg [23:0] out;

    always @(posedge clk or posedge arst) begin
        if(arst)
            out <= 0;
        else if(rst)
            out <= 0;
        else if(enable)
            out <= in;
    end
endmodule

module DFF40(in, clk, rst, out);//40-bit D-flip flop
    input [39:0] in;
    input clk, rst;
    output reg [39:0] out;

    always @(posedge clk or posedge rst) begin
        if(rst)
            out <= 0;
        else
            out <= in;
    end
endmodule

module DFF40_e(in, clk, enable, rst, arst, out);//40-bit D-flip flop
    input [39:0] in;
    input clk, enable, rst, arst;
    output reg [39:0] out;

    always @(posedge clk or posedge arst) begin
        if(arst)
            out <= 0;
        else if(rst)
            out <= 0;
        else if(enable)
            out <= in;
    end
endmodule

module Mux2_1(one, two, sel, out);
    input one, two;
    input sel;
    output reg out;

    always @* begin
        case(sel)
            0: out <= one;
            1: out <= two;
        endcase
    end
endmodule

module Mux2_16(one, two, sel, out);
    input [15:0] one, two;
    input sel;
    output reg [15:0] out;

    always @* begin
        case(sel)
            0: out <= one;
            1: out <= two;
        endcase
    end
endmodule

module Mux2_24(one, two, sel, out);
    input [23:0] one, two;
    input sel;
    output reg [23:0] out;

    always @* begin
        case(sel)
            0: out <= one;
            1: out <= two;
        endcase
    end
endmodule

module Mux2_40(one, two, sel, out);
    input [39:0] one, two;
    input sel;
    output reg [39:0] out;

    always @* begin
        case(sel)
            0: out <= one;
            1: out <= two;
        endcase
    end
endmodule

module Mux4_40(one, two, three, four, sel, out);
    input [39:0] one, two, three, four;
    input [1:0] sel;
    output reg [39:0] out;

    always @* begin
        case(sel)
            2'b00: out <= one;
            2'b01: out <= two;
            2'b10: out <= three;
            2'b11: out <= four;
        endcase
    end
endmodule

module Mux4_16(one, two, three, four, sel, out);
    input [15:0] one, two, three, four;
    input [1:0] sel;
    output reg [15:0] out;

    always @* begin
        case(sel)
            2'b00: out <= one;
            2'b01: out <= two;
            2'b10: out <= three;
            2'b11: out <= four;
        endcase
    end
endmodule

module Mux4_24(one, two, three, four, sel, out);
    input [23:0] one, two, three, four;
    input [1:0] sel;
    output reg [23:0] out;

    always @* begin
        case(sel)
            2'b00: out <= one;
            2'b01: out <= two;
            2'b10: out <= three;
            2'b11: out <= four;
        endcase
    end
endmodule

module Mux4_1(one, two, three, four, sel, out);
    input one, two, three, four;
    input [1:0] sel;
    output reg out;

    always @* begin
        case(sel)
            2'b00: out <= one;
            2'b01: out <= two;
            2'b10: out <= three;
            2'b11: out <= four;
        endcase
    end
endmodule

module Adder24(a, b, cin, s);
    input [23:0] a, b;
    input cin;
    output [24:0] s;

    assign s = a + b + cin;
endmodule

module Shifter40(in, out);
    input [39:0] in;
    output [39:0] out;

    assign out[38:0] = in[39:1];
    assign out[39] = in[39];
endmodule

module XOR_1_16(one, two, out);
    input one;
    input [15:0] two;
    output [15:0] out;

    assign out = one ? ~two : two;
endmodule
