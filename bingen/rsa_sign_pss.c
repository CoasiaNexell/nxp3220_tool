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

#if !defined(MBEDTLS_CONFIG_FILE)
#include "mbedtls/config.h"
#else
#include MBEDTLS_CONFIG_FILE
#endif

#if defined(MBEDTLS_PLATFORM_C)
#include "mbedtls/platform.h"
#else
#include <stdio.h>
#define mbedtls_snprintf   snprintf
#define mbedtls_printf     printf
#endif

#if !defined(MBEDTLS_MD_C) || !defined(MBEDTLS_ENTROPY_C) ||  \
    !defined(MBEDTLS_RSA_C) || !defined(MBEDTLS_SHA256_C) ||        \
    !defined(MBEDTLS_PK_PARSE_C) || !defined(MBEDTLS_FS_IO) ||    \
    !defined(MBEDTLS_CTR_DRBG_C)
int main( void )
{
	mbedtls_printf("MBEDTLS_MD_C and/or MBEDTLS_ENTROPY_C and/or "
			"MBEDTLS_RSA_C and/or MBEDTLS_SHA256_C and/or "
			"MBEDTLS_PK_PARSE_C and/or MBEDTLS_FS_IO and/or "
			"MBEDTLS_CTR_DRBG_C not defined.\n");
	return( 0 );
}
#else

#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/md.h"
#include "mbedtls/rsa.h"
#include "mbedtls/sha256.h"
#include "mbedtls/md.h"
#include "mbedtls/x509.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "libuser.h"
#include "bootheader.h"

#define ARTIK310_SRAM_SIZE		(64 * 1024)


void help(void)
{
	mbedtls_printf("usage:\n");
	mbedtls_printf("-b <boot key file>\n");
	mbedtls_printf("-u <user key file>\n");
	mbedtls_printf("-i <bl1 file>\n");
	mbedtls_printf("-n <nand retry count> (default:64)\n");
	mbedtls_printf("-e mark encrypted status to NSIH\n");
//	mbedtls_printf("-l <bl1 load address> (default:0xFFFF0000)\n");
//	mbedtls_printf("-s <bl1 start address> (default:0xFFFF0000)\n");
#if defined(_WIN32)
	mbedtls_printf("\n");
#endif
}

enum {
	ONLY_BL1 = 0,
	OTHER_BOOT = 1
};

struct img_desc {
	const unsigned char *ptr;
	int size;
};

struct bingen_managment {
	int load_addr;
	int launch_addr;
	int nand_retry_count;
	int crc32;

	void *fbuf;
	void *obuf;
	int image_size;
	int total_size;

	int other_boot;
	int testsample;

	char *nsih_name;
	char *bootkey_name;
	char *userkey_name;
	char *image_name;
	int mark_encrypted;
};

struct bingen_managment bg_m;
static unsigned int g_rsa_public_userkey[2048/8];

static void sha256_multi(const struct img_desc *pdesc, int desccount, int size,
		unsigned char phash[32], int is224)
{
	int i, csize = 0;
	mbedtls_sha256_context ctx;

	mbedtls_sha256_init(&ctx);
	mbedtls_sha256_starts(&ctx, is224);

	for (i = 0; i < desccount; i++) {
		mbedtls_sha256_update(&ctx, pdesc[i].ptr, pdesc[i].size);
		csize += pdesc[i].size;
	}

	mbedtls_sha256_finish(&ctx, phash);
	mbedtls_sha256_free(&ctx);
}

static int open_rsa_publickey(mbedtls_pk_context *pk, char *fname)
{
	int ret = 0;

	mbedtls_printf("\nz  . Reading private boot key from '%s'", fname);
	fflush(stdout);

	if ((ret = mbedtls_pk_parse_keyfile(pk, fname, "")) != 0) {
		mbedtls_printf(" failed\n  ! Could not read key from '%s'\n", fname);
		mbedtls_printf("  ! mbedtls_pk_parse_public_keyfile returned %d\n\n", ret);
		return ret;
	}

	if (!mbedtls_pk_can_do(pk, MBEDTLS_PK_RSA)) {
		mbedtls_printf( " failed\n  ! Key is not an RSA key\n" );
		return -1;
	}

	mbedtls_rsa_set_padding(mbedtls_pk_rsa(*pk), MBEDTLS_RSA_PKCS_V21,
			MBEDTLS_MD_SHA256);

	return ret;
}

//static int efuse_bootkey_genhash(mbedtls_rsa_context* ctx, char* key_name)
static int efuse_bootkey_genhash(unsigned int *Nv, char* key_name)
{
	char fname[512];
	unsigned int hash[8];
	int i;

	memset(hash, 0, 32);
	mbedtls_sha256((const unsigned char *)Nv, 256,
		(unsigned char *)hash, 0);

	memset(fname, 0, 512);
	mbedtls_snprintf(fname, 512, "%s.pub.hash", key_name);
	mbedtls_printf("   .generating rsa public boot key hash file(%s)\n\n",
			fname);
	s_fwrite(fname, (char*)hash, sizeof(hash));

	mbedtls_snprintf(fname, 512, "%s.pub.hash.txt", key_name);
	mbedtls_printf("   .generating rsa public boot key hash ascii file(%s)\n\n",
			fname);
	s_fprint(fname, (char*)hash, sizeof(hash));

	mbedtls_printf("rsa public boot key hash:\n");
	dbg_dump_hash(hash, sizeof(hash), 4);

	return 0;
}

#define IMAGE_ALIGN				512

static void* image_open_and_read(char* fname)
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

	if (fsize % IMAGE_ALIGN)
		fsize = ((fsize + (IMAGE_ALIGN - 1)) / IMAGE_ALIGN) * IMAGE_ALIGN;

	fb = malloc(fsize);
	memset(fb, 0, fsize);

	rsize = fread(fb, 1, fsize, fp);
	bg_m.image_size = fsize;

	fclose(fp);

	mbedtls_printf("%s file size is %d. but resized to %d\n",
			fname, rsize, fsize);
	return fb;
}

static int header_parser(char *tbi)
{
	int ret = 0;

	if (bg_m.other_boot == ONLY_BL1) {
		struct nx_bootinfo *pbi =
			(struct nx_bootinfo *)tbi;

		int nsize = sizeof(struct nx_bootinfo);
		unsigned char *nbuf = malloc(nsize);
		if (nsize != (ret = process_nsih(bg_m.nsih_name, nbuf))) {
			mbedtls_printf("NSIH Parsing Failed!!(Byte: %d:%d) \n",
				nsize, ret);
			return -1;
		}

		memcpy(pbi, nbuf, nsize);

		pbi->signature = HEADER_ID;
		pbi->LoadSize = bg_m.image_size;
		pbi->LoadAddr = bg_m.load_addr;
		pbi->StartAddr = bg_m.launch_addr;
		pbi->CRC32 = calc_crc(bg_m.fbuf, bg_m.image_size);;
		if (pbi->nandretrycnt != -1)
			pbi->nandretrycnt = bg_m.nand_retry_count;
	} else {
		struct sbi_header *pbi =
			(struct sbi_header *)tbi;

		int nsize = sizeof(struct sbi_header);
		unsigned char *nbuf = malloc(nsize);
		if (nsize != (ret = process_nsih(bg_m.nsih_name, nbuf))) {
			mbedtls_printf("NSIH Parsing Failed!!(Byte: %d:%d) \n",
				nsize, ret);
			return -1;
		}

		memcpy(pbi, nbuf, nsize);

		pbi->signature = HEADER_ID;
		pbi->load_size = bg_m.image_size;
		pbi->load_addr = bg_m.load_addr;
		pbi->launch_addr = bg_m.launch_addr;
		pbi->reserved2 = bg_m.mark_encrypted;
		pbi->crc32 = calc_crc(bg_m.fbuf, bg_m.image_size);;
	}
	return ret ;
}

int main(int argc, char *argv[])
{
	struct nx_bootheader *pbh0;
	struct bootheader *pobh;

	mbedtls_rsa_context *ctx;
	mbedtls_pk_context bpk;
	mbedtls_pk_context upk;
	mbedtls_entropy_context entropy;
	mbedtls_ctr_drbg_context ctr_drbg;
	unsigned char buf[MBEDTLS_MPI_MAX_SIZE];
	unsigned int Nv[256/4];

	const char *pers = "nexell trust sign";
	size_t olen = 0;

	unsigned char *obuf = NULL, *tbuf;
	unsigned int csize;

	unsigned int param_opt = 0;
	char *other_boot;
	int ret = 1;

	/* @brief: default value */
	bg_m.load_addr = 0xFFFF0000;
	bg_m.launch_addr = 0xFFFF0000;
	bg_m.nand_retry_count = 64;
	bg_m.bootkey_name = "bootkey";
	bg_m.userkey_name = "userkey";
	bg_m.image_name   = NULL;
	bg_m.other_boot = ONLY_BL1;
	bg_m.obuf = NULL;

	other_boot = "bl1";


	if (argc <= 1) {
		help();
		return -1;
	}

	while (-1 != (param_opt = getopt(argc, argv, "b:u:i:n:r:l:s:k:te"))) {
		switch (param_opt) {
		case 'b':
			bg_m.bootkey_name = strdup(optarg);
			break;
		case 'u':
			bg_m.userkey_name = strdup(optarg);
			break;
		case 'i':
			bg_m.image_name = strdup(optarg);
			break;
		case 'n':
			bg_m.nsih_name = strdup(optarg);
			break;
		case 'r':
			bg_m.nand_retry_count = deca_to_int(optarg);
			break;
		case 'l':
			bg_m.load_addr = hexa_to_int(optarg);
			break;
		case 's':
			bg_m.launch_addr = hexa_to_int(optarg);
			break;
		case 'k':
			other_boot = strdup(optarg);
			to_lower(other_boot);
			if (!strcmp(other_boot, "bl1"))
				bg_m.other_boot = ONLY_BL1;
			else
				bg_m.other_boot = OTHER_BOOT;
			break;
		case 't':
			bg_m.testsample = 1;
			break;
		case 'e':
			bg_m.mark_encrypted = 1;
			break;

		default:
			help();
			return -1;
		}
	}

	if ((bg_m.bootkey_name && bg_m.userkey_name
				&& bg_m.image_name) == 0) {
		help();
		return -1;
	}

	/* @brief: output image buffer. */
	if ((!strcmp(other_boot, "bl1")) || (!strcmp(other_boot, "bl2")))
		bg_m.obuf = malloc(ARTIK310_SRAM_SIZE);
	else
		bg_m.obuf = malloc(get_fsize(bg_m.image_name) + 0x100000);

	if (bg_m.other_boot == ONLY_BL1)
		pbh0 = (struct nx_bootheader *)bg_m.obuf;
	else
		pobh = (struct bootheader *)bg_m.obuf;

	/* @brief: ready to make random numbers. */
	mbedtls_printf("\n  . Seeding the random number generator...");
	fflush(stdout);

	mbedtls_entropy_init(&entropy);
	mbedtls_pk_init(&bpk);
	mbedtls_pk_init(&upk);
	mbedtls_ctr_drbg_init(&ctr_drbg);

	if ((ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func,
					&entropy, (const unsigned char *) pers,
					strlen(pers))) != 0) {
		mbedtls_printf(" failed\n  ! mbedtls_ctr_drbg_seed returned %d\n", ret);
		goto exit;
	}

	/* @brief: open(parser) the rsa-pkey(bootkey, userkey) */
	if (bg_m.other_boot == ONLY_BL1) {
		if (open_rsa_publickey(&bpk, bg_m.bootkey_name) != 0) {
			mbedtls_printf(" failed to open boot-key!! \n");
			goto exit;
		}
	}
	if (open_rsa_publickey(&upk, bg_m.userkey_name) != 0) {
		mbedtls_printf(" failed to open user-key!! \n");
		goto exit;
	}

	/* @brief: only boot-loader level 1 */
	if (bg_m.other_boot == ONLY_BL1) {
		/* @brief: boot.pub write to raw file */
		ctx = (mbedtls_rsa_context *)bpk.pk_ctx;
		ltb_e((char*)Nv, (char*)ctx->N.p, 256);
		dbg_dump_keyfile(ctx, bg_m.bootkey_name);
		memcpy(pbh0->rsa_public.rsapublicbootkey,
			(unsigned char*)Nv, (ctx->N.n * 8));
//		efuse_bootkey_genhash(ctx, bg_m.bootkey_name);
		efuse_bootkey_genhash(Nv, bg_m.bootkey_name);
	}

	/* @brief: user.pub write to raw file */
	ctx = (mbedtls_rsa_context *)upk.pk_ctx;
	ltb_e((char*)Nv, (char *)ctx->N.p, 256);
	dbg_dump_keyfile(ctx, bg_m.userkey_name);
	if (bg_m.other_boot == ONLY_BL1)
		memcpy(pbh0->rsa_public.rsapublicuserkey,
			(unsigned char*)Nv, (ctx->N.n * 8));
	else
		memcpy(g_rsa_public_userkey,
			(unsigned char*)Nv, (ctx->N.n * 8));
	efuse_bootkey_genhash(Nv, bg_m.userkey_name);

	/*
	 * @brief: open and read the boot-loader file
	 */
	bg_m.fbuf = image_open_and_read(bg_m.image_name);

	if (bg_m.other_boot == ONLY_BL1) {
		bg_m.total_size = (bg_m.image_size + sizeof(struct nx_bootinfo) +
			(2048 / 8) + sizeof(struct asymmetrickey));
		memcpy(pbh0->bl1image, bg_m.fbuf, bg_m.image_size);
		if (-1 == header_parser((char*)&pbh0->bi))
			goto exit;
	} else {
		bg_m.total_size = (bg_m.image_size + sizeof(struct sbi_header)
			+ sizeof(pobh->sign));
		memcpy(pobh->image, bg_m.fbuf, bg_m.image_size);
		if (-1 == header_parser((char*)&pobh->bi))
			goto exit;
	}

	/*
	 * boot image hash Generating (boot.pub, user.pub, bl1.bin)
	 *
	 * Compute the SHA-256 hash of the input file,
	 * then calculate the RSA signature of the hash.
	 */
	mbedtls_printf("\n  . Generating the RSA/SHA-256 signature \n");
	fflush(stdout);

	struct img_desc desc[3];
	unsigned char hash[32];

	if (bg_m.other_boot == ONLY_BL1) {
		desc[0].ptr  = (const unsigned char *)&pbh0->bi;
		desc[0].size = sizeof(struct nx_bootinfo);
		desc[1].ptr  = (const unsigned char *)&pbh0->rsa_public;
		desc[1].size = sizeof(struct asymmetrickey);
		desc[2].ptr  = (const unsigned char *)pbh0->bl1image;
		desc[2].size = pbh0->bi.LoadSize;

		sha256_multi(desc,
				sizeof(desc) / sizeof(struct img_desc),
				sizeof(struct nx_bootinfo) +
				sizeof(struct asymmetrickey) +
				pbh0->bi.LoadSize, hash, 0);
	} else {
		char zb[256];
		memset(zb, 0, sizeof(zb));

		desc[0].ptr  = (const unsigned char *)&pobh->bi;
		desc[0].size = sizeof(struct sbi_header);
		desc[1].ptr  = (const unsigned char *)zb;
		desc[1].size = 256;
		desc[2].ptr  = (const unsigned char *)pobh->image;
		desc[2].size = pobh->bi.load_size;

		sha256_multi(desc,
				sizeof(desc) / sizeof(struct img_desc),
				sizeof(struct sbi_header) +
				256 + pobh->bi.load_size, hash, 0);
	}

	/* @brief: crate the output total-image-hash file */
	{
		if (bg_m.testsample) {
			char name[512];
			memset(name, 0, 512);
			mbedtls_snprintf(name, 512, "%s.hash", bg_m.image_name);
			s_fwrite(name, hash, (256/8));
		}
		dbg_dump_hash((unsigned int*)hash, sizeof(hash), 4);
	}

	/* @brief: generate sig and write signature */
	 if (bg_m.other_boot == ONLY_BL1) {
		if ((ret = mbedtls_pk_sign(&bpk, MBEDTLS_MD_SHA256, hash, 0, buf, &olen,
						mbedtls_ctr_drbg_random, &ctr_drbg)) != 0) {

			mbedtls_printf(" failed\n  ! mbedtls_pk_sign returned %d\n\n", ret);
			goto exit;
		}
	 } else {
		 if ((ret = mbedtls_pk_sign(&upk, MBEDTLS_MD_SHA256, hash, 0, buf, &olen,
						 mbedtls_ctr_drbg_random, &ctr_drbg)) != 0) {
			 mbedtls_printf(" failed\n  ! mbedtls_pk_sign returned %d\n\n", ret);
			 goto exit;
		 }
	 }

	/* @brief: crate the result output sign file */
	if (bg_m.other_boot == ONLY_BL1) {
		memcpy(pbh0->bl1sign, buf, olen);
	} else {
		swap(buf, olen);
		memcpy(pobh->sign, buf, olen);
	}

	{
		if (bg_m.testsample) {
			char name[512];
			memset(name, 0, 512);
			mbedtls_snprintf(name, 512, "%s.sign", bg_m.image_name);
			s_fwrite(name, buf, olen);
		}
		mbedtls_printf("\n boot-loader image hash sign:\n");
		dbg_dump_hash((unsigned int*)buf, olen, 8);
	}
#if 0
	/* @brief: crate the result output raw file */
	{
		char name[512];
		memset(name, 0, 512);
		mbedtls_snprintf(name, 512, "%s.raw", bg_m.image_name);
		if (bg_m.other_boot == ONLY_BL1)
			s_fwrite(name, (char*)pbh0, bg_m.total_size);
		else
			s_fwrite(name, (char*)pobh, bg_m.total_size);
	}
#else
	/* @brief: relocated to a specified file format format */
	if (bg_m.other_boot != ONLY_BL1) {
		unsigned int extra_size = 256;
		bg_m.total_size += extra_size;

		obuf = malloc(bg_m.total_size);
		tbuf = obuf;

		memcpy(tbuf, &pobh->bi, sizeof(struct sbi_header));
		tbuf += sizeof(struct sbi_header);
		memset(tbuf, 0, extra_size);
		tbuf += extra_size;
		memcpy(tbuf, pobh->image, bg_m.image_size);
		tbuf += bg_m.image_size;
		memcpy(tbuf, pobh->sign, sizeof(pobh->sign));
	}
	/* @brief: crate the result output raw file */
	{
		char name[512];
		memset(name, 0, 512);
		mbedtls_snprintf(name, 512, "%s.raw", bg_m.image_name);
		if (bg_m.other_boot == ONLY_BL1)
			s_fwrite(name, (char*)pbh0, bg_m.total_size);
		else
			s_fwrite(name, (char*)obuf, bg_m.total_size);
	}

	if (obuf)
		free(obuf);
#endif

exit:
	if (bg_m.obuf)
		free(bg_m.obuf);
	mbedtls_pk_free(&bpk);
	mbedtls_pk_free(&upk);
	mbedtls_ctr_drbg_free(&ctr_drbg);
	mbedtls_entropy_free(&entropy);

	mbedtls_printf("\n");
#if defined(_WIN32)
	mbedtls_printf("  + Press Enter to exit this program.\n");
	fflush(stdout); getchar();
#endif
	return(ret);
}
#endif /* MBEDTLS_BIGNUM_C && MBEDTLS_ENTROPY_C && MBEDTLS_RSA_C &&
          MBEDTLS_SHA256_C && MBEDTLS_PK_PARSE_C && MBEDTLS_FS_IO &&
          MBEDTLS_CTR_DRBG_C */
