/***************************** Include Files *********************************/

#include <stdio.h>
#include <stdlib.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_exception.h"
#include "xgpio.h"
#include "xintc.h"
#include "xil_io.h"

/************************** Constant Definitions *****************************/

// base addresses
#define MEM_EN_BASEADDRESS          XPAR_XGPIO_0_BASEADDR
#define MEM_ADDR_BASEADDRESS        XPAR_XGPIO_1_BASEADDR
#define BRAM_IN_BASEADDRESS         XPAR_XBRAM_0_BASEADDR
#define BRAM_OUT_BASEADDRESS        XPAR_XBRAM_1_BASEADDR
#define INTC_BASEADDRESS            XPAR_XINTC_0_BASEADDR

// interrupt
#define XPAR_INTC_0_DEVICE_ID       0

// FIFO configuration
#define DATA_WIDTH                  29
#define FIFO_DEPTH                  64
#define FIFO_WIDTH                  (DATA_WIDTH + 1)

// parity checker configuration
#define PARITY_TYPE_ODD             1
#define PARITY_TYPE_EVEN            0
#define PARITY_BIT_MSB              1
#define PARITY_BIT_LSB              0
#define PARITY_TYPE                 PARITY_TYPE_EVEN
#define PARITY_BIT                  PARITY_BIT_MSB

// input BRAM: [31]=grant  [30]=valid  [29-0]=data+parity
#define BRAM_IN_MSB_DATA            (FIFO_WIDTH - 1)        // bit 29
#define BRAM_IN_BIT_VALID           (FIFO_WIDTH)            // bit 30
#define BRAM_IN_BIT_GRANT           (FIFO_WIDTH + 1)        // bit 31
#if (PARITY_BIT == PARITY_BIT_MSB)
    #define BRAM_IN_BIT_PARITY      BRAM_IN_MSB_DATA
#else
    #define BRAM_IN_BIT_PARITY      0
#endif

#define BRAM_IN_MASK_DATA           ((1u << FIFO_WIDTH) - 1)
#define BRAM_IN_MASK_VALID          (1u << BRAM_IN_BIT_VALID)
#define BRAM_IN_MASK_GRANT          (1u << BRAM_IN_BIT_GRANT)
#define BRAM_IN_MASK_PARITY         (1u << BRAM_IN_BIT_PARITY)
#if (PARITY_BIT == PARITY_BIT_MSB)
    #define BRAM_IN_MASK_DATA_RAW   ((1u << DATA_WIDTH) - 1)
#else
    #define BRAM_IN_MASK_DATA_RAW   (((1u << DATA_WIDTH) - 1) << 1)
#endif

// output BRAM: [31]=0  [30]=grant  [29]=valid  [28-0]=data
#define BRAM_OUT_MSB_DATA           (DATA_WIDTH - 1)        // bit 28
#define BRAM_OUT_BIT_VALID          (DATA_WIDTH)            // bit 29
#define BRAM_OUT_BIT_GRANT          (DATA_WIDTH + 1)        // bit 30

#define BRAM_OUT_MASK_DATA          ((1u << DATA_WIDTH) - 1)
#define BRAM_OUT_MASK_VALID         (1u << BRAM_OUT_BIT_VALID)
#define BRAM_OUT_MASK_GRANT         (1u << BRAM_OUT_BIT_GRANT)

// other
#define RAND_SEED                   12345
#define FAULT_RATE                  40

/************************** Type Definitions *********************************/

typedef struct {
    u32 data[FIFO_DEPTH];
    u8 valid[FIFO_DEPTH];
    int head;
    int tail;
    int count;
} Fifo_t;

/************************** Function Prototypes ******************************/

static int SetupInterruptSystem(XIntc *XIntcInstancePtr);
static void DoneInterruptHandler(void *CallbackRef);

static void fifo_init(Fifo_t *f);
static int fifo_push(Fifo_t *f, u32 data, u8 valid);
static int fifo_pop(Fifo_t *f, u32 *data, u8 *valid);
static inline int fifo_full(const Fifo_t *f);
static inline int fifo_empty(const Fifo_t *f);

static u32 generate_data(u8 valid, u8 grant, u8 error);
static inline u32 extract_data_raw(u32 data);
static inline u8 generate_parity(u32 data);
static inline void write_bram(u32 *mem_idx, u8 valid, u8 grant, u8 error);

static u32 run_traffic(void (*traffic_type)(u32 *mem_idx));
static inline void traffic_fill(u32 *mem_idx);
static inline void traffic_empty(u32 *mem_idx);
static void traffic_fill_and_empty(u32 *mem_idx);
static void traffic_always_grant(u32 *mem_idx);
static void traffic_random_grant(u32 *mem_idx);
static void traffic_inject_fault(u32 *mem_idx);

static void trigger_dut(XGpio *mem_en_device, XGpio *mem_addr_device, u32 mem_end_idx);
static void run_scoreboard(Fifo_t *f, u32 mem_end_idx);

/************************** Variable Definitions *****************************/

XIntc IntcInstance;
volatile u8 DoneInterrupt;

/************************** Function Definitions *****************************/

int main() {
    int Status;
    XGpio_Config *GpioConfigPtr;
    XGpio mem_en_device, mem_addr_device;
    XIntc_Config *IntcConfigPtr;

    // initialize GPIO as outputs
    GpioConfigPtr = XGpio_LookupConfig(MEM_EN_BASEADDRESS);
    XGpio_CfgInitialize(&mem_en_device, GpioConfigPtr, GpioConfigPtr->BaseAddress);
    XGpio_SetDataDirection(&mem_en_device, 1, 0);

    GpioConfigPtr = XGpio_LookupConfig(MEM_ADDR_BASEADDRESS);
    XGpio_CfgInitialize(&mem_addr_device, GpioConfigPtr, GpioConfigPtr->BaseAddress);
    XGpio_SetDataDirection(&mem_addr_device, 1, 0);

    // set up interrupt system
    IntcConfigPtr = XIntc_LookupConfig(INTC_BASEADDRESS);
    XIntc_Initialize(&IntcInstance, IntcConfigPtr->BaseAddress);
    SetupInterruptSystem(&IntcInstance);

    // set seed
    srand(RAND_SEED);

    // create golden reference model
    Fifo_t golden;
    fifo_init(&golden);

    // track BRAM
    u32 mem_idx;

    // FIFO fill & empty
    xil_printf("--------------------------------------------------\r\n");
    xil_printf("FIFO fill and empty\r\n");
    xil_printf("--------------------------------------------------\r\n");
    mem_idx = run_traffic(traffic_fill_and_empty);
    trigger_dut(&mem_en_device, &mem_addr_device, mem_idx);
    run_scoreboard(&golden, mem_idx);

    // random traffic at maximum bandwidth
    xil_printf("--------------------------------------------------\r\n");
    xil_printf("Random traffic, maximum bandwidth\r\n");
    xil_printf("--------------------------------------------------\r\n");
    mem_idx = run_traffic(traffic_always_grant);
    trigger_dut(&mem_en_device, &mem_addr_device, mem_idx);
    run_scoreboard(&golden, mem_idx);

    // random traffic at maximum bandwidth
    xil_printf("--------------------------------------------------\r\n");
    xil_printf("Random traffic, random grant\r\n");
    xil_printf("--------------------------------------------------\r\n");
    mem_idx = run_traffic(traffic_random_grant);
    trigger_dut(&mem_en_device, &mem_addr_device, mem_idx);
    run_scoreboard(&golden, mem_idx);

    // fault injection
    xil_printf("--------------------------------------------------\r\n");
    xil_printf("Random traffic, fault injection\r\n");
    xil_printf("--------------------------------------------------\r\n");
    mem_idx = run_traffic(traffic_inject_fault);
    trigger_dut(&mem_en_device, &mem_addr_device, mem_idx);
    run_scoreboard(&golden, mem_idx);

    return 0;
}

static int SetupInterruptSystem(XIntc *XIntcInstancePtr) {
    int Status;

    // connect device driver handler that will be called when an interrupt
    // for the device occurs
    Status = XIntc_Connect(XIntcInstancePtr, XPAR_INTC_0_DEVICE_ID,
        (XInterruptHandler)DoneInterruptHandler, (void *)(uintptr_t)0);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // start interrupt controller
    Status = XIntc_Start(XIntcInstancePtr, XIN_REAL_MODE);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // enable interrupt for device
    XIntc_Enable(XIntcInstancePtr, XPAR_INTC_0_DEVICE_ID);

    // initialize exception table
    Xil_ExceptionInit();

    // register the interrupt controller handler with exception table
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
        (Xil_ExceptionHandler)XIntc_InterruptHandler, XIntcInstancePtr);

    // enable exceptions
    Xil_ExceptionEnable();

    return XST_SUCCESS;
}

static void DoneInterruptHandler(void *CallbackRef) {
    DoneInterrupt = 0;
}

static void fifo_init(Fifo_t *f) {
    f->head = 0;
    f->tail = 0;
    f->count = 0;
}

static int fifo_push(Fifo_t *f, u32 data, u8 valid) {
    if (fifo_full(f)) {
        return -1;
    }

    // push data
    f->data[f->tail] = data;
    f->valid[f->tail] = valid;

    // move tail pointer
    f->tail = (f->tail + 1) % FIFO_DEPTH;
    f->count++;

    return 0;
}

static int fifo_pop(Fifo_t *f, u32 *data, u8 *valid) {
    if (fifo_empty(f)) {
        return -1;
    }

    // pop data
    *data = f->data[f->head];
    *valid = f->valid[f->head];

    // move head pointer
    f->head = (f->head + 1) % FIFO_DEPTH;
    f->count--;

    return 0;
}

static inline int fifo_full(const Fifo_t *f) {
    return (f->count == FIFO_DEPTH);
}

static inline int fifo_empty(const Fifo_t *f) {
    return (f->count == 0);
}

static u32 generate_data(u8 valid, u8 grant, u8 error) {
    // generate random data
    u32 data = (u32)rand() & BRAM_IN_MASK_DATA;

    // extract raw data
    u32 data_raw = extract_data_raw(data);

    // clear and set parity bit
    data &= ~BRAM_IN_MASK_PARITY;   // can be incorrect
    u8 parity = generate_parity(data_raw);
    data |= ((u32)parity << BRAM_IN_BIT_PARITY);

    // inject fault
    if (error) {
        u8 error_bit = rand() % (FIFO_WIDTH);
        data ^= (1u << error_bit);  // flip bit
    }

    // set valid and grant bits
    data |= ((u32)valid << BRAM_IN_BIT_VALID);
    data |= ((u32)grant << BRAM_IN_BIT_GRANT);

    return data;
}

static inline u32 extract_data_raw(u32 data) {
    #if (PARITY_BIT == PARITY_BIT_MSB)
        return data & BRAM_IN_MASK_DATA_RAW;
    #else
        return (data & BRAM_IN_MASK_DATA_RAW) >> 1;
    #endif
}

static inline u8 generate_parity(u32 data) {
    // XOR reduction tree
    data ^= data >> 16;
    data ^= data >> 8;
    data ^= data >> 4;
    data ^= data >> 2;
    data ^= data >> 1;

    u8 parity = data & 1;   // even parity
    #if (PARITY_TYPE == PARITY_TYPE_ODD)
        parity = !parity; 
    #endif

    return parity;
}

static inline void write_bram(u32 *mem_idx, u8 valid, u8 grant, u8 error) {
    u32 addr = BRAM_IN_BASEADDRESS + ((*mem_idx) * 4);
    u32 data = generate_data(valid, grant, error);
    Xil_Out32(addr, data);
    (*mem_idx)++;
}

static u32 run_traffic(void (*traffic_type)(u32 *mem_idx)) {
    u32 mem_idx = 0;

    // start
    for (int i = 0; i < 10; i++) {
        write_bram(&mem_idx, 0, 0, 0);
    }

    // call function pointer
    traffic_type(&mem_idx);

    // end
    for (int i = 0; i < 10; i++) {
        write_bram(&mem_idx, 0, 0, 0);
    }

    return mem_idx;
}

static inline void traffic_fill(u32 *mem_idx) {
    // fill FIFO
    for (int i = 0; i < FIFO_DEPTH; i++) {
        write_bram(mem_idx, 1, 0, 0);   // valid=1, grant=0, error=0
    }
}

static inline void traffic_empty(u32 *mem_idx) {
    // empty FIFO
    for (int i = 0; i < FIFO_DEPTH; i++) {
        write_bram(mem_idx, 0, 1, 0);   // valid=0, grant=1, error=0
    }
}

static void traffic_fill_and_empty(u32 *mem_idx) {
    traffic_fill(mem_idx);
    traffic_empty(mem_idx);
}

static void traffic_always_grant(u32 *mem_idx) {
    u8 valid = 0;
    u8 grant = 0;
    u8 error = 0;

    for (int i = 0; i < 2048; i++) {
        valid = rand() & 1;
        grant = 1;
        write_bram(mem_idx, valid, grant, error);
    }
    traffic_empty(mem_idx);
}

static void traffic_random_grant(u32 *mem_idx) {
    u8 valid = 0;
    u8 grant = 0;
    u8 error = 0;

    for (int i = 0; i < 2048; i++) {
        valid = rand() & 1;
        grant = rand() & 1;
        write_bram(mem_idx, valid, grant, error);
    }
    traffic_empty(mem_idx);
}

static void traffic_inject_fault(u32 *mem_idx) {
    u8 valid = 0;
    u8 grant = 0;
    u8 error = 0;

    for (int i = 0; i < 2048; i++) {
        valid = rand() & 1;
        grant = rand() & 1; 
        error = ((rand() % 100) < FAULT_RATE)? 1 : 0;
        write_bram(mem_idx, valid, grant, error);
    }
    traffic_empty(mem_idx);
}

static void trigger_dut(XGpio *mem_en_device, XGpio *mem_addr_device, u32 mem_end_idx) {
    DoneInterrupt = 1;
    
    // set target memory address
    XGpio_DiscreteWrite(mem_addr_device, 1, (mem_end_idx * 4));

    // pulse start signal
    XGpio_DiscreteWrite(mem_en_device, 1, 1);   // set high
    XGpio_DiscreteWrite(mem_en_device, 1, 0);   // set low

    // wait for DUT to finish processing
    while (1) {
        if (!DoneInterrupt) {
            break;
        }
    }
}

static void run_scoreboard(Fifo_t *f, u32 mem_end_idx) {
    u32 sb_num_push       = 0;  // number of data transmitted (good and bad)
    u32 sb_num_parity_err = 0;  // number of bad data transmitted
    u32 sb_num_pass       = 0;  // number of good data correctly received
    u32 sb_num_fail       = 0;  // number of good data incorrectly received
    u32 sb_num_drop_pass  = 0;  // number of bad data correctly dropped
    u32 sb_num_drop_fail  = 0;  // number of bad data incorrectly dropped
    u32 sb_num_grant_err  = 0;  // number of incorrect grants
    u32 sb_num_valid_err  = 0;  // number of incorrect valids

    for (u32 i = 0; i <= mem_end_idx; i++) {
        // for popping data
        u32 f_data;
        u8 f_valid;

        // read from input and output BRAMs
        u32 bram_in = Xil_In32(BRAM_IN_BASEADDRESS + (i * 4));
        u32 bram_out = Xil_In32(BRAM_OUT_BASEADDRESS + (i * 4));

        // extract input and output signals of DUT
        u32 data_i = (bram_in & BRAM_IN_MASK_DATA);
        u8 valid_i = (bram_in & BRAM_IN_MASK_VALID)? 1 : 0;
        u8 grant_i = (bram_in & BRAM_IN_MASK_GRANT)? 1 : 0;

        u32 data_o = (bram_out & BRAM_OUT_MASK_DATA);
        u8 valid_o = (bram_out & BRAM_OUT_MASK_VALID)? 1 : 0;
        u8 grant_o = (bram_out & BRAM_OUT_MASK_GRANT)? 1 : 0;

        // check grant and valid
        u8 sb_expect_grant = (f->count < FIFO_DEPTH);
        u8 sb_expect_valid = (f->count > 0);
        u8 head_valid = f->valid[f->head];

        if (grant_o != sb_expect_grant) {
            sb_num_grant_err++;
        }
        if (valid_o != (sb_expect_valid && head_valid)) {
            sb_num_valid_err++;
        }

        // push transaction: store everything (both good and bad)
        if (valid_i && sb_expect_grant) {
            u32 data_raw = extract_data_raw(data_i);
            u8 parity_expected = generate_parity(data_raw);
            u8 parity_actual = (data_i & BRAM_IN_MASK_PARITY)? 1 : 0;
            u8 data_error = (parity_actual != parity_expected)? 1 : 0;
            fifo_push(f, data_raw, !data_error);

            sb_num_push++;
            if (data_error) {
                sb_num_parity_err++;
            }
        }

        // pop transaction: bad word at head
        if (sb_expect_valid && !head_valid) {
            if (valid_o) {
                sb_num_drop_fail++;
            } else {
                sb_num_drop_pass++;
            }
            fifo_pop(f, &f_data, &f_valid);
        }
        // pop transaction: good word at head
        else {
            if (grant_i && sb_expect_valid && head_valid) {
                fifo_pop(f, &f_data, &f_valid);
                if (valid_o && (data_o == f_data)) {
                    sb_num_pass++;
                } else {
                    sb_num_fail++;
                }
            }
        }
    }

    xil_printf("Number of data transmitted (good and bad) = %5d\r\n", sb_num_push);
    xil_printf("Number of good data transmitted           = %5d\r\n", sb_num_push-sb_num_parity_err);
    xil_printf("Number of good data correctly received    = %5d\r\n", sb_num_pass);
    xil_printf("Number of good data incorrectly received  = %5d\r\n", sb_num_fail);
    xil_printf("Number of bad data transmitted            = %5d\r\n", sb_num_parity_err);
    xil_printf("Number of bad data correctly dropped      = %5d\r\n", sb_num_drop_pass);
    xil_printf("Number of bad data incorrectly dropped    = %5d\r\n", sb_num_drop_fail);
    xil_printf("Number of incorrect grants                = %5d\r\n", sb_num_grant_err);
    xil_printf("Number of incorrect valids                = %5d\r\n", sb_num_valid_err);
    xil_printf("--------------------------------------------------\r\n");

    if ((sb_num_fail == 0) && (sb_num_drop_fail == 0) && 
        (sb_num_pass == (sb_num_push - sb_num_parity_err)) && 
        (sb_num_drop_pass == sb_num_parity_err) &&
        (sb_num_grant_err == 0) && (sb_num_valid_err == 0)) {
        xil_printf("PASS\r\n");
    } else {
        xil_printf("FAIL\r\n");
    }
    xil_printf("\r\n");
}