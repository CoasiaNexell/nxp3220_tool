/*
 * Copyright (C) 2012 Nexell Co., All Rights Reserved
 * Nexell Co. Proprietary & Confidential
 *
 * NEXELL INFORMS THAT THIS CODE AND INFORMATION IS PROVIDED "AS IS" BASE
 * AND WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING
 * BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS
 * FOR A PARTICULAR PURPOSE.
 *
 * Module	: bl0
 * File		: nx_antares_bootheader.h
 * Description	: This must be synchronized with NSIH.txt
 * Author	: hans
 * History	: 2017.10.09 create
 */

#ifndef __NX_BOOTHEADER_H__
#define __NX_BOOTHEADER_H__

#define HEADER_ID				\
		((((unsigned int)'N')<< 0) |	\
		 (((unsigned int)'S')<< 8) |	\
		 (((unsigned int)'I')<<16) |	\
		 (((unsigned int)'H')<<24))


struct nx_bootinfo {
	unsigned int LoadSize;				/* 0x000 */
	unsigned int CRC32;				/* 0x004 */
	unsigned int LoadAddr;				/* 0x008 */
	unsigned int StartAddr;				/* 0x00C */
	unsigned int nandretrycnt;			/* 0x010 */

#if 0
	unsigned char _reserved3[15];			/* 0x014 ~ 0x050 */
	unsigned int device_addr;			// 0x50
	unsigned char _reserved3[41];			/* 0x014 ~ 0x0f7 */

#else
	unsigned char _reserved3[256 - 4 * 7];		/* 0x014 ~ 0x0f7 */
#endif
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

struct nx_memmap {
	unsigned int bl1image[(0x10000 -
			sizeof(struct nx_bootinfo) -
			(2048 / 8) -			/* sizeof(bl1sign) */
			sizeof(struct asymmetrickey)) / 4];
	struct nx_bootinfo bi;
	unsigned char bl1sign[2048/8];
	struct asymmetrickey rsa_public;
};

#endif
