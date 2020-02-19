/*
 *  RSASSA-PSS/SHA-256 signature creation program
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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#include "mbedtls/config.h"
#include "mbedtls/sha1.h"

static void make_sjtag_key(const char *seed,
			unsigned char skey[20],	unsigned char nskey[20],
			unsigned int hash[4])
{
	mbedtls_sha1_context ctx;
	unsigned char sha1sum[20];
	unsigned int buf[4];
	unsigned char *c = (unsigned char *)buf;
	int i, j;


	mbedtls_sha1_init(&ctx);
	mbedtls_sha1_starts(&ctx);
	mbedtls_sha1_update(&ctx, seed, 30);
	mbedtls_sha1_finish(&ctx, sha1sum);

	mbedtls_sha1_starts(&ctx);
	mbedtls_sha1_update(&ctx, sha1sum, 20);
	mbedtls_sha1_finish(&ctx, sha1sum);

	/* copy secure key */
	if (skey)
		memcpy(skey, sha1sum, 20);

	mbedtls_sha1_starts(&ctx);
	mbedtls_sha1_update(&ctx, sha1sum, 20);
	mbedtls_sha1_finish(&ctx, sha1sum);
	mbedtls_sha1_starts(&ctx);
	mbedtls_sha1_update(&ctx, sha1sum, 20);
	mbedtls_sha1_finish(&ctx, sha1sum);

	/* copy non-secure key */
	if (nskey)
		memcpy(nskey, sha1sum, 20);

	mbedtls_sha1_starts(&ctx);
	mbedtls_sha1_update(&ctx, sha1sum, 20);
	mbedtls_sha1_finish(&ctx, sha1sum);
	mbedtls_sha1_starts(&ctx);
	mbedtls_sha1_update(&ctx, sha1sum, 20);
	mbedtls_sha1_finish(&ctx, sha1sum);

	mbedtls_sha1_free(&ctx);

	for (i = 0; i < 16; i++)
		c[i] = sha1sum[15 - i];

	/* copy hash value */
	if (hash)
		memcpy(hash, c, 16);
}

static void make_sjtag_file(const char *prefix,
			unsigned char skey[20],	unsigned char nskey[20],
			unsigned int hash[4])
{
	char fname[1024] = { 0, };
	FILE *fp;
	int i;

	if (!prefix)
		return;

	if (skey) {
		snprintf(fname, sizeof(fname), "%s-seckey.txt", prefix);
		if ((fp = fopen(fname, "wb+")) != NULL) {
			fprintf(fp, "; secure password\n");
			for (i = 0; i < 20; i++) {
				if ((i % 4) == 0)
					fprintf(fp, "Data.Set EAPB:0x10300000 %%LE %%Long 0x");
				fprintf(fp, "%02x", skey[((i >> 2) << 2) + 3 - i % 4]);
				if ((i % 4) == 3)
					fprintf(fp, "\n");
			}
			fclose(fp);
		}
	}

	if (nskey) {
		snprintf(fname, sizeof(fname), "%s-nseckey.txt", prefix);
		if ((fp = fopen(fname, "wb+")) != NULL) {
			fprintf(fp, "; non-secure password\n");
			for (i = 0; i < 20; i++) {
				if ((i % 4) == 0)
					fprintf(fp, "Data.Set EAPB:0x10300000 %%LE %%Long 0x");
				fprintf(fp, "%02x", nskey[((i >> 2) << 2) + 3 - i % 4]);
				if ((i % 4) == 3)
					fprintf(fp, "\n");
			}
			fclose(fp);
		}
	}

	if (hash) {
		snprintf(fname, sizeof(fname), "%s-hash.txt", prefix);
		if ((fp = fopen(fname, "wb+")) != NULL) {
			for (i = 3; i >= 0; i--)
				fprintf(fp, "%08x", hash[i]);
			fprintf(fp, "\n");
			fclose(fp);
		}
	}
}

/*
 * seed:
 * "NXP3220 SJTAG passwd"
 *
 * secure jtag key:
 * Data.Set EAPB:0x040c0000 %LE %Long 0x1fb41f69
 * Data.Set EAPB:0x040c0000 %LE %Long 0xf33e7553
 * Data.Set EAPB:0x040c0000 %LE %Long 0x79172077
 * Data.Set EAPB:0x040c0000 %LE %Long 0x3271fa06
 * Data.Set EAPB:0x040c0000 %LE %Long 0xa1d5f4f5
 *
 * nonsecure jtag key:
 * Data.Set EAPB:0x040c0000 %LE %Long 0x4eace761
 * Data.Set EAPB:0x040c0000 %LE %Long 0x39513b2e
 * Data.Set EAPB:0x040c0000 %LE %Long 0x92619c0f
 * Data.Set EAPB:0x040c0000 %LE %Long 0x5c08bffa
 * Data.Set EAPB:0x040c0000 %LE %Long 0x555f1f29
 *
 * jtag password:
 * 0x5b0bfaaa812a9834b73ab77adfd402bb
 */
static void print_usage(void)
{
	printf(
	"usage: options\n"
	"-s string for hash seed\n"
	"-o output file prefix:\n"
	"   : <prefix>-seckey.txt\n"
	"   : <prefix>-nseckey.txt\n"
	"   : <prefix>-hash.txt\n"
	);
}

#define SJTAG_SEED	"ARTIK310 SZBNT SJTAG password  "
#define SJTAG_PREFIX	"secure-jtag"

int main(int argc, char **argv)
{
	int opt;
	const char *seed = SJTAG_SEED;
	char *out = SJTAG_PREFIX;
	unsigned char skey[20] = { 0, }, nskey[20] = { 0, };
	unsigned int hash[4] = { 0, };
	int i;

	while (-1 != (opt = getopt(argc, argv, "hs:o:"))) {
		switch (opt) {
		case 's':
			seed = optarg;
			break;
		case 'o':
			out = optarg;
			break;
		case 'h':
			print_usage();
			exit(0);
		default:
			break;
		}
	}

	printf("seed:'%s'\n\n", seed);
	make_sjtag_key(seed, skey, nskey, hash);

	printf("secure jtag key:\n");
	for (i = 0; i < 20; i++) {
		if ((i % 4) == 0)
			printf("Data.Set EAPB:0x10300000 %%LE %%Long 0x");
		printf("%02x", skey[((i >> 2) << 2) + 3 - i % 4]);
		if ((i % 4) == 3)
			printf("\n");
	}
	printf("\n");

	printf("nonsecure jtag key:\n");
	for (i = 0; i < 20; i++) {
		if ((i % 4) == 0)
			printf("Data.Set EAPB:0x10300000 %%LE %%Long 0x");
		printf("%02x", nskey[((i >> 2) << 2) + 3 - i % 4]);
		if ((i % 4) == 3)
			printf("\n");
	}
	printf("\n");

	printf("jtag password:\n");
	for (i = 3; i >= 0; i--)
		printf("%08x", hash[i]);
	printf("\n");

	make_sjtag_file(out, skey, nskey, hash);

	return 0;
}
