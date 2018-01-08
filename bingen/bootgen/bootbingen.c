#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>

#include "bootbingen.h"

/* Define the Macro */
#define BOOT_BINGEN_VER		0001

#define POLY			0xEDB88320L

#define DEF_LAUNCHADDR		0xFFFF0000
#define DEF_LOADADDR		0xFFFF0000

#define NXP3220_SRAM_SIZE	0x10000
#define BOOTKEY_SIZE		256
#define USERKEY_SIZE		256
#define SHA256_ENC_SIZE		256

/* Global Variable */
struct bootheader *g_pbh;

char *g_nsih_name		= 0;
char *g_input_name		= 0;
char *g_type_name		= 0;
unsigned int g_load_addr	= 0;
unsigned int g_launch_addr	= 0;

unsigned int g_inputsize	= 0;
unsigned int g_outputsize	= 0;

static unsigned int hex_to_int(const char *string)
{
	char ch;
	unsigned int ret = 0;

	while (ch = *string++) {
		ret <<= 4;
		if (ch >= '0' && ch <= '9') {
			ret |= ch - '0' +  0;
		} else if (ch >= 'a' && ch <= 'f') {
			ret |= ch - 'a' + 10;
		} else if (ch >= 'A' && ch <= 'F') {
			ret |= ch - 'A' + 10;
		}
	}

	return ret;
}

static unsigned int get_fcs(unsigned int fcs, unsigned int data)
{
	int i;

	fcs ^= data;
	for (i = 0; i < 32; i++) {
		if (fcs & 0x01)
			fcs = (fcs >> 1) ^ POLY;
		else
			fcs >>= 1;
	}
	return fcs;
}

static int calc_crc(char *buf, int size)
{
	unsigned int crc = 0, i;

	for (i = 0; i < size / 4; i++)
		crc = get_fcs(crc, buf[i]);

	return crc;
}

// Nexell System Information Header
static int process_nsih(const char *pfilename, unsigned char *pOutData)
{
	FILE *fp;
	int writesize, skipline, line, bytesize, i;
	unsigned char ch;
	unsigned int val = 0, *pBuf = (unsigned int *)pOutData;

	fp = fopen(pfilename, "rb");
	if (!fp) {
		printf("Process_NSIH : ERROR - Failed to open %s file.\n",
				pfilename);
		return 0;
	}

	bytesize = 0;
	writesize = 0;
	skipline = 0;
	line = 0;

	while (0 == feof(fp)) {
		ch = fgetc(fp);

		if (skipline == 0) {
			if (ch >= '0' && ch <= '9') {
				val <<= 4;
				val |= ch - '0';
				writesize++;
			} else if (ch >= 'a' && ch <= 'f') {
				val <<= 4;
				val |= ch - 'a' + 10;
				writesize++;
			} else if (ch >= 'A' && ch <= 'F') {
				val <<= 4;
				val |= ch - 'A' + 10;
				writesize++;
			} else {
				if (writesize == 8) {
					*pBuf++ = val;
					bytesize+=4;
				} else {
					if (writesize) {
						printf("Process_NSIH : Error at %d line.\n", line + 1);
						break;
					}
				}
				writesize = 0;
				skipline = 1;
			}
		}

		if (ch == '\n') {
			line++;
			skipline = 0;
			val = 0;
		}
	}

	printf("Process_NSIH : %d line processed.\n", line + 1);
	printf("Process_NSIH : %d bytes generated.\n", bytesize);

	fclose(fp);

	return bytesize;
}


/* ------------------------------------------------------------------------------ */
/*	  @ Function :
  *	  @ Param    : None.
  *	  @ Remak   : Boot Bingen Generation Information.
  */
void print_bingen_info( void )
{
	printf( "----------------------------------------------------\n" );
	printf( " %s Binary file Information.        \n", "NXP3220" );
	printf( " NSIH   Text   File : %s		\n", g_nsih_name   ? (char*)g_nsih_name   : "NULL" );
	printf( " Input  Binary File : %s		\n", g_input_name  ? (char*)g_input_name  : "NULL" );
//	printf( " Output Binary File : %s		\n", g_output_name ? (char*)g_output_name : "NULL" );
//	printf( " Input  Binary size : %d Byte (%dKB)	\n", g_inputsize   ? g_inputsize   : 0, (g_inputsize + 1024-1 )/1024);
	printf( " Output Binary size : %d Byte (%dKB)   \n", g_outputsize  ? g_outputsize  : 0, (g_outputsize + 1024-1 )/1024);
	printf( "----------------------------------------------------\n" );
	printf( " NSIH(Header) Information.             \n" );
	printf( "  -> DeviceAddr : %8Xh			\r\n", g_pbh->bi.device_addr );
//	printf( "  -> DeviceType : %8Xh			\r\n", g_pbh-> );
	printf( "  -> LoadSize	: %8Xh			\r\n", g_pbh->bi.load_size   );
	printf( "  -> LoadAddr	: %8Xh			\r\n", g_pbh->bi.load_addr   );
	printf( "  -> LauchAddr	: %8Xh			\r\n", g_pbh->bi.launch_addr );
	printf( "  -> SigNature	: %8Xh			\r\n", g_pbh->bi.signature );
	printf( "  -> CRC32	: %8Xh			\r\n", g_pbh->bi.crc32 );
}

static void usage(void)
{
	printf("--------------------------------------------------------------------------\n");
	printf(" Release  Version         : Ver.%04d                                      \n", BOOT_BINGEN_VER );
	printf(" Author & Version Manager : Deoks (S/W 1Team)                             \n");
	printf("--------------------------------------------------------------------------\n");
	printf(" Usage : This will tell you How to Use Help.					          \n");
	printf("--------------------------------------------------------------------------\n" );
	printf("   -h [HELP]                     : show usage                             \n");
	printf("   -t [BL1/OTHER]		 : What is the Boot? (mandatory)          \n");
	printf("   	->[BL1]								  \n");
	printf("   	->[OTHER]							  \n");
	printf("   -n [file name]                : [NSIH] file name  (mandatory)     	  \n");
	printf("   -i [file name]                : [INPUT]file name  (mandatory)	  \n");
	printf("   -l [load address]             : Binary Load  Address              	  \n");
	printf("   	-> Default Load	  Address : Default NSIH.txt   			  \n");
	printf("   -e [launch address]           : Binary Launch Addres             	  \n");
	printf("   	-> Default Launch Address : Default NSIH.txt   			  \n");
	printf("--------------------------------------------------------------------------\n");
	printf("\n");
	printf(" Usage: How to use the program? 			                              \n");
	printf(" Ubuntu  > How to use?                                                    \n");
	printf("  #>./bootgen -h 0 or ./BOOT_BINGEN \n");
	printf("  #>./bootgen -t Other -i bootimage  -l FFFF0000 -e FFFF0000              \n");
	printf("\n");
}

static int keyfile_read(char *name, char *buf, int size)
{
	FILE *fptr = NULL;
	int fsize;

	fptr = fopen(name, "r");
	printf("%s !!!!! \r\n", name);
	if (!fptr) {
		printf("%s open failed!! check file!!\n", name);
		goto err_end;
	} else {
		fsize = fread(buf, 1, size, fptr);
		fclose(fptr);
		if (fsize != size) {
			printf("%s file size error (%d)!! \r\n", name, fsize);
			return -2;
		}
	}

	return fsize;

err_end:
	fclose(fptr);

	return  -1;
}

static int image_read(char *name, char *buf, int size)
{
	FILE *fptr = NULL;
	int fsize;

	fptr = fopen(name, "r");
	if (!fptr) {
		printf("%s open failed!! check file!!\n", name);
		goto err_end;
	} else {
		fsize = fread(buf, 1, size, fptr);
		fclose(fptr);
		if (fsize % 0x10)
			fsize = (((fsize + 15) >> 4) << 4);
	}

	return fsize;

err_end:
	fclose(fptr);

	return  -1;
}

static int image_write(char *name, char *buf, int size)
{
	FILE *fptr = NULL;
	int fsize;

	fptr = fopen(name, "wb+");

	if (!fptr) {
		printf("%s open failed!! check file!!\n", name);
		goto err_end;
	} else {
		/* generate the 16byte aligan */
		fsize = fwrite(buf, 1, size, fptr);
		fclose(fptr);
	}

	return fsize;

err_end:
	fclose(fptr);

	return	-1;
}

int main(int argc, char **argv)
{
	unsigned int  *pout;
	unsigned char *pbuf;
	struct bootheader bh;


	unsigned int param_opt 	= 0;
	char fname[100];
	int is_bl1 = 0, fsize, crc;
	int ret = -1;

	pout = (unsigned int *)malloc(NXP3220_SRAM_SIZE);
	pbuf = (unsigned char*)pout;
	g_pbh = ((struct bootheader *)pbuf);

	if (argc <= 1) {
		usage();
		return 1;
	}

	while (-1 !=(param_opt = getopt(argc, argv, "h:n:i:t:l:s:"))) {
		switch (param_opt) {
			case 'h':
				usage();
				return 1;
			case 'n':
				g_nsih_name 	= strdup(optarg);
				break;
			case 'i':
				g_input_name 	= strdup(optarg);
				break;
			case 't':
				g_type_name	= strdup(optarg);
				break;
			case 'l':
				g_load_addr 	= hex_to_int(optarg);
				break;
			case 's':
				g_launch_addr	= hex_to_int(optarg);
				break;

			default:
				printf("unknown option_num parameter\r\n");
				break;
		}
	}

	if (g_load_addr == 0)
		g_load_addr = DEF_LOADADDR;
	if (g_launch_addr == 0)
		g_launch_addr = DEF_LAUNCHADDR;

	if (g_nsih_name == NULL) {
		g_nsih_name = "NSIH.txt";
		printf("Did not enter the NSIH files.\r\n");
		printf("This has been used as the default NSIH file.\r\n");
	} else {
		fsize = process_nsih(g_nsih_name, pbuf);
		g_outputsize += fsize;
		if (fsize != 512) {
//		if (fsize != sizeof(struct bootheader)) {
			printf("nsih generation size error:%d\r\n", fsize);
			return -1;
		}
	}

	if (g_input_name == NULL) {
		g_input_name = "antares_bl1.bin";
		printf("Did not enter the Binary files.\r\n");
		printf("This has been used as the default antares_bl1.bin.\r\n");
	}


	if (g_type_name == NULL) {
		g_type_name = "BL1";
		is_bl1 = 1;
		printf("Did not enter the Binary type!! \r\n");
		printf("This has been used as the default BL1! \r\n");
	} else {
		if (!strcmp(g_type_name, "BL1"))
			is_bl1 = 1;
		else
			is_bl1 = 0;
	}

	if (is_bl1) {
		/* RSA Public Boot Key */
		memset(fname, 0, 100);
		sprintf(fname, "%s.pub", g_input_name);
		if (keyfile_read(fname, bh.rsa_public.rsapublicbootkey, BOOTKEY_SIZE) < 0) {
			return -1;
		}
		memcpy((void*)(pbuf + g_outputsize),
			(void *)bh.rsa_public.rsapublicbootkey, BOOTKEY_SIZE);
		g_outputsize += BOOTKEY_SIZE;
	}

	/* SHA256 Hash */
	memset(fname, 0, 100);
	sprintf(fname, "%s.sig", g_input_name);
	if (keyfile_read(fname, bh.rsa_public.rsaencryptedsha256hash, SHA256_ENC_SIZE) < 0) {
		return -2;
	}
	memcpy((void*)(pbuf + g_outputsize),
		(void *)bh.rsa_public.rsaencryptedsha256hash, SHA256_ENC_SIZE);
	g_outputsize += SHA256_ENC_SIZE;

	if (is_bl1) {
		/* RSA Public User Key */
		memset(fname, 0, 100);
		sprintf(fname, "%s.usr", g_input_name);
		if (keyfile_read(fname, bh.rsa_public.rsapublicuserkey, USERKEY_SIZE) < 0)
			return -3;
		memcpy((void*)(pbuf + g_outputsize),
			(void *)bh.rsa_public.rsapublicuserkey, USERKEY_SIZE);
		g_outputsize += USERKEY_SIZE;
	}

	/* Boot Image */
	fsize = image_read(g_input_name, &pbuf[g_outputsize - 1],
			(NXP3220_SRAM_SIZE - sizeof(struct bootheader)));
	/* CRC the Boot Image  */
	crc = calc_crc(pbuf, fsize);
	g_outputsize += fsize;

	g_pbh->bi.crc32 = crc;
	g_pbh->bi.load_size = fsize;
	g_pbh->bi.load_addr = g_load_addr;
	g_pbh->bi.launch_addr = g_launch_addr;

	/* Final Output File Data */
	memset(fname, 0, 100);
	sprintf(fname, "%s.img", g_input_name);
	image_write(fname, (char *)pout, g_outputsize);

	/* boot-bingen information */
	print_bingen_info();

	free(pout);

	return 0;
}
