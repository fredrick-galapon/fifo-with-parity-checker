`ifndef CONFIG_VH
`define CONFIG_VH

// FIFO
`define DATA_WIDTH          32
`define FIFO_DEPTH          128

// parity checker
`define PARITY_TYPE         `PARITY_TYPE_EVEN
`define PARITY_BIT          `PARITY_BIT_MSB

`endif // CONFIG_VH