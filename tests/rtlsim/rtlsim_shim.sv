// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "VX_define.vh"

module rtlsim_shim import VX_gpu_pkg::*; #(
    parameter MEM_DATA_WIDTH = (`VX_CFG_PLATFORM_MEMORY_DATA_SIZE * 8),
    parameter VX_CFG_MEM_ADDR_WIDTH = `VX_CFG_PLATFORM_MEMORY_ADDR_WIDTH - $clog2(`VX_CFG_PLATFORM_MEMORY_NUM_BANKS),
    parameter MEM_NUM_BANKS  = `VX_CFG_PLATFORM_MEMORY_NUM_BANKS,
    parameter MEM_TAG_WIDTH  = 64
) (
    `SCOPE_IO_DECL

    // Clock
    input  wire                             clk,
    input  wire                             reset,

    // Memory request
    output wire                             mem_req_valid [MEM_NUM_BANKS],
    output wire                             mem_req_rw [MEM_NUM_BANKS],
    output wire [(MEM_DATA_WIDTH/8)-1:0]    mem_req_byteen [MEM_NUM_BANKS],
    output wire [VX_CFG_MEM_ADDR_WIDTH-1:0]        mem_req_addr [MEM_NUM_BANKS],
    output wire [MEM_DATA_WIDTH-1:0]        mem_req_data [MEM_NUM_BANKS],
    output wire [MEM_TAG_WIDTH-1:0]         mem_req_tag [MEM_NUM_BANKS],
    input  wire                             mem_req_ready [MEM_NUM_BANKS],

    // Memory response
    input wire                              mem_rsp_valid [MEM_NUM_BANKS],
    input wire [MEM_DATA_WIDTH-1:0]         mem_rsp_data [MEM_NUM_BANKS],
    input wire [MEM_TAG_WIDTH-1:0]          mem_rsp_tag [MEM_NUM_BANKS],
    output wire                             mem_rsp_ready [MEM_NUM_BANKS],

    // DCR write/read request
    input  wire                             dcr_req_valid,
    input  wire                             dcr_req_rw,
    input  wire [VX_DCR_ADDR_WIDTH-1:0]     dcr_req_addr,
    input  wire [VX_DCR_DATA_WIDTH-1:0]     dcr_req_data,

    // DCR read response
    output wire                             dcr_rsp_valid,
    output wire [VX_DCR_DATA_WIDTH-1:0]     dcr_rsp_data,

    // ctrl/status
    input  wire                             start,
    output wire                             busy
);
    int unsigned count;
    logic running;
    int unsigned received [MEM_NUM_BANKS];
    bit held_valid [MEM_NUM_BANKS];
    logic [MEM_DATA_WIDTH-1:0] held_data [MEM_NUM_BANKS];
    logic [MEM_TAG_WIDTH-1:0] held_tag [MEM_NUM_BANKS];
    logic [31:0] dcr_value;
    logic [3:0] dcr_delay;

    initial begin
        count = 0;
        running = 0;
        dcr_value = 0;
        dcr_delay = 0;
    end

    assign busy = running;
    assign dcr_rsp_valid = (dcr_delay == 1);
    assign dcr_rsp_data = dcr_value;

    always @(posedge clk) begin
        if (reset) begin
            count <= 0;
            running <= 0;
            dcr_delay <= 0;
            for (int b = 0; b < MEM_NUM_BANKS; ++b) begin
                received[b] <= 0;
                held_valid[b] <= 0;
                held_data[b] <= '0;
                held_tag[b] <= '0;
            end
        end else begin
            if (dcr_delay != 0) begin
                dcr_delay <= dcr_delay - 1;
            end
            if (dcr_req_valid) begin
                assert (dcr_req_addr == 'h123) else $error("fixture: DCR address mismatch");
                if (dcr_req_rw) begin
                    dcr_value <= dcr_req_data;
                end else begin
                    dcr_delay <= 4;
                end
            end
            if (start) begin
                running <= 1;
                count <= 0;
            end else if (running) begin
                count <= count + 1;
                for (int b = 0; b < MEM_NUM_BANKS; ++b) begin
                    if (held_valid[b] && (!mem_rsp_valid[b] ||
                        mem_rsp_data[b] !== held_data[b] || mem_rsp_tag[b] !== held_tag[b])) begin
                        $fatal(1, "fixture: response changed under backpressure");
                    end
                    held_valid[b] <= mem_rsp_valid[b] && !mem_rsp_ready[b];
                    held_data[b] <= mem_rsp_data[b];
                    held_tag[b] <= mem_rsp_tag[b];
                    if (mem_req_valid[b] && !mem_req_ready[b]) begin
                        $fatal(1, "fixture: unexpected request backpressure");
                    end
                    if (mem_rsp_valid[b]) begin
                        if (mem_rsp_tag[b] !== 64'hfedcba9876543210 + 64'(b) + 64'(received[b]) * 64'h100) begin
                            $fatal(1, "fixture: response tag mismatch");
                        end
                        for (int i = 0; i < MEM_DATA_WIDTH/8; ++i) begin
                            if (b == 0 && i == 0 && received[b] == 0 && dcr_value[3:0] == 5 &&
                                (dcr_value[7:4] == 1 || dcr_value[7:4] == 2)) begin
                            `ifndef VERILATOR
                                if (mem_rsp_data[b][i*8 +: 8] !==
                                    ((dcr_value[7:4] == 1) ? 8'b10x01x10 : 8'b10z01z10)) begin
                                    $fatal(1, "fixture: X/Z data was not preserved");
                                end
                            `endif
                            end else if (mem_rsp_data[b][i*8 +: 8] !== ((i % 2 == 0) ? 8'(i + b) : 8'h55)) begin
                                $fatal(1, "fixture: response data mismatch at byte %0d", i);
                            end
                        end
                        if (mem_rsp_ready[b]) begin
                            received[b] <= received[b] + 1;
                        end
                    end
                end
                if (count == 800) begin
                    for (int b = 0; b < MEM_NUM_BANKS; ++b) begin
                        if (received[b] != 2) begin
                            $fatal(1, "fixture: lost or duplicated response at bank %0d", b);
                        end
                    end
                    running <= 0;
                end
            end
        end
    end

    for (genvar b = 0; b < MEM_NUM_BANKS; ++b) begin : g_bank
        wire inject_fault = running && count == 1 && b == 0
                          && (dcr_value[7:4] == 1 || dcr_value[7:4] == 2);
        wire unknown_value = (dcr_value[7:4] == 1) ? 1'bx : 1'bz;
        assign mem_req_valid[b] = (inject_fault && dcr_value[3:0] == 1)
                               ? unknown_value : running && (count == 1 || count == 3 || count == 5 || count == 7);
        assign mem_req_rw[b] = (count == 1 || count == 5);
        assign mem_req_addr[b] = (inject_fault && dcr_value[3:0] == 2)
                              ? {VX_CFG_MEM_ADDR_WIDTH{unknown_value}} : VX_CFG_MEM_ADDR_WIDTH'(7);
        assign mem_req_tag[b] = (inject_fault && dcr_value[3:0] == 3)
                             ? {64{unknown_value}} : 64'hfedcba9876543210 + 64'(b) + ((count >= 5) ? 64'h100 : 64'h0);
        assign mem_rsp_ready[b] = running && count > 500;
        for (genvar i = 0; i < MEM_DATA_WIDTH/8; ++i) begin : g_data
            assign mem_req_byteen[b][i] = (inject_fault && dcr_value[3:0] == 4)
                                       ? unknown_value : ((count == 5) ? (i == 0) : (i % 2 == 0));
            assign mem_req_data[b][i*8 +: 8] = (inject_fault &&
                ((dcr_value[3:0] == 5 && i == 0) || (dcr_value[3:0] == 6 && i == 1)))
                ? {2'b10, unknown_value, 2'b01, unknown_value, 2'b10} : 8'(i + b);
        end
    end
endmodule
