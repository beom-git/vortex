`timescale 1ns/1ps

module vcs_top;
    logic clk = 1;
    testbench bench (.clk (clk));
    string image_path;
    string waveform;
`ifdef FSDB_OUTPUT
    string fsdb_waveform;
`endif
    int status;
    int runtime_fd;
    int page_size;

    import "DPI-C" context task rtlsim_program(input string image_path, output int status);
    import "DPI-C" context task rtlsim_host(input int fd, input int page_size, output int status);
    export "DPI-C" task rtlsim_step;
    export "DPI-C" function rtlsim_assertions;

`ifdef WAVEFORM_OUTPUT
    import "DPI-C" context function bit rtlsim_trace_enabled();
    bit recording = 0;
    bit trace_initialized = 0;
`endif

    always begin
        #5;
`ifdef WAVEFORM_OUTPUT
        // Gate writers before clock callbacks observe the new value.
        if (trace_initialized && rtlsim_trace_enabled() != recording) begin
            recording = !recording;
            if (recording) begin
`ifdef VCD_OUTPUT
                $dumpon;
`endif
`ifdef FSDB_OUTPUT
                $fsdbDumpon;
`endif
            end else begin
`ifdef VCD_OUTPUT
                $dumpoff;
`endif
`ifdef FSDB_OUTPUT
                $fsdbDumpoff;
`endif
            end
        end
`endif
        clk = ~clk;
    end

    task rtlsim_step();
        @(negedge clk);
        @(posedge clk);
        // Resume C++ only after the shared testbench and DUT NBA updates settle.
        #1;
    endtask

    function void rtlsim_assertions();
        $asserton;
    endfunction

    initial begin
        $assertoff;
`ifdef VCD_OUTPUT
        if (!$value$plusargs("vcd=%s", waveform)) begin
            waveform = "trace.vcd";
        end
        $dumpfile(waveform);
        $dumpvars(0);
`endif
`ifdef FSDB_OUTPUT
        if (!$value$plusargs("fsdb=%s", fsdb_waveform)) begin
            fsdb_waveform = "trace.fsdb";
        end
        $fsdbDumpfile(fsdb_waveform);
        $fsdbDumpvars(0, bench, "+all");
`endif
`ifdef WAVEFORM_OUTPUT
        recording = rtlsim_trace_enabled();
        if (!recording) begin
`ifdef VCD_OUTPUT
            $dumpoff;
`endif
`ifdef FSDB_OUTPUT
            $fsdbDumpoff;
`endif
        end
        trace_initialized = 1;
`endif
        if ($value$plusargs("runtime_fd=%d", runtime_fd)) begin
            if (runtime_fd != 3 || !$value$plusargs("runtime_page_size=%d", page_size)) begin
                $fatal(1, "rtlsim: invalid runtime connection");
            end
            rtlsim_host(runtime_fd, page_size, status);
        end else begin
            if (!$value$plusargs("program=%s", image_path)) begin
                $fatal(1, "rtlsim: missing +program=<image>");
            end
            rtlsim_program(image_path, status);
        end
        if (status != 0) begin
            $fatal(1, "rtlsim: program failed with status %0d", status);
        end
        $finish;
    end
endmodule
