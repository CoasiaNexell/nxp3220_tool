#ifndef __BOOT_BINGEN_H__
#define __BOOT_BINGEN_H__

#define HEADER_ID				\
		((((unsigned int)'N')<< 0) |	\
		 (((unsigned int)'S')<< 8) |	\
		 (((unsigned int)'I')<<16) |	\
		 (((unsigned int)'H')<<24))

struct clock_info
{
	unsigned int pll_pm[5];							// 0x05C ~ 0x06C
	unsigned int pll_sk[5];							// 0x070 ~ 0x080
};

struct ddr3_timing_task {
	/* Row */
	// Auto & Manual Refresh
	unsigned int tRAS_min			:6;		// 0  // tRAS       ps    Minimum Active to Precharge command time
	unsigned int tRC			:6;		// 6  // tRC        ps    Active to Active/Auto Refresh command time
	unsigned int tRCD			:4;		// 12 // tRCD       ps    Active to Read/Write command time
	unsigned int tRP			:4;		// 16 // tRP        ps    Precharge command period
	unsigned int tRRD			:4;		// 20
	unsigned int reserved0			:8;		// 24 ~ 31

	/* DATA */
	unsigned int RL				:8;		// 0 //
	unsigned int WL				:8;		// 8 //
	// (LPDDR 2/3)
	unsigned int tDQSCK			:4;		// 16 // tDQSCK     ps  DQS output access time from CK/CK#
	unsigned int tRTP			:4;		// 20 // tRTP       ps  Read to Precharge command delay
	unsigned int tWR			:4;		// 24 // tWR        ps  Write recovery time
	unsigned int tWTR			:4;		// 28 // tWTR       ps  Write to Read command delay

	/* Command And Address */
	unsigned int tFAW			:6;		// 0
	unsigned int reserved1			:6;		// 6
	unsigned int tMOD			:4;		// 12 // tMOD       ps   LOAD MODE to non-LOAD MODE command cycle time
	unsigned int tMRD			:4;		// 16 // tMRD       ps   Load Mode Register command cycle time
	unsigned int tCCD			:4;		// 20 // tCCD       ps   Cas to Cas command delay
	unsigned int tCKE			:4;		// 24 // tCKE       tCK   CKE minimum high or low pulse width
	unsigned int tCKESR			:4;		// 28 // tCKESR     tCK   tCKE_min + 1nCK

	/* Power Down */
	// Mixed calcurated Timing Parameter
	unsigned int WR2PRECH			:6;		// 0
	unsigned int WR2RD			:6;		// 6
	unsigned int WR2RD_CSC			:6;		// 12
	unsigned int tXS			:2;		// 18 // tXS
	unsigned int tXP			:4;		// 20 // tXP	      ps   Exit power down to a valid command
	unsigned int tXPR			:6;		// 24 // tXPR       ps   Exit Reset from CKE assertion to a valid command

	/* Calibration Timing */
	unsigned int tZQCS			:10;		//  0 // tZQCS      ps   ZQ Cal (Short) time
	unsigned int tZQoper			:10;		// 10 // tZQoper    ps   ZQ Cal (Long) time
	unsigned int tZQinit			:10;		// 20 // tZQinit    ps   ZQ Cal (Long) time
	unsigned int reserved2			:2;		// 30 // reserved2

	/* calcurated parameter */
	unsigned int tRCD_dclk 			:4;		// tRCD_dclk
	unsigned int tCCD_dclk			:4;		// tCCD_dclk
	unsigned int reserved3			:24;		// reserved 3
};	// 72Byte

struct ddr4_timing_task {
	// Row
	// Auto & Manual Refresh
	unsigned int tRAS_min			:6;		// 0
	unsigned int tRC			:6;		// 6
	unsigned int tRCD			:4;		// 10
	unsigned int tRP			:4;		// 14
	unsigned int tRRD_L			:6;		// 18
	unsigned int tRRD_S			:6;		// 24
	unsigned int reserved1			:2;		// 30

	// DATA
	unsigned int RL				:6;		//  0
	unsigned int WL				:6;		//  6
	// (LPDDR 2/3)
	unsigned int tDQSCK			:4;		// 12
	unsigned int tRTP			:4;		// 16
	unsigned int tWR			:4;		// 20
	unsigned int tWTR_L			:4;		// 24
	unsigned int tWTR_S			:4;		// 28 ~ 31

	/* Command And Address 1 */
	unsigned int tFAW			:6;		// 0
	unsigned int tMOD			:6;		// 6
	unsigned int tMRD			:4;		// 12

	/* Command And Address 2 */
	unsigned int tCCD_L			:4;		// 16
	unsigned int tCCD_S			:4;		// 20
	unsigned int tCKE			:4;		// 24
	unsigned int tCKESR			:4;		// 28 ~ 31

	/* Power Down */
	// Mixed calcurated Timing Parameter
	unsigned short WR2PRECH			:6;		//  0
	unsigned short WR2RD			:6;		//  6
	unsigned short WR2RD_CSC		:6;		// 12
	unsigned short tXS			:4;		// 18
	unsigned short tXP			:4;		// 22
	unsigned short tXPR			:4;		// 26
	unsigned short reserved2		:2;		// 30 ~ 31

	/* Calibration Timing */
	unsigned short tZQCS			:10;		//
	unsigned short tZQoper			:10;		//
	unsigned short tZQinit			:10;		//
	unsigned short reserved3		:2;		//

	/* calcurated parameter */
	unsigned int tRCD_dclk 			:4;		// tRCD_dclk
	unsigned int tWTR_dclk			:4;
	unsigned int tRRD_L_dclk		:4;
	unsigned int reserved4			:20;		// reserved4
};


struct ddrinit_info {
	unsigned char chip_num;					// 0x00
	unsigned char row_num;					// 0x01
	unsigned char col_num;					// 0x02
	unsigned char bg_num;					// 0x03
	unsigned char bank_num;					// 0x04
	unsigned char bus_width;				// 0x05

#if defined(DDR3)
	struct ddr3_timing_task ac_timing;
#elif defined(DDR4)
	struct ddr4_timing_task ac_timing;
#endif
};

#if defined(DDR3)
struct ddr3dev_drvdsinfo {
	unsigned char mr2_rtt_wr;
	unsigned char mr1_ods;
	unsigned char	mr1_rtt_nom;
	unsigned char _reserved0;
	unsigned int _reserved1;
};
#elif defined(DDR4)
struct ddr4dev_drvdsinfo {
	unsigned char mr2_rtt_wr;
	unsigned char mr1_ods;
	unsigned char	mr1_rtt_nom;
	unsigned char mr5_rtt_park;
	unsigned int _reserved1;
};
#endif

struct ddrphy_drvds_info
{
	unsigned char adrctl_drive;
	unsigned char clk_drive;
	unsigned char dq_dqs_drive;
};


struct sbi_header
{
	unsigned int vector[8];							// 0x000 ~ 0x01C
	unsigned int vector_rel[8];						// 0x020 ~ 0x03C

	unsigned int load_size;							// 0x040
	unsigned int crc32;							// 0x044
	unsigned int load_addr;							// 0x048
	unsigned int launch_addr;						// 0x04C

	unsigned int device_addr;						// 0x050

//	union nx_deviceboot_info dbi;						// 0x050~0x058

	struct clock_info clk;							// 0x5C ~ 0x80

	struct ddrinit_info dii;						// 0x088 ~ 0x0AC

#if defined(DDR3)
	struct ddr3dev_drvdsinfo dsinfo;					// 0x0B0
#elif defined(DDR4)
	struct ddr4dev_drvdsinfo dsinfo;
#endif

#if 0
#if defined(MEM_TYPE_LPDDR23)
	struct nx_lpddr3dev_drvds_info	lpddr3_dsinfo;				// 0x0B0
#endif
#endif
	struct ddrphy_drvds_info phy_dsinfo;					// 0x0B4 ~ 0x0BC

	unsigned int reserved0[6];						// 0x0C4 ~ 0x0D8

	unsigned int stub[(0x1ec-0x0dc)/4];					// 0x0DC ~ 0x1EC

	unsigned int reserved1[3];						// 0x1EC ~ 0x1F4

	unsigned int build_info;						// 0x1F8

	unsigned int signature;							// 0x1FC    "NSIH"
} __attribute__ ((packed,aligned(16)));


struct nx_bootinfo {
	unsigned int vector[8];				/* 0x000 ~ 0x01f */
	unsigned int vector_rel[8];			/* 0x020 ~ 0x03f */

	unsigned int LoadSize;				/* 0x040 */
	unsigned int CRC32;				/* 0x044 */
	unsigned int LoadAddr;				/* 0x048 */
	unsigned int StartAddr;				/* 0x04C */

	unsigned char _reserved3[512 - 4 * 22];		/* 0x050 ~ 0x1f7 */

	/* version */
	unsigned int buildinfo;				/* 0x1f8 */

	/* "NSIH": nexell system infomation header */
	unsigned int signature;				/* 0x1fc */
} __attribute__ ((packed, aligned(16)));

struct asymmetrickey {
	unsigned char rsapublicbootkey[2048/8];		/* 0x200 ~ 0x2ff */
	unsigned char rsaencryptedsha256hash[2048/8];	/* 0x400 ~ 0x4ff */
	unsigned char rsapublicuserkey[2048/8];		/* 0x300 ~ 0x3ff */
};

struct bootheader {
//	struct nx_bootinfo bi;
	struct sbi_header bi;
	struct asymmetrickey rsa_public;
};

#endif	// #ifndef __BOOT_BINGEN_H__