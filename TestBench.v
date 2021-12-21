//`include "MSDAP.v"
`include "netlist.v"
`timescale 1ns/1ps

module TestBench;
    reg [20:0] count;
    reg [128 * 8-1:0] str;
    reg [8 * 8-1:0] temp4;
    reg r;
    integer fd;
    reg [8:0] CL [511:0];
    reg [8:0] CR [511:0];
    reg [15:0] XL [6999:0];
    reg [15:0] XR [6999:0];
    reg rst [6999:0];
    reg [7:0] RjL [15:0];
    reg [7:0] RjR [15:0];
    reg [15:0] temp1, temp2, temp3;
    reg [39:0] out;
    integer i, j, outfd;
    reg Sclk, Dclk, Start, Reset, Frame, InputL, InputR;
    wire InReady, OutReady;
    wire [39:0] OutputL, OutputR;

    MSDAP msdap(Sclk, Dclk, Start, Reset, Frame, InputL, InputR, InReady, OutReady, OutputL, OutputR);

    parameter DATACLK = 1302;
    always #38 Sclk = ~Sclk;
    always #DATACLK Dclk = ~Dclk;

    initial begin
        /*$dumpfile("waves.vcd");
        $dumpvars;*/
        fd = $fopen("data1.in", "r");
        if(!fd)
            $display("could not open file");
        r = $fgets(str, fd);
        r = $fgets(str, fd);
        r = $fgets(str, fd);
        r = $fgets(str, fd);
        count = 0;

        repeat(16) begin
            r = $fgets(str, fd);

            r = $sscanf(str, "%h %h", RjL[count], RjR[count]);
            count = count + 1;
        end

        count = 0;
        r = $fgets(str, fd);
        r = $fgets(str, fd);

        repeat(512) begin
            r = $fgets(str, fd);

            r = $sscanf(str, "%h %h", CL[count], CR[count]);
            //$display("%h", C[count]);
            count = count + 1;
            
        end

        r = $fgets(str, fd);
        r = $fgets(str, fd);

        count = 0;
        repeat(7000) begin
            r = $fgets(str, fd);
            r = $sscanf(str, "%h %h //%d : %s", temp1, temp2, temp3, temp4);
            if(temp4 == "reset") begin
                temp4 = 0;
                rst[count] = 1;
            end
            else
                rst[count] = 0;

            XL[count] = temp1;
            XR[count] = temp2;
            count = count + 1;
        end

        count = 0;
        out <= 0;
        Start <= 1;
        Reset <= 0;
        Frame <= 0;
        InputL <= 0;
        InputR <= 0;
        Sclk <= 0;
        Dclk <= 0;
        #(38 * 8);
        /*Reset <= 0;
        #38;*/
        #13;
        Start <= 0;
        #38;
        while(!InReady)
            #1;

        while(Dclk == 1)
            #1;
        while(Dclk == 0)
            #1;

        i = 0;
	outfd = $fopen("out.txt", "w");
        repeat(16) begin
            j = 15;
            Frame <= 1;
            repeat(16) begin
                if(j > 7) begin
                    InputL <= 0;
                    InputR <= 0;
                end
                else begin
                    InputL <= RjL[i][j];
                    InputR <= RjR[i][j];
                end
                #(2 * DATACLK);
                Frame <= 0;
                j = j - 1;
            end
            i = i + 1;
        end

        i = 0;
        repeat(512) begin
            j = 15;
            Frame <= 1;
            repeat(16) begin
                if(j > 8) begin
                    InputL <= 0;
                    InputR <= 0;
                end
                else begin
                    InputL <= CL[i][j];
                    InputR <= CR[i][j];
                end
                #(2 * DATACLK);
                Frame <= 0;
                j = j - 1;
            end
            i = i + 1;
        end

        i = 0;
        repeat(7000) begin
            j = 15;
            Frame <= 1;
            repeat(16) begin
                InputL <= XL[i][j];
                InputR <= XR[i][j];
                if(j == 13 && rst[i])
                    Reset <= 1;
                #(2 * DATACLK);
                Reset <= 0;
                Frame <= 0;
                j = j - 1;
            end
            i = i + 1;

        end

	$fclose(outfd);
        $finish;
    end

    integer prevtime = 0;
    always @(negedge OutReady) begin
        $display("%h %h %d %d %d", OutputL, OutputR, count, $time, $time - prevtime);
        $fdisplay(outfd, "%h %h | %h %h | //%d", OutputL, OutputR, OutputL, OutputR, count);
        prevtime = $time;
        count = count + 1;
    end
endmodule
