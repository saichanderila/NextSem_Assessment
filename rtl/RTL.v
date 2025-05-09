module axi_stream_processor_tb;
    // Parameters
    parameter TDATA_WIDTH = 32;
    parameter CLK_PERIOD = 10;
    parameter MAX_PACKET_LEN = 10;

    // Signals
    reg clk, aresetn;
    
    // AXI-Stream signals
    reg [TDATA_WIDTH-1:0] s_axis_tdata;
    reg [TDATA_WIDTH/8-1:0] s_axis_tkeep;
    reg s_axis_tlast;
    reg s_axis_tvalid;
    wire s_axis_tready;
    
    wire [TDATA_WIDTH-1:0] m_axis_tdata;
    wire [TDATA_WIDTH/8-1:0] m_axis_tkeep;
    wire m_axis_tlast;
    wire m_axis_tvalid;
    reg m_axis_tready;
    
    // Control signals (now direct registers instead of AXI-Lite)
    reg [1:0] mode;
    reg [TDATA_WIDTH-1:0] constant_value;

    // Instantiate DUT
    axi_stream_processor #(
        .TDATA_WIDTH(TDATA_WIDTH)
    ) dut (
        .aclk(clk),
        .aresetn(aresetn),
        
        // AXI-Stream inputs
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        
        // AXI-Stream outputs
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        
        // Control signals
        .mode(mode),
        .constant_value(constant_value)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test procedure
    initial begin
        // Initialize signals
        aresetn = 0;
        s_axis_tdata = 0;
        s_axis_tkeep = {(TDATA_WIDTH/8){1'b1}};
        s_axis_tlast = 0;
        s_axis_tvalid = 0;
        m_axis_tready = 1;
        mode = 0;
        constant_value = 0;

        // Reset
        #20 aresetn = 1;

        // Test Mode 0: Pass-through
        $display("Testing Mode 0: Pass-through...");
        mode = 0;
        send_packet(32'h12345678, 1);
        
        // Test Mode 1: Byte reversal
        $display("Testing Mode 1: Byte reversal...");
        mode = 1;
        send_packet(32'h12345678, 1); // Expect 32'h78563412
        
        // Test Mode 2: Add constant
        $display("Testing Mode 2: Add constant...");
        mode = 2;
        constant_value = 32'h00000005;
        send_packet(32'h12345678, 1); // Expect 32'h1234567D
        
        // Test overflow case
        constant_value = 32'hFFFFFFFF;
        send_packet(32'hFFFFFFFF, 1); // Expect overflow
        
        // Test reset during transaction
        $display("Testing reset during transaction...");
        fork
            begin
                send_packet(32'h12345678, 0);
                #10 aresetn = 0;
                #20 aresetn = 1;
            end
            begin
                apply_backpressure(3);
            end
        join

        // Test partial TKEEP
        $display("Testing partial TKEEP...");
        mode = 0;
        s_axis_tkeep = 4'b1100; // Only first two bytes valid
        send_packet(32'hAABBCCDD, 1);
        s_axis_tkeep = {(TDATA_WIDTH/8){1'b1}}; // Restore TKEEP

        // Test invalid mode
        $display("Testing invalid mode...");
        mode = 3; // Invalid mode, should default to pass-through
        send_packet(32'h12345678, 1);

        #100 $display("Test completed.");
        $finish;
    end

    // Task to send AXI-Stream packet
    task send_packet(input [TDATA_WIDTH-1:0] data, input last);
        begin
            @(posedge clk);
            s_axis_tdata = data;
            s_axis_tlast = last;
            s_axis_tvalid = 1;
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
            s_axis_tvalid = 0;
            s_axis_tlast = 0;
            $display("Sent packet: tdata=%h, tkeep=%h, tlast=%b", data, s_axis_tkeep, last);
        end
    endtask

    // Task to apply backpressure
    task apply_backpressure(input integer cycles);
        begin
            m_axis_tready = 0;
            repeat (cycles) @(posedge clk);
            m_axis_tready = 1;
            $display("Applied backpressure for %0d cycles", cycles);
        end
    endtask

    // Monitor output
    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            $display("Output: tdata=%h, tkeep=%h, tlast=%b", m_axis_tdata, m_axis_tkeep, m_axis_tlast);
        end
    end

endmodule
