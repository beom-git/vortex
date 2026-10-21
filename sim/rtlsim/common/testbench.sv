`include "VX_define.vh"

module testbench (
    input wire clk
);
    localparam NUM_BANKS = `VX_CFG_PLATFORM_MEMORY_NUM_BANKS;
    localparam DATA_SIZE = `VX_CFG_PLATFORM_MEMORY_DATA_SIZE;
    localparam ADDR_WIDTH = `VX_CFG_PLATFORM_MEMORY_ADDR_WIDTH - $clog2(NUM_BANKS);

    import "DPI-C" function void rtlsim_poll(output int command, output int unsigned address,
        output int unsigned data);
    import "DPI-C" function void rtlsim_complete(input int unsigned result);
    import "DPI-C" function void rtlsim_request(input int bank, input bit write,
        input longint unsigned address, input longint unsigned tag,
        input bit [DATA_SIZE-1:0] byteen, input logic [DATA_SIZE*8-1:0] data);
    import "DPI-C" function bit rtlsim_response(input int bank,
        output logic [DATA_SIZE*8-1:0] data, output longint unsigned tag);
    import "DPI-C" function void rtlsim_memory_tick();
    import "DPI-C" function bit rtlsim_stopped();

    logic reset;
    logic start;
    wire busy;
    logic dcr_req_valid;
    logic dcr_req_rw;
    logic [VX_gpu_pkg::VX_DCR_ADDR_WIDTH-1:0] dcr_req_addr;
    logic [VX_gpu_pkg::VX_DCR_DATA_WIDTH-1:0] dcr_req_data;
    wire dcr_rsp_valid;
    wire [VX_gpu_pkg::VX_DCR_DATA_WIDTH-1:0] dcr_rsp_data;

    wire mem_req_valid [NUM_BANKS];
    wire mem_req_rw [NUM_BANKS];
    wire [DATA_SIZE-1:0] mem_req_byteen [NUM_BANKS];
    wire [ADDR_WIDTH-1:0] mem_req_addr [NUM_BANKS];
    wire [DATA_SIZE*8-1:0] mem_req_data [NUM_BANKS];
    wire [63:0] mem_req_tag [NUM_BANKS];
    logic mem_req_ready [NUM_BANKS];
    logic mem_rsp_valid [NUM_BANKS];
    logic [DATA_SIZE*8-1:0] mem_rsp_data [NUM_BANKS];
    logic [63:0] mem_rsp_tag [NUM_BANKS];
    wire mem_rsp_ready [NUM_BANKS];

    rtlsim_shim dut (
        .clk                (clk),
        .reset              (reset),
        .start              (start),
        .busy               (busy),
        .dcr_req_valid      (dcr_req_valid),
        .dcr_req_rw         (dcr_req_rw),
        .dcr_req_addr       (dcr_req_addr),
        .dcr_req_data       (dcr_req_data),
        .dcr_rsp_valid      (dcr_rsp_valid),
        .dcr_rsp_data       (dcr_rsp_data),
        .mem_req_valid      (mem_req_valid),
        .mem_req_rw         (mem_req_rw),
        .mem_req_byteen     (mem_req_byteen),
        .mem_req_addr       (mem_req_addr),
        .mem_req_data       (mem_req_data),
        .mem_req_tag        (mem_req_tag),
        .mem_req_ready      (mem_req_ready),
        .mem_rsp_valid      (mem_rsp_valid),
        .mem_rsp_data       (mem_rsp_data),
        .mem_rsp_tag        (mem_rsp_tag),
        .mem_rsp_ready      (mem_rsp_ready)
    );

    typedef enum {IDLE, RESET_HOLD, RESET_SETTLE, DCR_PULSE, DCR_WAIT,
                  START_PULSE, WAIT_BUSY, RUNNING} state_t;
    state_t state;
    int unsigned cycles;
    bit memory_enabled;
    bit read_command;
    bit sampled_dcr_valid;
    int unsigned sampled_dcr_data;
    bit read_seen;
    int unsigned read_data;
    bit sampled_busy;
    bit accepted [NUM_BANKS];

    initial begin
        reset = 1;
        start = 0;
        dcr_req_valid = 0;
        dcr_req_rw = 0;
        dcr_req_addr = '0;
        dcr_req_data = '0;
        state = IDLE;
        cycles = 0;
        memory_enabled = 0;
        read_command = 0;
        sampled_dcr_valid = 0;
        sampled_dcr_data = 0;
        read_seen = 0;
        read_data = 0;
        sampled_busy = 0;
        for (int b = 0; b < NUM_BANKS; ++b) begin
            mem_req_ready[b] = 0;
            mem_rsp_valid[b] = 0;
            mem_rsp_data[b] = '0;
            mem_rsp_tag[b] = '0;
            accepted[b] = 0;
        end
    end

    // Sample the transaction consumed at this edge, before DUT nonblocking updates.
    always @(posedge clk) begin
        if (memory_enabled) begin
            if ($isunknown(busy) || $isunknown(dcr_rsp_valid)) begin
                $fatal(1, "rtlsim: unknown control signal");
            end
            sampled_busy <= busy;
            sampled_dcr_valid <= dcr_rsp_valid;
            if (dcr_rsp_valid && read_command) begin
                if ($isunknown(dcr_rsp_data)) begin
                    $fatal(1, "rtlsim: unknown DCR response");
                end
                sampled_dcr_data <= dcr_rsp_data;
            end
            for (int b = 0; b < NUM_BANKS; ++b) begin
                if ($isunknown(mem_req_valid[b]) ||
                    (mem_rsp_valid[b] && $isunknown(mem_rsp_ready[b]))) begin
                    $fatal(1, "rtlsim: unknown memory handshake at bank %0d", b);
                end
                accepted[b] <= mem_rsp_valid[b] && mem_rsp_ready[b];
                if (mem_req_valid[b] && mem_req_ready[b]) begin
                    if ($isunknown({mem_req_rw[b], mem_req_addr[b], mem_req_tag[b]}) ||
                        (mem_req_rw[b] && $isunknown(mem_req_byteen[b]))) begin
                        $fatal(1, "rtlsim: unknown memory request at bank %0d", b);
                    end
                    rtlsim_request(b, mem_req_rw[b], 64'(mem_req_addr[b]),
                        mem_req_tag[b], mem_req_byteen[b], mem_req_data[b]);
                end
            end
            rtlsim_memory_tick();
        end
    end

    // Drive only on falling edges. A completed DRAM read is not an accepted bus response.
    always @(negedge clk) begin : drive
        int command;
        int unsigned address;
        int unsigned data;
        bit response_valid;
        logic [DATA_SIZE*8-1:0] response_data;
        longint unsigned response_tag;
        if (memory_enabled) begin
            for (int b = 0; b < NUM_BANKS; ++b) begin
                if (accepted[b]) begin
                    mem_rsp_valid[b] <= 0;
                end
                if (!mem_rsp_valid[b] || accepted[b]) begin
                    response_valid = rtlsim_response(b, response_data, response_tag);
                    mem_rsp_valid[b] <= response_valid;
                    if (response_valid) begin
                        mem_rsp_data[b] <= response_data;
                        mem_rsp_tag[b] <= response_tag;
                    end
                end
            end
        end
        if (state == DCR_WAIT && read_command && sampled_dcr_valid) begin
            read_seen <= 1;
            read_data <= sampled_dcr_data;
        end
        case (state)
            IDLE: begin
                rtlsim_poll(command, address, data);
                cycles <= 0;
                case (command)
                    0: begin end
                    1: begin
                        reset <= 1;
                        state <= RESET_HOLD;
                    end
                    2, 3: begin
                        if (address >= (1 << VX_gpu_pkg::VX_DCR_ADDR_WIDTH)) begin
                            $fatal(1, "rtlsim: DCR address out of range");
                        end
                        dcr_req_valid <= 1;
                        dcr_req_rw <= (command == 2);
                        dcr_req_addr <= VX_gpu_pkg::VX_DCR_ADDR_WIDTH'(address);
                        dcr_req_data <= data;
                        read_command <= (command == 3);
                        read_seen <= 0;
                        state <= DCR_PULSE;
                    end
                    4: begin
                        start <= 1;
                        state <= START_PULSE;
                    end
                    default: begin
                        $fatal(1, "rtlsim: invalid command %0d", command);
                    end
                endcase
            end
            RESET_HOLD: begin
                cycles <= cycles + 1;
                if (cycles + 1 == `VX_CFG_RESET_DELAY) begin
                    reset <= 0;
                    cycles <= 1;
                    state <= RESET_SETTLE;
                end
            end
            RESET_SETTLE: begin
                cycles <= cycles + 1;
                if (cycles + 1 >= `VX_CFG_RESET_DELAY) begin
                    memory_enabled <= 1;
                    for (int b = 0; b < NUM_BANKS; ++b) begin
                        mem_req_ready[b] <= 1;
                    end
                    state <= IDLE;
                    rtlsim_complete(0);
                end
            end
            DCR_PULSE: begin
                dcr_req_valid <= 0;
                state <= read_command ? DCR_WAIT : IDLE;
                if (!read_command) begin
                    rtlsim_complete(0);
                end
            end
            DCR_WAIT: begin
                if (!read_command || read_seen || sampled_dcr_valid) begin
                    read_command <= 0;
                    state <= IDLE;
                    rtlsim_complete(sampled_dcr_valid ? sampled_dcr_data : read_data);
                end
            end
            START_PULSE: begin
                start <= 0;
                state <= WAIT_BUSY;
            end
            WAIT_BUSY: begin
                cycles <= cycles + 1;
                if (sampled_busy) begin
                    state <= RUNNING;
                end else if (cycles + 1 == 100000 || rtlsim_stopped()) begin
                    state <= IDLE;
                    rtlsim_complete(0);
                end
            end
            RUNNING: begin
                if (!sampled_busy || rtlsim_stopped()) begin
                    state <= IDLE;
                    rtlsim_complete(0);
                end
            end
            default: begin
                $fatal(1, "rtlsim: invalid state");
            end
        endcase
    end
endmodule
