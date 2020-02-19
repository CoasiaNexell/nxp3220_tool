/*
 *  FIPS-180-1 compliant SHA-1 implementation
 *
 *  Copyright (C) 2006-2015, ARM Limited, All Rights Reserved
 *  SPDX-License-Identifier: Apache-2.0
 *
 *  Licensed under the Apache License, Version 2.0 (the "License"); you may
 *  not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 *  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 *  This file is part of mbed TLS (https://tls.mbed.org)
 */
/*
 *  The SHA-1 standard was published by NIST in 1993.
 *
 *  http://www.itl.nist.gov/fipspubs/fip180-1.htm
 */

#if !defined(MBEDTLS_CONFIG_FILE)
#include "mbedtls/config.h"
#else
#include MBEDTLS_CONFIG_FILE
#endif

#if defined(MBEDTLS_SHA1_C)

#include "mbedtls/sha1.h"

#include <string.h>

#if defined(MBEDTLS_SELF_TEST)
#if defined(MBEDTLS_PLATFORM_C)
#include "mbedtls/platform.h"
#else
#include <stdio.h>
#define mbedtls_printf printf
#endif /* MBEDTLS_PLATFORM_C */
#endif /* MBEDTLS_SELF_TEST */

#if !defined(MBEDTLS_SHA1_ALT)

/* Implementation that should never be optimized out by the compiler */
static void mbedtls_zeroize( void *v, size_t n ) {
    volatile unsigned char *p = (unsigned char*)v; while( n-- ) *p++ = 0;
}

/*
 * 32-bit integer manipulation macros (big endian)
 */
#ifndef GET_UINT32_BE
#define GET_UINT32_BE(n,b,i)                            \
{                                                       \
    (n) = ( (uint32_t) (b)[(i)    ] << 24 )             \
        | ( (uint32_t) (b)[(i) + 1] << 16 )             \
        | ( (uint32_t) (b)[(i) + 2] <<  8 )             \
        | ( (uint32_t) (b)[(i) + 3]       );            \
}
#endif

#ifndef PUT_UINT32_BE
#define PUT_UINT32_BE(n,b,i)                            \
{                                                       \
    (b)[(i)    ] = (unsigned char) ( (n) >> 24 );       \
    (b)[(i) + 1] = (unsigned char) ( (n) >> 16 );       \
    (b)[(i) + 2] = (unsigned char) ( (n) >>  8 );       \
    (b)[(i) + 3] = (unsigned char) ( (n)       );       \
}
#endif

void mbedtls_sha1_init( mbedtls_sha1_context *ctx )
{
    memset( ctx, 0, sizeof( mbedtls_sha1_context ) );
}

void mbedtls_sha1_free( mbedtls_sha1_context *ctx )
{
    if( ctx == NULL )
        return;

    mbedtls_zeroize( ctx, sizeof( mbedtls_sha1_context ) );
}

void mbedtls_sha1_clone( mbedtls_sha1_context *dst,
                         const mbedtls_sha1_context *src )
{
    *dst = *src;
}

/*
 * SHA-1 context setup
 */
void mbedtls_sha1_starts( mbedtls_sha1_context *ctx )
{
    ctx->total[0] = 0;
    ctx->total[1] = 0;

    ctx->state[0] = 0x67452301;
    ctx->state[1] = 0xEFCDAB89;
    ctx->state[2] = 0x98BADCFE;
    ctx->state[3] = 0x10325476;
    ctx->state[4] = 0xC3D2E1F0;
}

#if !defined(MBEDTLS_SHA1_PROCESS_ALT)
void mbedtls_sha1_process( mbedtls_sha1_context *ctx, const unsigned char data[64] )
{
    uint32_t temp, W[16], A, B, C, D, E;

    GET_UINT32_BE( W[ 0], data,  0 );
    GET_UINT32_BE( W[ 1], data,  4 );
    GET_UINT32_BE( W[ 2], data,  8 );
    GET_UINT32_BE( W[ 3], data, 12 );
    GET_UINT32_BE( W[ 4], data, 16 );
    GET_UINT32_BE( W[ 5], data, 20 );
    GET_UINT32_BE( W[ 6], data, 24 );
    GET_UINT32_BE( W[ 7], data, 28 );
    GET_UINT32_BE( W[ 8], data, 32 );
    GET_UINT32_BE( W[ 9], data, 36 );
    GET_UINT32_BE( W[10], data, 40 );
    GET_UINT32_BE( W[11], data, 44 );
    GET_UINT32_BE( W[12], data, 48 );
    GET_UINT32_BE( W[13], data, 52 );
    GET_UINT32_BE( W[14], data, 56 );
    GET_UINT32_BE( W[15], data, 60 );

#define S(x,n) ((x << n) | ((x & 0xFFFFFFFF) >> (32 - n)))

#define R(t)                                            \
(                                                       \
    temp = W[( t -  3 ) & 0x0F] ^ W[( t - 8 ) & 0x0F] ^ \
           W[( t - 14 ) & 0x0F] ^ W[  t       & 0x0F],  \
    ( W[t & 0x0F] = S(temp,1) )                         \
)

#define P(a,b,c,d,e,x)                                  \
{                                                       \
    e += S(a,5) + F(b,c,d) + K + x; b = S(b,30);        \
}

    A = ctx->state[0];
    B = ctx->state[1];
    C = ctx->state[2];
    D = ctx->state[3];
    E = ctx->state[4];

#define F(x,y,z) (z ^ (x & (y ^ z)))
#define K 0x5A827999

    P( A, B, C, D, E, W[0]  );
    P( E, A, B, C, D, W[1]  );
    P( D, E, A, B, C, W[2]  );
    P( C, D, E, A, B, W[3]  );
    P( B, C, D, E, A, W[4]  );
    P( A, B, C, D, E, W[5]  );
    P( E, A, B, C, D, W[6]  );
    P( D, E, A, B, C, W[7]  );
    P( C, D, E, A, B, W[8]  );
    P( B, C, D, E, A, W[9]  );
    P( A, B, C, D, E, W[10] );
    P( E, A, B, C, D, W[11] );
    P( D, E, A, B, C, W[12] );
    P( C, D, E, A, B, W[13] );
    P( B, C, D, E, A, W[14] );
    P( A, B, C, D, E, W[15] );
    P( E, A, B, C, D, R(16) );
    P( D, E, A, B, C, R(17) );
    P( C, D, E, A, B, R(18) );
    P( B, C, D, E, A, R(19) );

#undef K
#undef F

#define F(x,y,z) (x ^ y ^ z)
#define K 0x6ED9EBA1

    P( A, B, C, D, E, R(20) );
    P( E, A, B, C, D, R(21) );
    P( D, E, A, B, C, R(22) );
    P( C, D, E, A, B, R(23) );
    P( B, C, D, E, A, R(24) );
    P( A, B, C, D, E, R(25) );
    P( E, A, B, C, D, R(26) );
    P( D, E, A, B, C, R(27) );
    P( C, D, E, A, B, R(28) );
    P( B, C, D, E, A, R(29) );
    P( A, B, C, D, E, R(30) );
    P( E, A, B, C, D, R(31) );
    P( D, E, A, B, C, R(32) );
    P( C, D, E, A, B, R(33) );
    P( B, C, D, E, A, R(34) );
    P( A, B, C, D, E, R(35) );
    P( E, A, B, C, D, R(36) );
    P( D, E, A, B, C, R(37) );
    P( C, D, E, A, B, R(38) );
    P( B, C, D, E, A, R(39) );

#undef K
#undef F

#define F(x,y,z) ((x & y) | (z & (x | y)))
#define K 0x8F1BBCDC

    P( A, B, C, D, E, R(40) );
    P( E, A, B, C, D, R(41) );
    P( D, E, A, B, C, R(42) );
    P( C, D, E, A, B, R(43) );
    P( B, C, D, E, A, R(44) );
    P( A, B, C, D, E, R(45) );
    P( E, A, B, C, D, R(46) );
    P( D, E, A, B, C, R(47) );
    P( C, D, E, A, B, R(48) );
    P( B, C, D, E, A, R(49) );
    P( A, B, C, D, E, R(50) );
    P( E, A, B, C, D, R(51) );
    P( D, E, A, B, C, R(52) );
    P( C, D, E, A, B, R(53) );
    P( B, C, D, E, A, R(54) );
    P( A, B, C, D, E, R(55) );
    P( E, A, B, C, D, R(56) );
    P( D, E, A, B, C, R(57) );
    P( C, D, E, A, B, R(58) );
    P( B, C, D, E, A, R(59) );

#undef K
#undef F

#define F(x,y,z) (x ^ y ^ z)
#define K 0xCA62C1D6

    P( A, B, C, D, E, R(60) );
    P( E, A, B, C, D, R(61) );
    P( D, E, A, B, C, R(62) );
    P( C, D, E, A, B, R(63) );
    P( B, C, D, E, A, R(64) );
    P( A, B, C, D, E, R(65) );
    P( E, A, B, C, D, R(66) );
    P( D, E, A, B, C, R(67) );
    P( C, D, E, A, B, R(68) );
    P( B, C, D, E, A, R(69) );
    P( A, B, C, D, E, R(70) );
    P( E, A, B, C, D, R(71) );
    P( D, E, A, B, C, R(72) );
    P( C, D, E, A, B, R(73) );
    P( B, C, D, E, A, R(74) );
    P( A, B, C, D, E, R(75) );
    P( E, A, B, C, D, R(76) );
    P( D, E, A, B, C, R(77) );
    P( C, D, E, A, B, R(78) );
    P( B, C, D, E, A, R(79) );

#undef K
#undef F

    ctx->state[0] += A;
    ctx->state[1] += B;
    ctx->state[2] += C;
    ctx->state[3] += D;
    ctx->state[4] += E;
}
#endif /* !MBEDTLS_SHA1_PROCESS_ALT */

/*
 * SHA-1 process buffer
 */
void mbedtls_sha1_update( mbedtls_sha1_context *ctx, const unsigned char *input, size_t ilen )
{
    size_t fill;
    uint32_t left;

    if( ilen == 0 )
        return;

    left = ctx->total[0] & 0x3F;
    fill = 64 - left;

    ctx->total[0] += (uint32_t) ilen;
    ctx->total[0] &= 0xFFFFFFFF;

    if( ctx->total[0] < (uint32_t) ilen )
        ctx->total[1]++;

    if( left && ilen >= fill )
    {
        memcpy( (void *) (ctx->buffer + left), input, fill );
        mbedtls_sha1_process( ctx, ctx->buffer );
        input += fill;
        ilen  -= fill;
        left = 0;
    }

    while( ilen >= 64 )
    {
        mbedtls_sha1_process( ctx, input );
        input += 64;
        ilen  -= 64;
    }

    if( ilen > 0 )
        memcpy( (void *) (ctx->buffer + left), input, ilen );
}

static const unsigned char sha1_padding[64] =
{
 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

/*
 * SHA-1 final digest
 */
void mbedtls_sha1_finish( mbedtls_sha1_context *ctx, unsigned char output[20] )
{
    uint32_t last, padn;
    uint32_t high, low;
    unsigned char msglen[8];

    high = ( ctx->total[0] >> 29 )
         | ( ctx->total[1] <<  3 );
    low  = ( ctx->total[0] <<  3 );

    PUT_UINT32_BE( high, msglen, 0 );
    PUT_UINT32_BE( low,  msglen, 4 );

    last = ctx->total[0] & 0x3F;
    padn = ( last < 56 ) ? ( 56 - last ) : ( 120 - last );

    mbedtls_sha1_update( ctx, sha1_padding, padn );
    mbedtls_sha1_update( ctx, msglen, 8 );

    PUT_UINT32_BE( ctx->state[0], output,  0 );
    PUT_UINT32_BE( ctx->state[1], output,  4 );
    PUT_UINT32_BE( ctx->state[2], output,  8 );
    PUT_UINT32_BE( ctx->state[3], output, 12 );
    PUT_UINT32_BE( ctx->state[4], output, 16 );
}

#endif /* !MBEDTLS_SHA1_ALT */

/*
 * output = SHA-1( input buffer )
 */
void mbedtls_sha1( const unsigned char *input, size_t ilen, unsigned char output[20] )
{
    mbedtls_sha1_context ctx;

    mbedtls_sha1_init( &ctx );
    mbedtls_sha1_starts( &ctx );
    mbedtls_sha1_update( &ctx, input, ilen );
    mbedtls_sha1_finish( &ctx, output );
    mbedtls_sha1_free( &ctx );
}

#if defined(MBEDTLS_SELF_TEST)
#if 0
/*
 * FIPS-180-1 test vectors
 */
static const unsigned char sha1_test_buf[3][57] =
{
    { "abc" },
    { "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" },
    { "" }
};

static const int sha1_test_buflen[3] =
{
    3, 56, 1000
};

static const unsigned char sha1_test_sum[3][20] =
{
    { 0xA9, 0x99, 0x3E, 0x36, 0x47, 0x06, 0x81, 0x6A, 0xBA, 0x3E,
      0x25, 0x71, 0x78, 0x50, 0xC2, 0x6C, 0x9C, 0xD0, 0xD8, 0x9D },
    { 0x84, 0x98, 0x3E, 0x44, 0x1C, 0x3B, 0xD2, 0x6E, 0xBA, 0xAE,
      0x4A, 0xA1, 0xF9, 0x51, 0x29, 0xE5, 0xE5, 0x46, 0x70, 0xF1 },
    { 0x34, 0xAA, 0x97, 0x3C, 0xD4, 0xC4, 0xDA, 0xA4, 0xF6, 0x1E,
      0xEB, 0x2B, 0xDB, 0xAD, 0x27, 0x31, 0x65, 0x34, 0x01, 0x6F }
};
#endif
void printvalue(unsigned char value[])
{
	int i;
	printf("\n0x");
	for (i = 0; i < 16; i++) {
		printf("%02x", value[i]);
	}
	printf("\n\n");
#if 1
	printf("lsb");
	for (i = 0; i < 16 * 8 - 6; i++)
		printf(" ");
	printf("msb\n");
	for (i = 0; i < 16 * 8; i++)
		if (i % 100)
			printf(" ");
		else
			printf("%d", i / 100);
	printf("\n");
	for (i = 0; i < 16 * 8; i++)
		if (i % 10)
			printf(" ");
		else
			printf("%d", (i / 10) % 10);
	printf("\n");
	for (i = 0; i < 16 * 8; i++)
		printf("%d", i % 10);
	printf("\n");
	for (i = 0; i < 16 * 8; i++)
		printf("%d", (value[(127 - i) >> 3] >> (i % 8)) & 1);
	printf("\n\n");
//#else
	printf("msb");
	for (i = 0; i < 16 * 8 - 6; i++)
		printf(" ");
	printf("lsb\n");
	for (i = 16 * 8 - 1; i >= 0; i--)
		if (i % 100)
			printf(" ");
		else
			printf("%d", i / 100);
	printf("\n");
	for (i = 16 * 8 - 1; i >= 0; i--)
		if (i % 10)
			printf(" ");
		else
			printf("%d", (i / 10) % 10);
	printf("\n");
	for (i = 16 * 8 - 1; i >= 0; i--)
		printf("%d", i % 10);
	printf("\n");
	for (i = 0; i < 16 * 8; i++)
		printf("%d", (value[i >> 3] >> (7 - (i % 8))) & 1);
	printf("\n");
#endif
}
#define IDSIZE  21

static const char gst36StrTable[36] =
{
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
	'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
	'U', 'V', 'W', 'X', 'Y', 'Z'
};
void upper_str(char s[]) {
	int c = 0;

	while (s[c] != '\0') {
		if (s[c] >= 'a' && s[c] <= 'z') {
			s[c] = s[c] - 32;
		}
		c++;
	}
}
int check_str(char *s) {
	while (*s != '\0') {
		if ((*s <= 'Z' && *s >= 'A') || (*s <= '9' && *s >= '0'))
			s++;
		else return 0;
	}
	return 1;
}
static void lotidbin2string(unsigned int lot_id_bin, unsigned char *lot_id_string)
{
	unsigned int LotId = lot_id_bin & ((1UL << IDSIZE) - 1);
	unsigned char *str = lot_id_string;

	int i;
	unsigned int tmp = 0;
#if 1
	printf("LotId:%x\r\n", LotId);
	/* reverse number */
//      while (LotId) {
	for (i = 0; i < IDSIZE; i++) {
		tmp <<= 1;
		if (LotId & 1)
			tmp |= 1;
		LotId >>= 1;
	}
	LotId = tmp;
	printf("rev LotId:%x\r\n", LotId);
#else
	tmp = LotId;
	printf("LotId:%x\r\n", LotId);
#endif
	str[0] = 'S';
	i = 0;
	while (LotId) {
		LotId /= 36;    // get string size
		i++;            // max 7
	}
	str[i + 1] = '\0';      // mark string end

	LotId = tmp;
	while (LotId) {
		str[i] = gst36StrTable[LotId % 36];
		LotId /= 36;
		i--;
	}
	printf("str LotId:%s\r\n", str);
}
static unsigned int string2lotid(unsigned char *lot_id_string)
{
	unsigned int lotid = 0, i, tmp = 0;
	unsigned char *lot_id_stringt = lot_id_string;
	lot_id_stringt++;       // discard 'N'
	while (*lot_id_stringt) {
		lotid *= 36;
		for (i = 0; i < 36; i++)
			if (gst36StrTable[i] == *lot_id_stringt)
				break;
		lot_id_stringt++;
		lotid += i;
	}
	printf("lot id:%s, 0x%X\r\n", lot_id_string, lotid);
	while (lotid) {
		tmp <<= 1;
		if (lotid & 1)
			tmp |= 1;
		lotid >>= 1;
	}
	lotid = tmp;
	printf("lot id:%s, 0x%X\r\n", lot_id_string, lotid);
	return lotid;
}

#define ARTIK310	0
#define NXP3220		1

#include <unistd.h>
int writeT32CMM(unsigned char *buf, const int size, int proc, int secure, char *sLotID)
{

	FILE *out;
	int write_size = 0;
	int i = 0;
	unsigned int tmp;
	char path[1024];

	sprintf(path, "./securejtag_%s_%s_%s.cmm",
			proc ? "NXP3220" : "ARTIK310", sLotID, secure ? "secure" : "nonsecure");

	printf("Create Secure JTAG password cmm file(HEX) : %s\n", path);
	if ((out = fopen(path, "wb")) == 0) {
		printf("Fail to create file : %s\n", path);
		return -1;
	}
	printf("End create file.\n");


	printf("Start write data to %s.\n", path);
	for (i = 0; i < size; i += 4) {
		tmp =   buf[i + 0] <<  0 |
			buf[i + 1] <<  8 |
			buf[i + 2] << 16 |
			buf[i + 3] << 24;
		fprintf(out, "Data.Set EAPB:0x10300000 %%LE %%Long 0x%08x\n", tmp);
	}

	printf("Write %d bytes to %s done.\n", i, path);

	fclose(out);

	return 1;
}

void sjtagkeygen(int proc, char slotid[], unsigned int jtaghash[])
{
	int verbose;
	int i, j, buflen, ret = 0;
	unsigned char sha1sum[20];
	mbedtls_sha1_context ctx;

	mbedtls_sha1_init( &ctx );

	char buf[1024];
	printf("jtag password seed\n");
	if (proc == ARTIK310)
		sprintf(buf, "ARTIK310 %s SJTAG password  ", slotid);
	else
		sprintf(buf, "NXP3220 %s SJTAG password   ", slotid);
//	sprintf(buf, "NXP3220 SJTAG passwd");
	printf("%s\r\n", buf);
	mbedtls_sha1_starts( &ctx );
	mbedtls_sha1_update( &ctx, buf, 30 );
	mbedtls_sha1_finish( &ctx, sha1sum );

	mbedtls_sha1_starts( &ctx );
	mbedtls_sha1_update( &ctx, sha1sum, 20 );
	mbedtls_sha1_finish( &ctx, sha1sum );
	writeT32CMM(sha1sum, 20, proc, 1, slotid);
	printf("secure jtag key\n");
	for (i = 0; i < 20; i++) {
		if ((i % 4) == 0)
			printf("d.s eapb:0x10300000 %%le %%long 0x");
		printf("%02x", sha1sum[((i >> 2) << 2) + 3 - i % 4]);
		if ((i % 4) == 3)
			printf("\r\n");
	}
	printf("\n");
	mbedtls_sha1_starts( &ctx );
	mbedtls_sha1_update( &ctx, sha1sum, 20 );
	mbedtls_sha1_finish( &ctx, sha1sum );
	mbedtls_sha1_starts( &ctx );
	mbedtls_sha1_update( &ctx, sha1sum, 20 );
	mbedtls_sha1_finish( &ctx, sha1sum );
	writeT32CMM(sha1sum, 20, proc, 0, slotid);
	printf("nonsecure jtag key\n");
	for (i = 0; i < 20; i++) {
		if ((i % 4) == 0)
			printf("d.s eapb:0x10300000 %%le %%long 0x");
		printf("%02x", sha1sum[((i >> 2) << 2) + 3 - i % 4]);
		if ((i % 4) == 3)
			printf("\r\n");
	}
	printf("\n");
	mbedtls_sha1_starts( &ctx );
	mbedtls_sha1_update( &ctx, sha1sum, 20 );
	mbedtls_sha1_finish( &ctx, sha1sum );
	mbedtls_sha1_starts( &ctx );
	mbedtls_sha1_update( &ctx, sha1sum, 20 );
	mbedtls_sha1_finish( &ctx, sha1sum );
	printf("jtag password\n");
//	printvalue(sha1sum);
//	printf("\n");

	mbedtls_sha1_free( &ctx );

	unsigned char *cjh = (unsigned char *)jtaghash;
	for (i = 0; i < 16; i++) {
		cjh[i] = sha1sum[15 - i];
	}
	printf("0x");
	for (i = 3; i >= 0; i--)
		printf("%08x", jtaghash[i]);
	printf("\r\n\n");

//	return jtaghash;
}
/*
vector
1F111893 081201A5 00000000 04E81234
SZB4HNZ

seed:
"NXP3220 SJTAG passwd"

secure jtag key:
d.s eapb:0x040c0000 %le %long 0x1fb41f69
d.s eapb:0x040c0000 %le %long 0xf33e7553
d.s eapb:0x040c0000 %le %long 0x79172077
d.s eapb:0x040c0000 %le %long 0x3271fa06
d.s eapb:0x040c0000 %le %long 0xa1d5f4f5

nonsecure jtag key:
d.s eapb:0x040c0000 %le %long 0x4eace761
d.s eapb:0x040c0000 %le %long 0x39513b2e
d.s eapb:0x040c0000 %le %long 0x92619c0f
d.s eapb:0x040c0000 %le %long 0x5c08bffa
d.s eapb:0x040c0000 %le %long 0x555f1f29

jtag password:
0x5b0bfaaa812a9834b73ab77adfd402bb
*/
unsigned int ecid[4]    = {0x1F111893, 0x081201A5, 0x00000000, 0x04E81234};	//SZB4HNZ
unsigned char slotid[] = "SZB4HNZ";

#if 1
void usage(char *argv)
{
	fprintf(stderr, "\n"
			"%s [-p processor name(ARTIK310 or NXP3220)] [-l LotID(Sxxxx)]\n",
			argv);
	exit(-1);
}
#endif
int main(int argc, char *argv[])
{
	int i, j, opt, proc;
	unsigned int jtaghash[4];
	unsigned int bLotID = ecid[0];
	char LID[6];

	if (argc < 3) {
		printf("need more parameter\r\n");
		usage(argv[0]);
	}
#if 1
	while ((opt = getopt(argc, argv, "p:l:")) != -1) {
		switch (opt) {
		case 'p':
			upper_str(optarg);
			if (strcmp("ARTIK310", optarg) == 0)
				proc = ARTIK310;
			else if (strcmp("NXP3220", optarg) == 0)
				proc = NXP3220;
			else
				printf("processor type error\r\n");
			break;
		case 'l':
			upper_str(optarg);
			if (check_str(optarg) == 0) {
				printf("LotID error:%s\r\n", optarg);
				usage(argv[0]);
			}
			if (optarg[0] != 'S') {
				printf("LotID is not start 'S'(%s)\r\n", optarg);
				usage(argv[0]);
			}
			strncpy(LID, optarg, 5);
			LID[5] = 0;
			break;
		dafault:
			usage(argv[0]);
			break;
		}
	}
#endif
#if 0
	char strlotid[8];
	lotidbin2string(blotid, strlotid);

	blotid = string2lotid("NZB4H");
	printf("NZB4H:%x\r\n", blotid);
#endif
#if 1
	unsigned blotid = string2lotid(LID);
	printf("NZBNT:%x\r\n", blotid);
	lotidbin2string(blotid, LID);
	printf("%s\r\n", LID);
#endif
	printf("%s\r\n", LID);
	sjtagkeygen(proc, LID, jtaghash);

	return -1;
}
#endif /* MBEDTLS_SELF_TEST */

#endif /* MBEDTLS_SHA1_C */
