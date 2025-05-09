module axi_stream_processor #(
    parameter TDATA_WIDTH = 32,  // AXI-Stream data width (32 or 64 bits)
    parameter MODE_WIDTH = 2     // Mode selection width (0: pass-through, 1: byte reversal, 2: add constant)
) (
    // Clock and reset
    input  wire                     aclk,
    input  wire                     aresetn,

    // AXI-Stream Slave Interface
    input  wire [TDATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [TDATA_WIDTH/8-1:0] s_axis_tkeep,
    input  wire                     s_axis_tvalid,
    input  wire                     s_axis_tlast,
    output wire                     s_axis_tready,

    // AXI-Stream Master Interface
    output wire [TDATA_WIDTH-1:0]   m_axis_tdata,
    output wire [TDATA_WIDTH/8-1:0] m_axis_tkeep,
    output wire                     m_axis_tvalid,
    output wire                     m_axis_tlast,
    input  wire                     m_axis_tready,

    // AXI-Lite Control Interface (simplified)
    input  wire [MODE_WIDTH-1:0]    mode,           // Mode: 0=pass-through, 1=byte reverse, 2=add constant
    input  wire [TDATA_WIDTH-1:0]   constant_value  // Constant to add in mode 2
);

    // Internal signals
    reg [TDATA_WIDTH-1:0]   tdata_reg;
    reg [TDATA_WIDTH/8-1:0] tkeep_reg;
    reg                     tvalid_reg;
    reg                     tlast_reg;
    reg                     tready_reg;

    // Byte reversal function
    function [TDATA_WIDTH-1:0] reverse_bytes;
        input [TDATA_WIDTH-1:0] data;
        integer i;
        begin
            for (i = 0; i < TDATA_WIDTH/8; i = i + 1) begin
                reverse_bytes[8*i +: 8] = data[8*(TDATA_WIDTH/8-1-i) +: 8];
            end
        end
    endfunction

    // Data processing logic
    always @(*) begin
        case (mode)
            2'd0: tdata_reg = s_axis_tdata;                    // Mode 0: Pass-through
            2'd1: tdata_reg = reverse_bytes(s_axis_tdata);     // Mode 1: Byte reversal
            2'd2: tdata_reg = s_axis_tdata + constant_value;   // Mode 2: Add constant
            default: tdata_reg = s_axis_tdata;                 // Default: Pass-through
        endcase
    end

    // AXI-Stream pipeline and backpressure handling
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            tvalid_reg <= 1'b0;
            tready_reg <= 1'b1;  // Ready to accept data after reset
            tkeep_reg  <= 1'b0;
            tlast_reg  <= 1'b0;
        end else begin
            // Backpressure: Only process when downstream is ready
            if (m_axis_tready || !tvalid_reg) begin
                if (s_axis_tvalid && tready_reg) begin
                    tvalid_reg <= 1'b1;
                    tkeep_reg  <= s_axis_tkeep;
                    tlast_reg  <= s_axis_tlast;
                    tready_reg <= 1'b1;  // Keep ready unless downstream stalls
                end else begin
                    tvalid_reg <= 1'b0;
                    tready_reg <= 1'b1;
                end
            end
        end
    end

    // Output assignments
    assign m_axis_tdata  = tdata_reg;
    assign m_axis_tkeep  = tkeep_reg;
    assign m_axis_tvalid = tvalid_reg;
    assign m_axis_tlast  = tlast_reg;
    assign s_axis_tready = tready_reg;

endmodule
