#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/md.h"
#include "mbedtls/rsa.h"
#include "mbedtls/sha256.h"
#include "mbedtls/md.h"
#include "mbedtls/x509.h"

#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "nx_antares_bootheader.h"
#include <unistd.h>

#include <stdio.h>
#define mbedtls_snprintf   snprintf
#define mbedtls_printf     printf

#define POLY 0xEDB88320L

void swap(char *buf, int size)
{
	unsigned int swap, index, reverse_index = (size - 1);

	for (index = 0; index < (size / 2); index++, reverse_index--) {
		swap = buf[reverse_index];
		buf[reverse_index] = buf[index];
		buf[index] = swap;
	}
}

unsigned int get_fcs(unsigned int fcs, unsigned char data)
{
	int i;

	fcs ^= (unsigned int)data;
	for (i = 0; i < 8; i++) {
		if (fcs & 0x01)
			fcs = (fcs >> 1) ^ POLY;
		else
			fcs >>= 1;
	}

	return fcs;
}

/* @brief: calcurate the CRC function */
unsigned int calc_crc(unsigned char *data, int size)
{
	unsigned int fcs = 0xffffffff;
	int i;

	for (i = 0; i < size; i++)
		fcs = get_fcs(fcs, data[i]);

	return fcs;
}

/* @brief: convert the hex to integra */
unsigned int hexa_to_int(const char *string)
{
	char ch;
	unsigned int ret = 0;

	while (ch = *string++) {
		ret <<= 4;
		if (ch >= '0' && ch <= '9')
			ret |= ch - '0' +  0;
		else if (ch >= 'a' && ch <= 'f')
			ret |= ch - 'a' + 10;
		else if (ch >= 'A' && ch <= 'F')
			ret |= ch - 'A' + 10;
	}

	return ret;
}

/* Convert hexadecimal strings to integers.  */
unsigned int deca_to_int(const char *string)
{
	char ch;
	unsigned int ret = 0;

	while (ch = *string++) {
		ret *= 10;
		if (ch >= '0' && ch <= '9')
			ret += ch - '0';
		else
			return -1;
	}

	return ret;
}

/* It Converted to Uppercase.  */
void to_upper(char* string)
{
	char *str = (char*)string;
	int ndx = 0;

	for (ndx = 0; ndx < strlen(str); ndx++)
		str[ndx] = (char)toupper(str[ndx]);
}

/* It Converted to Lowercase.  */
void to_lower(char* string)
{
	char* str = (char*)string;
	int ndx = 0;

	for (ndx = 0; ndx < strlen(str); ndx++)
		str[ndx] = (char)tolower(str[ndx]);
}

int process_nsih(const char *fname, unsigned char *buf)
{
	FILE *fp;
	char ch;
	int write_size, skip_line, line, byte_size, i;
	unsigned int write_value;

	fp = fopen(fname, "rb");
	if (!fp) {
		mbedtls_printf( "process_nsih : ERROR - Failed to open %s file.\n", fname );
		return 0;
	}

	byte_size = 0;
	write_value = 0;
	write_size = 0;
	skip_line = 0;
	line = 0;

	while (0 == feof(fp)) {
		ch = fgetc( fp );

		if (skip_line == 0) {
			if (ch >= '0' && ch <= '9') {
				write_value = write_value * 16 + ch - '0';
				write_size += 4;
			} else if (ch >= 'a' && ch <= 'f') {
				write_value = write_value * 16 + ch - 'a' + 10;
				write_size += 4;
			} else if (ch >= 'A' && ch <= 'F') {
				write_value = write_value * 16 + ch - 'A' + 10;
				write_size += 4;
			} else {
				if (write_size == 8 || write_size == 16
					|| write_size == 32) {
					for (i=0 ; i< (write_size / 8); i++) {
						buf[byte_size++] =
							(unsigned char)(write_value & 0xFF);
						write_value >>= 8;
					}
				} else {
					if (write_size != 0)
						mbedtls_printf("process_nsih : Error at %d line.\n", line+1 );
				}
				write_size = 0;
				skip_line = 1;
			}
		}

		if (ch == '\n') {
			line++;
			skip_line = 0;
			write_value = 0;
		}

	}

	fclose( fp );

	return byte_size;
}

#define LTB_E		1

void ltb_e(char *dst, char *src, int size)
{
	int i;
#if (LTB_E == 1)
	for (i = 0; i < size; i++)
		dst[i] = src[(size -1) - i];
#else
	for (i = 0; i < size; i++)
		dst[i] = src[i];
#endif
}

int get_fsize(char *fname)
{
	FILE *fp;
	void *fb;
	int fsize, rsize;

	if ((fp = fopen(fname, "rb")) == NULL) {
		mbedtls_printf(" failed\n ! Could not open %s\n\n", fname);
	}

	fseek(fp, 0, SEEK_END);
	fsize = ftell(fp);
	fseek(fp, 0, SEEK_SET);

	return fsize;
}

int s_fwrite(char *fname, char *buf, int size)
{
	FILE *hpbkf;

	if ((hpbkf = fopen(fname, "wb+")) != NULL) {
		if (fwrite(buf, 1, size, hpbkf) != size) {
			mbedtls_printf("cannot write %s\n", fname);
		}
		fclose(hpbkf);
	}
}

int s_fprint(char *fname, char *buf, int size)
{
	FILE *hpbkf;
	unsigned int *p = (unsigned int *)buf;
	int i;

	if ((hpbkf = fopen(fname, "wb+")) != NULL) {
		for (i = 0; i < size/4; i++, p++)
			fprintf(hpbkf, "%04x", *p);

		fprintf(hpbkf, "\n");
		fclose(hpbkf);
	}
}

void dbg_dump_keyfile(mbedtls_rsa_context *ctx, char *key_name)
{
	int i;

	mbedtls_printf("\n\n %s public key is: \n", key_name);
	for (i = 0; i < ctx->N.n; i++) {
		if (i % 4 == 0)
			mbedtls_printf("\n");
		mbedtls_printf("%016lx ", ctx->N.p[i]);
	}
	mbedtls_printf("\n\n");
	mbedtls_printf("E:%lx\n\n", ctx->E.p[0]);
}

void dbg_dump_hash(unsigned int *hash, int size, int div_unit)
{
	unsigned int i;
#if 0
	unsigned long *ulbuf = (unsigned long *)hash;

	for (i = 0; i < (size >> 3); i++) {
		if (i % div_unit == 0)
			mbedtls_printf("\n");
		mbedtls_printf("%016lx ", (unsigned long)ulbuf[i]);
	}
#else
	for (i = 0; i < (size >> 2); i++) {
		if (i % div_unit == 0)
			mbedtls_printf("\n");
		mbedtls_printf("%08X ", (unsigned int)hash[i]);
	}
#endif
	mbedtls_printf("\n\n");
}
