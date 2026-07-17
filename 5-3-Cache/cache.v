module cache (input clk,
              input rstn,
              input i_cpu_req,
              input i_cpu_write,
              output o_cpu_ack,
              input [5:0] i_cpu_addr,
              input [31:0] i_cpu_wdata,
              output [31:0] o_cpu_rdata,
              output o_mem_req,
              output o_mem_write,
              input i_mem_ack,
              output [5:0] o_mem_addr,
              output [31:0] o_mem_wdata,
              input [31:0] i_mem_rdata);
    
    reg [3:0] valid_mem, wb_mem;
    
    wire       cpu_en = i_cpu_req & o_cpu_ack;
    wire       cpu_we = i_cpu_req & o_cpu_ack & i_cpu_write;
    wire       cpu_re = i_cpu_req & o_cpu_ack & ~i_cpu_write;
    
    wire       mem_en = o_mem_req & i_mem_ack;
    wire       mem_we = o_mem_req & i_mem_ack & o_mem_write;
    wire       mem_re = o_mem_req & i_mem_ack & ~o_mem_write;
    
    wire       cc_we = mem_re | cpu_we;
    wire [1:0] cc_wa = i_cpu_addr[1:0];
    wire       cc_re = i_cpu_req;
    wire [1:0] cc_ra = i_cpu_addr[1:0];
    
    reg        cc_re_d;
    reg        valid_rd, wb_rd;
    wire [3:0] tag_rd;
    wire [31:0] data_rd;
    
    reg mem_we_d;
    
    always @(posedge clk, negedge rstn)
        if (!rstn) cc_re_d <= 0;
        else cc_re_d       <= cc_re;
    
    wire hit   = cc_re_d & valid_rd && tag_rd == i_cpu_addr[5:2];
    wire empty = cc_re_d & ~valid_rd;
    wire diff  = cc_re_d & valid_rd && tag_rd != i_cpu_addr[5:2];
    wire miss  = empty | diff;
    
    // no operation, write back, read data
    wire mem_no = hit || (cc_re_d & ~wb_rd & i_cpu_write);
    wire mem_wb = diff & wb_rd;
    wire mem_rd = miss & ~i_cpu_write;
    
    //hit, write wo/ evict, read w/ mem_re,
    assign o_cpu_ack   = hit || mem_no || (mem_rd ? mem_re : mem_we);
    assign o_cpu_rdata = hit ? data_rd : mem_re ? i_mem_rdata : 'bX;
    
    always @(posedge clk, negedge rstn)
        if (!rstn) mem_we_d <= 0;
        else mem_we_d       <= mem_we;
    
    //write back + read miss
    assign o_mem_req   = ~mem_we_d & (mem_wb | mem_rd);
    assign o_mem_addr  = mem_wb ? {tag_rd, i_cpu_addr[1:0]} : i_cpu_addr;
    assign o_mem_wdata = data_rd;
    assign o_mem_write = wb_rd;
    
    // VALID(1bit) + TAG(4bit) + DATA(32bit)

    // Write VALID
    always @(posedge clk, negedge rstn)
        if (!rstn) valid_mem             <= 0;
        else if (cc_we) valid_mem[cc_wa] <= 1;
    
    // Read VALID
    always @(posedge clk, negedge rstn)
        if (!rstn) valid_rd      <= 0;
        else if (cc_re) valid_rd <= valid_mem[cc_ra];
    
    // Write Write-Back (dirty bit)
    // 1: dirty(not match cache data and memory data)
    // 0: clean(match cache data and memory data)
    always @(posedge clk, negedge rstn)
        if (!rstn) wb_mem              <= 0;
        else if (cpu_we) wb_mem[cc_wa] <= 1;
        else if (mem_re) wb_mem[cc_wa] <= 0;
        else if (mem_we) wb_mem[cc_wa] <= i_cpu_write;
    
    // Read Write-Back (dirty bit)
    always @(posedge clk, negedge rstn)
        if (!rstn) wb_rd      <= 0;
        else if (cc_re) wb_rd <= wb_mem[cc_ra];
    
    // if read memory,
    // Write data and tag to cache memory
    wire [3:0] tag_wd   = mem_re ? o_mem_addr[5:2] : cpu_we ? i_cpu_addr[5:2] : 'bX;
    wire [31:0] data_wd = mem_re ? i_mem_rdata : cpu_we ? i_cpu_wdata : 'bX;
    
    // Tag cache memory: 4x4bit
    tpsram #(
    .DEPTH(4),
    .WIDTH(4)
    ) u_tag (
    clk,
    cc_we,
    cc_wa,
    tag_wd,
    cc_re,
    cc_ra,
    tag_rd
    );
    
    // Data cache memory: 4x32bit
    tpsram #(
    .DEPTH(4),
    .WIDTH(32)
    ) u_data (
    clk,
    cc_we,
    cc_wa,
    data_wd,
    cc_re,
    cc_ra,
    data_rd
    );
    
endmodule
    
