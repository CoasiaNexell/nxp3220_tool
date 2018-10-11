#ifndef __BOOTHEADDR_H__
#define __BOOTHEADDR_H__

#define HEADER_ID				\
		((((uint32_t)'N')<< 0) |	\
		 (((uint32_t)'S')<< 8) |	\
		 (((uint32_t)'I')<<16) |	\
		 (((uint32_t)'H')<<24))

struct devboot_info {
	uint32_t device_addr;
	uint32_t reserved[3];
};

struct clock_info {
	uint32_t pll_pm;							// 0x00
	uint32_t pll_sk;							// 0x04
	uint32_t sscg;								// 0x08
};

struct ddr3_timing_task {
	/* Refresh Cycle & Refresh Interval */
	uint32_t tREFI			:16;		//  0		// tREFI    ps	  Refresh Interval
	uint32_t tRFC			:8;		// 16		// tRFC	    ps	  Refresh Cycle
	uint32_t reserved0		:8;		// 24 ~ 31

	/* Row */
	// Auto & Manual Refresh
	uint32_t tRAS_min		:6;		//  0		// tRAS       ps    Minimum Active to Precharge command time
	uint32_t tRC			:6;		//  6		// tRC        ps    Active to Active/Auto Refresh command time
	uint32_t tRCD			:4;		// 12		// tRCD       ps    Active to Read/Write command time
	uint32_t tRP			:4;		// 16		// tRP        ps    Precharge command period
	uint32_t tRRD			:4;		// 20		// tRRD	      ps
	uint32_t reserved1		:8;		// 24 ~ 31

	/* DATA */
	uint32_t RL			:8;		//  0 //
	uint32_t WL			:8;		//  8 //
	// (LPDDR 2/3)
	uint32_t tDQSCK			:4;		// 16		// tDQSCK     ps  DQS output access time from CK/CK#
	uint32_t tRTP			:4;		// 20		// tRTP       ps  Read to Precharge command delay
	uint32_t tWR			:4;		// 24		// tWR        ps  Write recovery time
	uint32_t tWTR			:4;		// 28		// tWTR       ps  Write to Read command delay

	/* Command And Address */
	uint32_t tFAW			:6;		//  0
	uint32_t reserved2		:6;		//  6
	uint32_t tMOD			:4;		// 12		// tMOD       ps   LOAD MODE to non-LOAD MODE command cycle time
	uint32_t tMRD			:4;		// 16		// tMRD       ps   Load Mode Register command cycle time
	uint32_t tCCD			:4;		// 20		// tCCD       ps   Cas to Cas command delay
	uint32_t tCKE			:4;		// 24		// tCKE       tCK   CKE minimum high or low pulse width
	uint32_t tCKESR			:4;		// 28		// tCKESR     tCK   tCKE_min + 1nCK

	/* Power Down */
	uint32_t tXS			:8;		//  0		// tXS
	uint32_t tXP			:8;		//  8		// tXP	    ps   Exit power down to a valid command
	uint32_t tXPR			:8;		// 16		// tXPR       ps   Exit Reset from CKE assertion to a valid command
	uint32_t reserved3		:8;		// 24

	/* Mixed calcurated Timing Parameter */
	uint32_t WR2PRECH		:6;		//  0
	uint32_t WR2RD			:6;		//  6
	uint32_t WR2RD_CSC		:6;		// 12
	uint32_t reserved4		:14;		// 18

	/* Calibration Timing */
	uint32_t tZQCS			:10;		//  0		// tZQCS      ps   ZQ Cal (Short) time
	uint32_t tZQoper		:10;		// 10		// tZQoper    ps   ZQ Cal (Long) time
	uint32_t tZQinit		:10;		// 20		// tZQinit    ps   ZQ Cal (Long) time
	uint32_t reserved5		:2;		// 30		// reserved2

	/* calcurated parameter */
	uint32_t tRCD_dclk 		:4;		//  0		// tRCD_dclk
	uint32_t tCCD_dclk		:4;		//  4		// tCCD_dclk
	uint32_t reserved6		:24;		//  8		// reserved
};	// 72Byte

struct ddr4_timing_task {
	// Row
	// Auto & Manual Refresh
	uint32_t tRAS_min		:6;		//  0
	uint32_t tRC			:6;		//  6
	uint32_t tRCD			:4;		// 10
	uint32_t tRP			:4;		// 14
	uint32_t tRRD_L			:6;		// 18
	uint32_t tRRD_S			:6;		// 24
	uint32_t reserved1		:2;		// 30

	// DATA
	uint32_t RL			:6;		//  0
	uint32_t WL			:6;		//  6
	// (LPDDR 2/3)
	uint32_t tDQSCK			:4;		// 12
	uint32_t tRTP			:4;		// 16
	uint32_t tWR			:4;		// 20
	uint32_t tWTR_L			:4;		// 24
	uint32_t tWTR_S			:4;		// 28 ~ 31

	/* Command And Address 1 */
	uint32_t tFAW			:6;		//  0
	uint32_t tMOD			:6;		//  6
	uint32_t tMRD			:4;		// 12

	/* Command And Address 2 */
	uint32_t tCCD_L			:4;		// 16
	uint32_t tCCD_S			:4;		// 20
	uint32_t tCKE			:4;		// 24
	uint32_t tCKESR			:4;		// 28 ~ 31

	/* Power Down */
	// Mixed calcurated Timing Parameter
	uint16_t WR2PRECH		:6;		//  0
	uint16_t WR2RD			:6;		//  6
	uint16_t WR2RD_CSC		:6;		// 12
	uint16_t tXS			:4;		// 18
	uint16_t tXP			:4;		// 22
	uint16_t tXPR			:4;		// 26
	uint16_t reserved2		:2;		// 30 ~ 31

	/* Calibration Timing */
	uint16_t tZQCS			:10;		//  0
	uint16_t tZQoper		:10;		// 10
	uint16_t tZQinit		:10;		// 20
	uint16_t reserved3		:2;		// 30

	/* calcurated parameter */
	uint32_t tRCD_dclk 		:4;		//  0	tRCD_dclk
	uint32_t tWTR_dclk		:4;		//  4
	uint32_t tRRD_L_dclk		:4;		//  8
	uint32_t reserved4		:20;		// 12	 reserved4
};

struct ddrinit_info {
	uint8_t	chip_num;							// 0x00
	uint8_t row_num;							// 0x01
	uint8_t col_num;							// 0x02
	uint8_t bank_num;							// 0x03
	uint8_t bg_num;								// 0x04
	uint8_t bus_width;							// 0x05
	uint8_t reserved[2];							// 0x06 ~ 0x08

	struct ddr3_timing_task ac_timing;					// 0x08 ~ 0x2C (0x20)
};


struct ddr3dev_drvdsinfo {
	uint8_t mr2_rtt_wr;							// 0x00 : MR2 - rtt_wr
	uint8_t mr1_ods;							// 0x01 : MR1 - rtt_ods
	uint8_t	mr1_rtt_nom;							// 0x02 : MR1 - rtt_nom
	uint8_t _reserved0;							// 0x03 : reserved0
	uint32_t _reserved1;							// 0x04 ~ 0x07 : reserved1
};


struct ddrphy_drvds_info {
	uint8_t adrctl_drive;							// 0x00 : address line drive strength
	uint8_t clk_drive;							// 0x01 : clock line drive strength
	uint8_t dq_dqs_drive;							// 0x02 : dq, dqs line drive strength
	uint8_t reserved0;							// 0x03 : reserved0
	uint32_t reserved1;							// 0x04 ~ 0x08 : reserved1
};

struct sdram_ddr_meminfo {
	struct ddrinit_info dii[5];						// 0x070 ~ 0x098 (0x8 x 5 = 0x28)
	struct ddr3dev_drvdsinfo dsinfo[5];					// 0x098 ~ 0x0C0 (0x8 x 5 = 0x28)
	struct ddrphy_drvds_info phy_dsinfo[5];					// 0x0C0 ~ 0x0E8 (0x8 x 5 = 0x28)
};

struct sbi_header {
	uint32_t load_size;							// 0x000
	uint32_t crc32; 							// 0x004
	uint32_t load_addr;							// 0x008
	uint32_t launch_addr;							// 0x00C

	struct devboot_info dbi;						// 0x010 ~ 0x020

	struct clock_info clk[5];						// 0x020 ~ 0x05C (0x3C)

	struct ddrinit_info dii;						// 0x05C ~ 0x084 (0x28)
	struct ddr3dev_drvdsinfo dsinfo;					// 0x084 ~ 0x08C (0x8)
	struct ddrphy_drvds_info phy_dsinfo;					// 0x08C ~ 0x094 (0x8)

	uint32_t cal_mode;							// 0x094

	uint32_t reserved1[22]; 						// 0x098 ~ 0x0F0

	uint32_t is_secure_os	:4;						// 0x0F0 : 0 ~ 3
	uint32_t is_n_secure_os :4;						// 0x0F0 : 4 ~ 7
	uint32_t is_sss_f	:4;						// 0x0F0 : 8 ~ 11
	uint32_t reserved2	:20;						// 0x0F0 : 12 ~ 31

	uint32_t serial_ch;							// 0x0F4

	uint32_t build_info;							// 0x0F8
	uint32_t signature;							// 0x0FC
} __attribute__ ((packed,aligned(16)));


struct asymmetric_key {
	uint8_t rsa_public_userkey[2048/8];
};

struct bootheader {
	struct sbi_header bi;							/* 0x000 ~ 0x1FC */
	unsigned char sign[2048/8];
	unsigned int  image[1];
};

struct nx_bootinfo {
	unsigned int LoadSize;				/* 0x000 */
	unsigned int CRC32;				/* 0x004 */
	unsigned int LoadAddr;				/* 0x008 */
	unsigned int StartAddr;				/* 0x00C */
	unsigned int nandretrycnt;			/* 0x010 */

	unsigned char _reserved3[256 - 4 * 7];		/* 0x014 ~ 0x0f7 */

	/* version */
	unsigned int buildinfo;				/* 0x0f8 */

	/* "NSIH": nexell system infomation header */
	unsigned int signature;				/* 0x0fc */
} __attribute__ ((packed, aligned(16)));

struct asymmetrickey {
	unsigned char rsapublicbootkey[2048/8];		/* 0x200 ~ 0x2ff */
	unsigned char rsapublicuserkey[2048/8];		/* 0x300 ~ 0x3ff */
};

struct nx_bootheader {
	struct nx_bootinfo bi;				/* 0x000 ~ 0x0ff */
	unsigned char bl1sign[2048/8];			/* 0x100 ~ 0x1ff */
	struct asymmetrickey rsa_public;		/* 0x200 ~ 0x3ff */
	unsigned int bl1image[1];			/* 0x400 ~ */
};

#endif // #ifndef __BOOTHEADDR_H__
