module tb_cache;

  reg clk, rstn;

  reg cpu_req, cpu_write;
  wire cpu_ack;
  reg [5:0] cpu_addr;
  reg [31:0] cpu_wdata;
  wire [31:0] cpu_rdata;

  wire mem_req, mem_write;
  wire mem_ack;
  wire [5:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [31:0] mem_rdata;

  reg [3:0] cpu_ptr;

  reg [1+6+32:0] cmd[10:0];

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    rstn = 1;
    #20 rstn = 0;
    #30 rstn = 1;
  end


  //CPU PART
  initial begin
    cmd[0]  = {1'b1, 6'h04, 32'h400};  //WRITE	
    cmd[1]  = {1'b1, 6'h05, 32'h500};  //WRITE
    cmd[2]  = {1'b0, 6'h06, 32'h000};  //READ MISS
    cmd[3]  = {1'b0, 6'h07, 32'h000};  //READ MISS

    cmd[4]  = {1'b0, 6'h08, 32'h000};  //READ MISS, WRITE BACK
    cmd[5]  = {1'b1, 6'h05, 32'h501};  //WRITE HIT
    cmd[6]  = {1'b0, 6'h06, 32'h000};  //READ HIT
    cmd[7]  = {1'b1, 6'h0B, 32'hB00};  //WRITE MISS

    cmd[8]  = {1'b0, 6'h0C, 32'h000};  //READ MISS
    cmd[9]  = {1'b1, 6'h0D, 32'hD00};  //WRITE MISS, WRITE BACK

    cmd[10] = 0;
  end

  wire cpu_en = cpu_req & cpu_ack;

  always @(posedge clk, negedge rstn)
    if (!rstn) {cpu_write, cpu_addr, cpu_wdata} <= 0;
    else {cpu_write, cpu_addr, cpu_wdata} <= cmd[cpu_ptr];

  always @(posedge clk, negedge rstn)
    if (!rstn) cpu_ptr <= 0;
    else if (cpu_en) cpu_ptr <= cpu_ptr + 1;

  always @(posedge clk, negedge rstn)
    if (!rstn) cpu_req <= 0;
    else if (cpu_en) cpu_req <= 0;
    else if (cpu_ptr < 10) cpu_req <= 1;

  //CACHE PART, DUT
  cache u_cache (
      clk,
      rstn,

      cpu_req,
      cpu_write,
      cpu_ack,
      cpu_addr,
      cpu_wdata,
      cpu_rdata,

      mem_req,
      mem_write,
      mem_ack,
      mem_addr,
      mem_wdata,
      mem_rdata
  );

  //MEMORY PART
  wire mem_en = mem_req & mem_ack;
  wire mem_we = mem_req & mem_ack & mem_write;
  wire mem_re = mem_req & mem_ack & ~mem_write;

  reg [31:0] mem[63:0];
  reg [6:0] mem_req_d;

  always @(posedge clk, negedge rstn)
    if (!rstn) for (int i = 0; i < 64; i++) mem[i] <= i << 4;
    else if (mem_we) mem[mem_addr] <= mem_wdata;

  assign mem_ack = mem_req_d[5] & ~mem_req_d[6];
  always @(posedge clk, negedge rstn)
    if (!rstn) mem_req_d <= 0;
    else mem_req_d <= {mem_req_d[5:0], mem_req};

  assign mem_rdata = mem_re ? mem[mem_addr] : 'bX;

  initial begin
    #1000 $finish;
  end
endmodule
