`include "DSEMacro.v"

module XSTop_wrapper_dse(
  input           clock,
  input           reset,

  input [63:0]    io_extIntrs,
  output          out_enable,
  output [`DEG_DATA_WIDTH+`MAGIC_NUM_WIDTH-1:0] out_io_data,

  output          dma_core_awready,
  input           dma_core_awvalid,
  input  [13:0]   dma_core_awid,
  input  [47:0]   dma_core_awaddr,
  input  [7:0]    dma_core_awlen,
  input  [2:0]    dma_core_awsize,
  input  [1:0]    dma_core_awburst,
  input           dma_core_awlock,
  input  [3:0]    dma_core_awcache,
  input  [2:0]    dma_core_awprot,
  input  [3:0]    dma_core_awqos,
  output          dma_core_wready,
  input           dma_core_wvalid,
  input  [255:0]  dma_core_wdata,
  input  [31:0]   dma_core_wstrb,
  input           dma_core_wlast,
  input           dma_core_bready,
  output          dma_core_bvalid,
  output [13:0]   dma_core_bid,
  output [1:0]    dma_core_bresp,
  output          dma_core_arready,
  input           dma_core_arvalid,
  input  [13:0]   dma_core_arid,
  input  [47:0]   dma_core_araddr,
  input  [7:0]    dma_core_arlen,
  input  [2:0]    dma_core_arsize,
  input  [1:0]    dma_core_arburst,
  input           dma_core_arlock,
  input  [3:0]    dma_core_arcache,
  input  [2:0]    dma_core_arprot,
  input  [3:0]    dma_core_arqos,
  input           dma_core_rready,
  output          dma_core_rvalid,
  output [13:0]   dma_core_rid,
  output [255:0]  dma_core_rdata,
  output [1:0]    dma_core_rresp,
  output          dma_core_rlast,

  input           peri_awready,
  output          peri_awvalid,
  output [1:0]    peri_awid,
  output [30:0]   peri_awaddr,
  output [7:0]    peri_awlen,
  output [2:0]    peri_awsize,
  output [1:0]    peri_awburst,
  output          peri_awlock,
  output [3:0]    peri_awcache,
  output [2:0]    peri_awprot,
  output [3:0]    peri_awqos,
  input           peri_wready,
  output          peri_wvalid,
  output [63:0]   peri_wdata,
  output [7:0]    peri_wstrb,
  output          peri_wlast,
  output          peri_bready,
  input           peri_bvalid,
  input  [1:0]    peri_bid,
  input  [1:0]    peri_bresp,
  input           peri_arready,
  output          peri_arvalid,
  output [1:0]    peri_arid,
  output [30:0]   peri_araddr,
  output [7:0]    peri_arlen,
  output [2:0]    peri_arsize,
  output [1:0]    peri_arburst,
  output          peri_arlock,
  output [3:0]    peri_arcache,
  output [2:0]    peri_arprot,
  output [3:0]    peri_arqos,
  output          peri_rready,
  input           peri_rvalid,
  input  [1:0]    peri_rid,
  input  [63:0]   peri_rdata,
  input  [1:0]    peri_rresp,
  input           peri_rlast,

  input           mem_core_awready,
  output          mem_core_awvalid,
  output [13:0]   mem_core_awid,
  output [47:0]   mem_core_awaddr,
  output [7:0]    mem_core_awlen,
  output [2:0]    mem_core_awsize,
  output [1:0]    mem_core_awburst,
  output          mem_core_awlock,
  output [3:0]    mem_core_awcache,
  output [2:0]    mem_core_awprot,
  output [3:0]    mem_core_awqos,
  input           mem_core_wready,
  output          mem_core_wvalid,
  output [255:0]  mem_core_wdata,
  output [31:0]   mem_core_wstrb,
  output          mem_core_wlast,
  output          mem_core_bready,
  input           mem_core_bvalid,
  input  [13:0]   mem_core_bid,
  input  [1:0]    mem_core_bresp,
  input           mem_core_arready,
  output          mem_core_arvalid,
  output [13:0]   mem_core_arid,
  output [47:0]   mem_core_araddr,
  output [7:0]    mem_core_arlen,
  output [2:0]    mem_core_arsize,
  output [1:0]    mem_core_arburst,
  output          mem_core_arlock,
  output [3:0]    mem_core_arcache,
  output [2:0]    mem_core_arprot,
  output [3:0]    mem_core_arqos,
  output          mem_core_rready,
  input           mem_core_rvalid,
  input  [13:0]   mem_core_rid,
  input  [255:0]  mem_core_rdata,
  input  [1:0]    mem_core_rresp,
  input           mem_core_rlast
);

  wire dse_reset_valid;
  wire [35:0] dse_reset_vector;
  wire [63:0] dse_epoch;
  wire [47:0] memory_awaddr;
  wire [47:0] memory_araddr;

  // define performance counter wires
  wire deg_out_enable;
  wire [3:0] deg_valids;
  wire [`DEG_DATA_WIDTH-1:0] deg_out_data;  // [16000:0] is valid data
  wire [`PERF_DATA_WIDTH-1:0] perf_out_data;
  wire dse_endpoint_out_enable;
  wire [`DEG_DATA_WIDTH+`MAGIC_NUM_WIDTH-1:0] dse_endpoint_out_data;

  assign mem_core_awaddr = memory_awaddr - 48'h0000_8000_0000;
  assign mem_core_araddr = memory_araddr - 48'h0000_8000_0000;

  XSTop  u_XSTop(
    .nmi_0_0                         (1'b0),
    .nmi_0_1                         (1'b0),

    .dma_awready                   (dma_core_awready )                     ,
    .dma_awvalid                   (dma_core_awvalid )                     ,
    .dma_awid                      (dma_core_awid    )                       ,
    .dma_awaddr                    (dma_core_awaddr  )                         ,
    .dma_awlen                     (dma_core_awlen   )                        ,
    .dma_awsize                    (dma_core_awsize  )                         ,
    .dma_awburst                   (dma_core_awburst )                          ,
    .dma_awlock                    (dma_core_awlock  )                         ,
    .dma_awcache                   (dma_core_awcache )                          ,
    .dma_awprot                    (dma_core_awprot  )                         ,
    .dma_awqos                     (dma_core_awqos   )                        ,
    .dma_wready                    (dma_core_wready  )                    ,
    .dma_wvalid                    (dma_core_wvalid  )                    ,
    .dma_wdata                     (dma_core_wdata   )                        ,
    .dma_wstrb                     (dma_core_wstrb   )                        ,
    .dma_wlast                     (dma_core_wlast   )                        ,
    .dma_bready                    (dma_core_bready  )                    ,
    .dma_bvalid                    (dma_core_bvalid  )                    ,
    .dma_bid                       (dma_core_bid     )                      ,
    .dma_bresp                     (dma_core_bresp   )                        ,
    .dma_arready                   (dma_core_arready )                     ,
    .dma_arvalid                   (dma_core_arvalid )                     ,
    .dma_arid                      (dma_core_arid    )                       ,
    .dma_araddr                    (dma_core_araddr  )                         ,
    .dma_arlen                     (dma_core_arlen   )                        ,
    .dma_arsize                    (dma_core_arsize  )                         ,
    .dma_arburst                   (dma_core_arburst )                          ,
    .dma_arlock                    (dma_core_arlock  )                         ,
    .dma_arcache                   (dma_core_arcache )                          ,
    .dma_arprot                    (dma_core_arprot  )                         ,
    .dma_arqos                     (dma_core_arqos   )                        ,
    .dma_rready                    (dma_core_rready  )                    ,
    .dma_rvalid                    (dma_core_rvalid  )                    ,
    .dma_rid                       (dma_core_rid     )                      ,
    .dma_rdata                     (dma_core_rdata   )                        ,
    .dma_rresp                     (dma_core_rresp   )                        ,
    .dma_rlast                     (dma_core_rlast   )                        ,

    .peripheral_awready            (peri_awready  )                            ,
    .peripheral_awvalid            (peri_awvalid  )                            ,
    .peripheral_awid               (peri_awid     )                              ,
    .peripheral_awaddr             (peri_awaddr   )                                ,
    .peripheral_awlen              (peri_awlen    )                               ,
    .peripheral_awsize             (peri_awsize   )                                ,
    .peripheral_awburst            (peri_awburst  )                                 ,
    .peripheral_awlock             (peri_awlock   )                                ,
    .peripheral_awcache            (peri_awcache  )                                 ,
    .peripheral_awprot             (peri_awprot   )                                ,
    .peripheral_awqos              (peri_awqos    )                               ,
    .peripheral_wready             (peri_wready   )                           ,
    .peripheral_wvalid             (peri_wvalid   )                           ,
    .peripheral_wdata              (peri_wdata    )                               ,
    .peripheral_wstrb              (peri_wstrb    )                               ,
    .peripheral_wlast              (peri_wlast    )                               ,
    .peripheral_bready             (peri_bready   )                           ,
    .peripheral_bvalid             (peri_bvalid   )                           ,
    .peripheral_bid                (peri_bid      )                             ,
    .peripheral_bresp              (peri_bresp    )                               ,
    .peripheral_arready            (peri_arready  )                            ,
    .peripheral_arvalid            (peri_arvalid  )                            ,
    .peripheral_arid               (peri_arid     )                              ,
    .peripheral_araddr             (peri_araddr   )                                ,
    .peripheral_arlen              (peri_arlen    )                               ,
    .peripheral_arsize             (peri_arsize   )                                ,
    .peripheral_arburst            (peri_arburst  )                                 ,
    .peripheral_arlock             (peri_arlock   )                                ,
    .peripheral_arcache            (peri_arcache  )                                 ,
    .peripheral_arprot             (peri_arprot   )                                ,
    .peripheral_arqos              (peri_arqos    )                               ,
    .peripheral_rready             (peri_rready   )                           ,
    .peripheral_rvalid             (peri_rvalid   )                           ,
    .peripheral_rid                (peri_rid      )                             ,
    .peripheral_rdata              (peri_rdata    )                               ,
    .peripheral_rresp              (peri_rresp    )                               ,
    .peripheral_rlast              (peri_rlast    )                               ,

    .memory_awready                (mem_core_awready )                        ,
    .memory_awvalid                (mem_core_awvalid )                        ,
    .memory_awid                   (mem_core_awid    )                          ,
    .memory_awaddr                 (memory_awaddr    )                            ,
    .memory_awlen                  (mem_core_awlen   )                           ,
    .memory_awsize                 (mem_core_awsize  )                            ,
    .memory_awburst                (mem_core_awburst )                             ,
    .memory_awlock                 (mem_core_awlock  )                            ,
    .memory_awcache                (mem_core_awcache )                             ,
    .memory_awprot                 (mem_core_awprot  )                            ,
    .memory_awqos                  (mem_core_awqos   )                           ,
    .memory_wready                 (mem_core_wready  )                       ,
    .memory_wvalid                 (mem_core_wvalid  )                       ,
    .memory_wdata                  (mem_core_wdata   )                           ,
    .memory_wstrb                  (mem_core_wstrb   )                           ,
    .memory_wlast                  (mem_core_wlast   )                           ,
    .memory_bready                 (mem_core_bready  )                       ,
    .memory_bvalid                 (mem_core_bvalid  )                       ,
    .memory_bid                    (mem_core_bid     )                         ,
    .memory_bresp                  (mem_core_bresp   )                           ,
    .memory_arready                (mem_core_arready )                        ,
    .memory_arvalid                (mem_core_arvalid )                        ,
    .memory_arid                   (mem_core_arid    )                          ,
    .memory_araddr                 (memory_araddr    )                            ,
    .memory_arlen                  (mem_core_arlen   )                           ,
    .memory_arsize                 (mem_core_arsize  )                            ,
    .memory_arburst                (mem_core_arburst )                             ,
    .memory_arlock                 (mem_core_arlock  )                            ,
    .memory_arcache                (mem_core_arcache )                             ,
    .memory_arprot                 (mem_core_arprot  )                            ,
    .memory_arqos                  (mem_core_arqos   )                           ,
    .memory_rready                 (mem_core_rready  )                       ,
    .memory_rvalid                 (mem_core_rvalid  )                       ,
    .memory_rid                    (mem_core_rid     )                         ,
    .memory_rdata                  (mem_core_rdata   )                           ,
    .memory_rresp                  (mem_core_rresp   )                           ,
    .memory_rlast                  (mem_core_rlast   )                           ,

    .io_clock                        (clock    ),
    .io_reset                        (reset  ),
    .io_sram_config                  (16'h0),
    .io_extIntrs                     (io_extIntrs  ),
    .io_pll0_lock                    (1'b1),

    .io_systemjtag_jtag_TCK          (_jtag_jtag_TCK),
    .io_systemjtag_jtag_TMS          (_jtag_jtag_TMS),
    .io_systemjtag_jtag_TDI          (_jtag_jtag_TDI),
    .io_systemjtag_jtag_TDO_data     (_l_soc_io_systemjtag_jtag_TDO_data),
    .io_systemjtag_jtag_TDO_driven   (_l_soc_io_systemjtag_jtag_TDO_driven),
    .io_systemjtag_reset             (reset),
    .io_systemjtag_mfr_id            (11'h11),
    .io_systemjtag_part_number       (16'h16),
    .io_systemjtag_version           (4'h4),

    .io_cacheable_check_req_0_valid  (1'b0),

    .io_riscv_rst_vec_0                 (48'h10000000),

    .io_traceCoreInterface_0_fromEncoder_enable (1'b0),
    .io_traceCoreInterface_0_fromEncoder_stall  (1'b0)

    // .io_dse_rst                         (reset),
    // .io_dse_reset_valid                 (dse_reset_valid),
    // .io_dse_reset_vec                   (dse_reset_vector),
    // .io_dse_epoch                       (dse_epoch),
    // .perf_out_data                      (perf_out_data)
  );

  assign deg_out_enable = 1'b0;
  assign deg_valids = 4'b0;
  assign deg_out_data = 0;
  assign perf_out_data = 0;
  assign dse_reset_valid = 1'b0;
  assign dse_reset_vector = 0;
  assign dse_epoch = 0;

  SimJTAG #(
    .TICK_DELAY(3)
  ) jtag (	// src/test/scala/top/SimTop.scala:63:20
    .clock           (clock),
    .reset           (reset),
    .jtag_TRSTn      (/* unused */),
    .jtag_TCK        (_jtag_jtag_TCK),
    .jtag_TMS        (_jtag_jtag_TMS),
    .jtag_TDI        (_jtag_jtag_TDI),
    .jtag_TDO_data   (_l_soc_io_systemjtag_jtag_TDO_data),	// src/test/scala/top/SimTop.scala:36:19
    .jtag_TDO_driven (_l_soc_io_systemjtag_jtag_TDO_driven),	// src/test/scala/top/SimTop.scala:36:19
    .enable          (1'h1),	// src/test/scala/top/SimTop.scala:59:20
    .init_done       (~reset),	// src/test/scala/top/SimTop.scala:64:61
    .exit            (/* unused */)
  );

  DSEEndpoint dseendpoint (
    .clock              (clock           ),
    .reset              (reset           ),
    .dse_reset_valid    (dse_reset_valid ),
    .dse_reset_vector   (dse_reset_vector),
    .dse_epoch          (dse_epoch       ),
    .deg_out_enable     (deg_out_enable  ),
    .deg_valids         (deg_valids      ),
    .deg_out_data       (deg_out_data    ),
    .perf_out_data      (perf_out_data   ),
    .out_enable         (dse_endpoint_out_enable),
    .out_data           (dse_endpoint_out_data)
  );

  assign out_enable = dse_endpoint_out_enable;
  assign out_io_data = dse_endpoint_out_data;

endmodule
