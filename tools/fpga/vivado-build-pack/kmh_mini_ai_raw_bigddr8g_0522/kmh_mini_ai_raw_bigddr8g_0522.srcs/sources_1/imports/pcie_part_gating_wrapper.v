//Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2020.2 (lin64) Build 3064766 Wed Nov 18 09:12:47 MST 2020
//Date        : Tue May  6 10:09:44 2025
//Host        : open20 running 64-bit Ubuntu 22.04.3 LTS
//Command     : generate_target pcie_part_gating_wrapper.bd
//Design      : pcie_part_gating_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module pcie_part_gating_wrapper
   (c0_ddr4_act_n,
    c0_ddr4_adr,
    c0_ddr4_ba,
    c0_ddr4_bg,
    c0_ddr4_ck_c,
    c0_ddr4_ck_t,
    c0_ddr4_cke,
    c0_ddr4_cs_n,
    c0_ddr4_dm_n,
    c0_ddr4_dq,
    c0_ddr4_dqs_c,
    c0_ddr4_dqs_t,
    c0_ddr4_odt,
    c0_ddr4_reset_n,
    ddr4_mig_calib_done,
    ddr4_mig_sys_clk_clk_n,
    ddr4_mig_sys_clk_clk_p,
    pci_ep_rxn,
    pci_ep_rxp,
    pci_ep_txn,
    pci_ep_txp,
    pcie_ep_gt_ref_clk_clk_n,
    pcie_ep_gt_ref_clk_clk_p,
    pcie_ep_lnk_up,
    pcie_ep_perstn);
  output c0_ddr4_act_n;
  output [16:0]c0_ddr4_adr;
  output [1:0]c0_ddr4_ba;
  output [1:0]c0_ddr4_bg;
  output [0:0]c0_ddr4_ck_c;
  output [0:0]c0_ddr4_ck_t;
  output [0:0]c0_ddr4_cke;
  output [0:0]c0_ddr4_cs_n;
  inout [7:0]c0_ddr4_dm_n;
  inout [63:0]c0_ddr4_dq;
  inout [7:0]c0_ddr4_dqs_c;
  inout [7:0]c0_ddr4_dqs_t;
  output [0:0]c0_ddr4_odt;
  output c0_ddr4_reset_n;
  output ddr4_mig_calib_done;
  input ddr4_mig_sys_clk_clk_n;
  input ddr4_mig_sys_clk_clk_p;
  input [7:0]pci_ep_rxn;
  input [7:0]pci_ep_rxp;
  output [7:0]pci_ep_txn;
  output [7:0]pci_ep_txp;
  input [0:0]pcie_ep_gt_ref_clk_clk_n;
  input [0:0]pcie_ep_gt_ref_clk_clk_p;
  output pcie_ep_lnk_up;
  input pcie_ep_perstn;

  wire c0_ddr4_act_n;
  wire [16:0]c0_ddr4_adr;
  wire [1:0]c0_ddr4_ba;
  wire [1:0]c0_ddr4_bg;
  wire [0:0]c0_ddr4_ck_c;
  wire [0:0]c0_ddr4_ck_t;
  wire [0:0]c0_ddr4_cke;
  wire [0:0]c0_ddr4_cs_n;
  wire [7:0]c0_ddr4_dm_n;
  wire [63:0]c0_ddr4_dq;
  wire [7:0]c0_ddr4_dqs_c;
  wire [7:0]c0_ddr4_dqs_t;
  wire [0:0]c0_ddr4_odt;
  wire c0_ddr4_reset_n;
  wire ddr4_mig_calib_done;
  wire ddr4_mig_sys_clk_clk_n;
  wire ddr4_mig_sys_clk_clk_p;
  wire [7:0]pci_ep_rxn;
  wire [7:0]pci_ep_rxp;
  wire [7:0]pci_ep_txn;
  wire [7:0]pci_ep_txp;
  wire [0:0]pcie_ep_gt_ref_clk_clk_n;
  wire [0:0]pcie_ep_gt_ref_clk_clk_p;
  wire pcie_ep_lnk_up;
  wire pcie_ep_perstn;

  pcie_part_gating pcie_part_gating_i
       (.c0_ddr4_act_n(c0_ddr4_act_n),
        .c0_ddr4_adr(c0_ddr4_adr),
        .c0_ddr4_ba(c0_ddr4_ba),
        .c0_ddr4_bg(c0_ddr4_bg),
        .c0_ddr4_ck_c(c0_ddr4_ck_c),
        .c0_ddr4_ck_t(c0_ddr4_ck_t),
        .c0_ddr4_cke(c0_ddr4_cke),
        .c0_ddr4_cs_n(c0_ddr4_cs_n),
        .c0_ddr4_dm_n(c0_ddr4_dm_n),
        .c0_ddr4_dq(c0_ddr4_dq),
        .c0_ddr4_dqs_c(c0_ddr4_dqs_c),
        .c0_ddr4_dqs_t(c0_ddr4_dqs_t),
        .c0_ddr4_odt(c0_ddr4_odt),
        .c0_ddr4_reset_n(c0_ddr4_reset_n),
        .ddr4_mig_calib_done(ddr4_mig_calib_done),
        .ddr4_mig_sys_clk_clk_n(ddr4_mig_sys_clk_clk_n),
        .ddr4_mig_sys_clk_clk_p(ddr4_mig_sys_clk_clk_p),
        .pci_ep_rxn(pci_ep_rxn),
        .pci_ep_rxp(pci_ep_rxp),
        .pci_ep_txn(pci_ep_txn),
        .pci_ep_txp(pci_ep_txp),
        .pcie_ep_gt_ref_clk_clk_n(pcie_ep_gt_ref_clk_clk_n),
        .pcie_ep_gt_ref_clk_clk_p(pcie_ep_gt_ref_clk_clk_p),
        .pcie_ep_lnk_up(pcie_ep_lnk_up),
        .pcie_ep_perstn(pcie_ep_perstn));
endmodule
