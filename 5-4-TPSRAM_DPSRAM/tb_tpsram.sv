module tb_tpsram;
	
	parameter	DEPTH =8, WIDTH=32;
	parameter	DEPTH_LOG = $clog2(DEPTH);
	
	reg	clk;
	reg	we,re;
	reg	[DEPTH_LOG-1:0]	wa,ra;
	reg	[WIDTH-1:0]			wd;
	wire	[WIDTH-1:0]	rd;
	
	reg	cs_a, we_a, cs_b, we_b;
	reg	[DEPTH_LOG-1:0]	ad_a, ad_b;
	reg	[WIDTH-1:0]			wd_a, wd_b;
	wire	[WIDTH-1:0]			rd_a, rd_b;
	
	initial begin
		clk	= 0;
		forever #5 clk = ~clk;
	end
	
	initial begin
		{we,re,cs_a,we_a,cs_b,we_b} <= 0;
		fork
			begin: tpsram_write
				@(posedge clk);
				for (int i=0;i<DEPTH;i++) begin
					we <= 1;
					wa <= i;
					wd <= 'h10+i;
					@(posedge clk);
				end
				we <= 0; @(posedge clk);
			end
			
			begin: tpsram_read
				repeat (2) @(posedge clk);
				for (int i=0;i<DEPTH;i++) begin
					re <= 1;
					ra <= i;
					@(posedge clk);
				end
				re <= 0; @(posedge clk);
			end
			
			begin: dpsram_port_a
				@(posedge clk);
				for (int i=0;i<DEPTH/2;i++) begin
					cs_a <= 1; we_a <= 1;
					ad_a <= i;
					wd_a <= 'h20+i;
					@(posedge clk);
				end
				cs_a <= 0; we_a <= 0;
				@(posedge clk);
				for (int i=DEPTH/2;i<DEPTH;i++) begin
					cs_a <= 1;
					ad_a <= i;
					@(posedge clk);
				end
				cs_a <= 0; @(posedge clk);
			end
			
			begin: dpsram_port_b
				@(posedge clk);
				for (int i=DEPTH/2;i<DEPTH;i++) begin
					cs_b <= 1; we_b <= 1;
					ad_b <= i;
					wd_b <= 'h30+i;
					@(posedge clk);
				end
				cs_b <= 0; we_b <= 0;
				@(posedge clk);
				for (int i=0;i<DEPTH/2;i++) begin
					cs_b <= 1;
					ad_b <= i;
					@(posedge clk);
				end
				cs_b <= 0; @(posedge clk);
			end
		join
		repeat(2) @(posedge clk);
		$finish;
	end
	
	tpsram #(DEPTH, WIDTH) u_tpsram_8x32
		(.clk(clk), .we(we), .re(re), .wa(wa), .ra(ra), .wd(wd), .rd(rd));
	
	dpsram #(DEPTH, WIDTH) u_dpsram_8x32
		(.clk(clk), .cs_a(cs_a), .cs_b(cs_b), .we_a(we_a), .we_b(we_b), .ad_a(ad_a), .ad_b(ad_b), .wd_a(wd_a), .wd_b(wd_b), .rd_a(rd_a), .rd_b(rd_b));
	
endmodule
