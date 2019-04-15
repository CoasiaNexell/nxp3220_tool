/*------------------------------------------------------------------------------
 *
 * Copyright (C) 2012 Nexell Co., All Rights Reserved
 * Nexell Co. Proprietary & Confidential
 *
 * NEXELL INFORMS THAT THIS CODE AND INFORMATION IS PROVIDED "AS IS" BASE
 * AND WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING
 * BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR
 * FITNESS FOR A PARTICULAR PURPOSE.
 *
 * Module          : nand boot ecc generation
 * File            : nandbingen.c
 * Description     :
 * Author          : Hans
 * History         : 2017.12.23 first implementation.
 *
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>

#define _VER_	"20190411_002"

#define GEN_ALPHAINDEX

#define mm_max  15		/* Dimension of Galoise Field */
#define nn_max  32768		/* Length of codeword, n = 2**m - 1 */
#define tt_max  60		/* Number of errors that can be corrected */
#define kk_max  32768		/* Length of information bit, kk = nn - rr  */
#define rr_max  1000		/* Number of parity checks, rr = deg[g(x)] */
#define parallel_max  32	/* Number of parallel encoding/syndrome computations */

#define _RANDOM_SEED_	0x576a

struct bchinfo {
	int *alpha_to;
	int *index_of; // Galois field
	int (*T_G_R)[rr_max];
	int *data;
	int mm;
	int nn;
	int tt;
	int rr;
	int kk;
	int kk_shorten;
	int nn_shorten;
	int parallel;
	int tid;
};

static int verbose;

static void print_usage(char *s)
{
	fprintf(stdout, "# Usage %s:  nand binary generator (ver:%s)\n",
		s, _VER_);
	fprintf(stdout, "    -h:  This help message\n");
	fprintf(stdout, "    -p <bytes>:  nand page size\n");
	fprintf(stdout, "    -r : no randomize (enable default)\n");
	fprintf(stdout, "    -i <name>:  image file name\n");
	fprintf(stdout, "    -o <name>:  output file name\n");
}

/*
 * Generate GF(2**mm) from the primitive polynomial p(X) in p[0]..p[mm]
 * The lookup table looks like:
 * index -> polynomial form:   alpha_to[ ] contains j = alpha**i;
 * polynomial form -> index form:  index_of[j = alpha**i] = i
 * alpha_to[1] = 2 is the primitive element of GF(2**mm)
 */
static void generate_gf(int mm, int nn, int alpha_to[], int index_of[])
{
	int i;
	int mask;  // Register states
	int p[mm_max + 1];

	printf("%s mm:%d, nn:%d\n", __func__, mm, nn);

	// Primitive polynomials
	for (i = 1; i < mm; i++)
		p[i] = 0;
	p[0] = p[mm] = 1;
	if (mm == 2)        p[1] = 1;
	else if (mm == 3)   p[1] = 1;
	else if (mm == 4)   p[1] = 1;
	else if (mm == 5)   p[2] = 1;
	else if (mm == 6)   p[1] = 1;
	else if (mm == 7)   p[1] = 1;
	else if (mm == 8)   p[4] = p[5] = p[6] = 1;
	else if (mm == 9)   p[4] = 1;
	else if (mm == 10)  p[3] = 1;
	else if (mm == 11)  p[2] = 1;
	else if (mm == 12)  p[3] = p[4] = p[7] = 1;
	else if (mm == 13)  p[1] = p[2] = p[3] = p[5] = p[7] = p[8] = p[10] = 1;    // 25AF
//	else if (mm == 13)   p[1] = p[3] = p[4] = 1;
	else if (mm == 14)  p[2] = p[4] = p[6] = p[7] = p[8] = 1;   // 41D5
//	else if (mm == 14)   p[1] = p[11] = p[12] = 1;
	else if (mm == 15)  p[1] = 1;
	else if (mm == 16)  p[2] = p[3] = p[5] = 1;
	else if (mm == 17)  p[3] = 1;
	else if (mm == 18)  p[7] = 1;
	else if (mm == 19)  p[1] = p[5] = p[6] = 1;
	else if (mm == 20)  p[3] = 1;

	if (verbose) {
		fprintf(stderr, "# The Galois field is GF(2**%d);\n\n", mm);
		fprintf(stderr, "# The primitive polynomial is: p(x) = ");
		for (i = 0; i <= mm; i++) {
			fprintf(stderr, " %d", p[i]);
		}
		fprintf(stderr, "\n\n");
	}

	/*
	 * Galois field implementation with shift registers
	 * Ref: L&C, Chapter 6.7, pp. 217
	 */
	mask = 1;
	alpha_to[mm] = 0;
	for (i = 0; i < mm; i++) {
		alpha_to[i] = mask;
		index_of[alpha_to[i]] = i;
		if (p[i] != 0)
			alpha_to[mm] ^= mask;

		mask <<= 1;
	}

	index_of[alpha_to[mm]] = mm;
	mask >>= 1;
	for (i = mm + 1; i < nn; i++) {
		if (alpha_to[i - 1] >= mask)
			alpha_to[i] = alpha_to[mm] ^
				((alpha_to[i - 1] ^ mask) << 1);
		else alpha_to[i] = alpha_to[i - 1] << 1;

		index_of[alpha_to[i]] = i;
	}
	index_of[0] = -1;

	/*
	 * Print out the Galois Field
	 */
	if (verbose) {
		fprintf(stderr, "# Look-up tables for GF(2**%2d)\n", mm);
		fprintf(stderr, "  i   alpha_to[i]  index_of[i]\n");
		for (i = 0; i <= nn; i++)
			fprintf(stderr, "%3d      %3d          %3d\n",
					i, alpha_to[i], index_of[i]);
		fprintf(stderr, "\n");
	}
}

/*
 * Compute generator polynomial of the tt-error correcting Binary BCH code
 * g(x) = LCM{M_1(x), M_2(x), ..., M_2t(x)},
 * where M_i(x) is the minimal polynomial of alpha^i by cyclotomic cosets
 */
static int gen_poly(int mm, int nn, int tt, int parallel,
		    int (*T_G_R)[rr_max], int *alpha_to, int *index_of)
{
	/*
	 * Roots of generator polynomial
	 */
	int i, j, iii, jjj, Temp;

	int *gen_roots, *gen_roots_true;
	gen_roots = malloc(sizeof(int) * (nn + 1));
	gen_roots_true = malloc(sizeof(int) * (nn + 1));

	printf("%s mm:%d, nn:%d, tt:%d, parallel:%d\n",
			__func__, mm, nn, tt, parallel);
	/*
	 * Initialization of gen_roots
	 */
	for (i = 0; i <= nn; i++) {
		gen_roots_true[i] = 0;
		gen_roots[i] = 0;
	}

	/*
	 * Cyclotomic cosets of gen_roots
	 */
	for (i = 1; i <= 2 * tt; i++) {
		for (j = 0; j < mm; j++) {
			Temp = ((int)pow(2, j) * i) % nn;
			gen_roots_true[Temp] = 1;
		}
	}

	int rr = 0;     // Count the number of parity check bits
	for (i = 0; i < nn; i++)
		if (gen_roots_true[i] == 1) {
			rr++;
			gen_roots[rr] = i;
		}

	int *gg = malloc(sizeof(int) * rr_max);        // Generator polynomial

	/*
	 * Compute generator polynomial based on its roots
	 */
	gg[0] = 2; // g(x) = (X + alpha) initially
	gg[1] = 1;
	for (i = 2; i <= rr; i++) {
		gg[i] = 1;
		for (j = i - 1; j > 0; j--)
			if (gg[j] != 0) {
				int genalpha = alpha_to[gen_roots[i]];
				int ggindex = index_of[gg[j]] +
					index_of[genalpha];
				gg[j] = gg[j - 1] ^ alpha_to[ggindex % nn];
			} else
				gg[j] = gg[j - 1];
		int genalpha = alpha_to[gen_roots[i]];
		int gg0index = index_of[gg[0]] + index_of[genalpha];
		gg[0] = alpha_to[gg0index % nn];
	}

	if (verbose) {
		fprintf(stderr, "# The Generator Polynomial is:\n");
		for (i = 0; i <= rr; i++)
			fprintf(stderr, " %d", gg[i]);
		fprintf(stderr, "\n\n");
	}

	/*
	 * for parallel encoding and syndrome computation
	 * Max parallalism is rr
	 */
	if (parallel > rr)
		parallel = rr;

	/*
	 * parallel lookahead table
	 */
	int (*T_G)[rr_max] = malloc(sizeof(int) * rr_max * rr_max);

	/*
	 * Construct parallel lookahead matrix T_g, and T_g**r from gg(x)
	 * Ref: parallel CRC, Shieh, 2001
	 */
	for (i = 0; i < rr; i++)
		for (j = 0; j < rr; j++)
			T_G[i][j] = 0;

	for (i = 1; i < rr; i++)
		T_G[i][i - 1] = 1;

	for (i = 0; i < rr; i++)
		T_G[i][rr - 1] = gg[i];

	for (i = 0; i < rr; i++)
		for (j = 0; j < rr; j++)
			T_G_R[i][j] = T_G[i][j];

	int (*T_G_R_Temp)[rr_max] = malloc(sizeof(int) * rr_max * rr_max);
	/*
	 * Compute T_G**R Matrix
	 */
	for (iii = 1; iii < parallel; iii++) {
		for (i = 0; i < rr; i++) {
			for (j = 0; j < rr; j++) {
				Temp = 0;
				for (jjj = 0; jjj < rr; jjj++)
					Temp ^= T_G_R[i][jjj] * T_G[jjj][j];

				T_G_R_Temp[i][j] = Temp;
			}
		}

		for (i = 0; i < rr; i++) {
			for (j = 0; j < rr; j++)
				T_G_R[i][j] = T_G_R_Temp[i][j];
		}
	}
	free(T_G_R_Temp);
	free(T_G);
	free(gg);
	free(gen_roots);
	free(gen_roots_true);

	return rr;
}

/*
 * parallel computation of n - k parity check bits.
 * Use lookahead matrix T_G_R.
 * The incoming streams are fed into registers from the right hand
 */
static void parallel_encode_bch(int *bb, int *data, int (*data_p)[kk_max],
				int parallel, int rr, int kk_shorten,
				int (*T_G_R)[rr_max])
{
	int i, j, iii, Temp;
	int *bb_temp = malloc(sizeof(int) * rr_max);
	int loop_count;

	/*
	 * determine the number of loops required for parallelism.
	 */
	loop_count = ceil(kk_shorten / (double)parallel);

	/*
	 * serial to parallel data conversion
	 */
	for (i = 0; i < parallel; i++) {
		for (j = 0; j < loop_count; j++) {
			if (i + j * parallel < kk_shorten)
				data_p[i][j] = data[i + j * parallel];
			else
				data_p[i][j] = 0;
		}
	}

	/*
	 * initialize the parity bits.
	 */
	for (i = 0; i < rr; i++)
		bb[i] = 0;

	/*
	 * Compute parity checks
	 * S(t) = T_G_R [ S(t-1) + M(t) ]
	 * Ref: parallel CRC, Shieh, 2001
	 */
	for (iii = 0; iii < loop_count; iii++) {
		for (i = 0; i < rr; i++)
			bb_temp[i] = bb[i];

		for (i = 0; i < parallel; i++)
			bb_temp[rr - parallel + i] ^= data_p[i][iii];

		for (i = 0; i < rr; i++) {
			Temp = 0;
			for (j = 0; j < rr; j++)
				Temp ^= (bb_temp[j] * T_G_R[i][j]);
			bb[i] = Temp;
		}
	}
	for (i = 0; i < parallel; i++)		// why?
		bb[i] ^= data_p[i][iii];

	free(bb_temp);
}

static void __attribute__((unused)) nand_randomizer(unsigned char *data,
					    int len, unsigned short seed)
{
	unsigned char c;
	unsigned short fcs, tmp;
	int i;

	fcs = seed;
	for (i = 0; i < len; i++) {
		c = data[i];
		tmp = fcs ^ (fcs << 1);
		fcs = fcs << 1;
		if (tmp & 0x4000) {
			fcs |= 1;
		}
		data[i] = c ^ (fcs >> 8);
	}
}

/*
 * nn: maximum error correction data bits that permited by mathmatics
 * rr: ecc bits (mm * tt)
 * tt: number of error correction bits
 * kk: maximum error correction data bits except ecc (nn - rr)
 * nn_shorten: target error correction data bytes (data + ecc)
 * kk_shorten: target error correction data bits except ecc (only data)
 * parallel: < rr
 * alpha_to, index_of, T_G_R, data_p, .... : temporary data
 *
 * encoding => org data, ecc
 * generate syndrome => ecc, broken data => syndrome
 * decoding => broken data, syndrom => error position
 */
int main(int argc, char* argv[])
{
	int i, j, pagesize = 1024, correctnum = 60, help = 1;
	int mm = 14, nn = 0;
	int *alpha_to = malloc(sizeof(int) * nn_max);
	int *index_of = malloc(sizeof(int) * nn_max); // Galois field
	int *T_G_R = malloc(sizeof(int) * rr_max * rr_max);

	char *ifn = "abc.txt";
	char *ofn = NULL;
	int free_ofn = 0;

	struct bchinfo bch;
	int no_randomize = 1;

	bch.alpha_to = alpha_to;
	bch.index_of = index_of;
	bch.T_G_R = (int(*)[rr_max])T_G_R;

	bch.parallel = 8;

	for (i = 1; i < argc; i++) {
		if (argv[i][0] != '-') {
			help = 1;
			continue;
		}
		switch (argv[i][1]) {
		case 'p':
			pagesize = atoi(argv[++i]);
			if (pagesize == 512) {
				mm = 13;
				correctnum = 24;
			}
			else if (pagesize == 1024) {
				mm = 14;
				correctnum = 60;
			}
			break;
		case 'r':
			no_randomize = 0;
			break;
		case 'i':
			ifn = argv[++i];
			help = 0;
			break;
		case 'o':
			ofn = argv[++i];
			break;
		default:
			help = 1;
		}
	}

	if (help == 1) {
		print_usage(argv[0]);
		return (0);
	}

	bch.mm = mm;
	bch.tt = correctnum;
	if (nn == 0)
		nn = (int)pow(2, mm) - 1;
	bch.nn_shorten = pagesize * 8;
	bch.nn = nn;

#ifdef GEN_ALPHAINDEX
	generate_gf(mm, nn, alpha_to, index_of);


	bch.rr = gen_poly(mm, nn, bch.tt, bch.parallel,
			(int(*)[rr_max])T_G_R, alpha_to, index_of);
#if 0
	FILE *fp;
#if 0
	fp = fopen("alpha_to.dat", "wb");
	fwrite(alpha_to, sizeof(int), nn_max, fp);
	fclose(fp);
	fp = fopen("index_of.dat", "wb");
	fwrite(index_of, sizeof(int), nn_max, fp);
	fclose(fp);
#endif
	fp = fopen("T_G_R.dat", "wb");
	fwrite(T_G_R, sizeof(int), rr_max * rr_max, fp);
	fclose(fp);
#endif
#else
	printf("load alpha_to\n");
	FILE *fp;
	fp = fopen("alpha_to.dat", "rb");
	fread(alpha_to, sizeof(int), nn_max, fp);
	fclose(fp);
	printf("load index_of\n");
	fp = fopen("index_of.dat", "rb");
	fread(index_of, sizeof(int), nn_max, fp);
	fclose(fp);
	printf("load T_G_R\n");
	fp = fopen("T_G_R.dat", "rb");
	fread(T_G_R, sizeof(int), rr_max * rr_max, fp);
	fclose(fp);
	bch.rr = 840;
#endif

	bch.kk_shorten = bch.nn_shorten - bch.rr;
	if (bch.kk_shorten & 1 << 3)	// odd byte
		bch.kk_shorten -= 8;	// make even for ddr access

	printf("\nmm:%d, nn:%d, kk_shorten:%d, nn_shorten:%d, rr:%d, tt:%d\n",
	       mm, nn, bch.kk_shorten, bch.nn_shorten, bch.rr, bch.tt);

	unsigned char *pdata;

	struct bchinfo *pbch = (struct bchinfo *)&bch;

	int *data = malloc(sizeof(int) * pbch->nn_shorten);
	int *ecc = malloc(sizeof(int) * pbch->rr);	// Parity checks
	int (*data_p)[kk_max] = malloc(sizeof(int) * pbch->parallel * kk_max);

	printf("data size in one sector:%d\n", pbch->kk_shorten);

	int cnt = 0, fsize, imgptr = 0;

	FILE *f;
	f = fopen(ifn, "rb");
	fseek(f, 0, SEEK_END);
	fsize = ftell(f);
	fseek(f, 0, SEEK_SET);
	printf("%s size is %d\n", ifn, fsize);

	cnt = (fsize + (pbch->kk_shorten / 8 - 1)) / (pbch->kk_shorten / 8);
	fsize = (pbch->nn_shorten / 8) * cnt;
	unsigned char *wfile = malloc(fsize);

	printf("image build total count:%d\n", cnt);
repeat:
	printf("%d ", cnt - imgptr);
	/*
	 * data generation
	 */
	memset(data, 0, sizeof(int) * pbch->nn_shorten);
	unsigned char *pcdata = malloc(pbch->kk_shorten / pbch->parallel);
#if 1	// real or golden
	fread(pcdata, 1, pbch->kk_shorten / pbch->parallel, f);
#else
	for (i = 0; i < pbch->kk_shorten / 8; i++)
		pcdata[i] = (unsigned char)i;	// golden vector pattern
#endif
	/*
	 * parallel to serial
	 */
	for (i = 0; i < pbch->kk_shorten; i++)
		data[i] = (pcdata[i >> 3] >> (i & 7)) & 1;
	free(pcdata);

	/*
	 * data encoding
	 */
//	printf("parallel_encode_bch(%d:%d:%d)\n",
//			pbch->kk_shorten, pbch->parallel, pbch->rr);

	parallel_encode_bch(ecc, data,	// input: data, output:ecc
			    data_p, pbch->parallel,
			    pbch->rr, pbch->kk_shorten, pbch->T_G_R);

	for (i = 0; i < pbch->rr / pbch->parallel; i++)
		for (j = 0; j < pbch->parallel; j++)
			data[pbch->kk_shorten + pbch->parallel * i + j] =
				ecc[(pbch->rr - (i + 1) * pbch->parallel) + j];

	/*
	 * make data serial to parallel
	 */
	pdata = malloc(pbch->nn_shorten / 8);
	memset(pdata, 0, pbch->nn_shorten / 8);
	for (i = 0; i < pbch->nn_shorten; i++)
		pdata[i / 8] |= data[i] << (i & 0x7);

	if (no_randomize)
		nand_randomizer(pdata, pbch->nn_shorten / 8, _RANDOM_SEED_);

	memcpy(&wfile[pbch->nn_shorten / 8 * imgptr++],
	       pdata, pbch->nn_shorten / 8);

	for (i = 0; i < pbch->nn_shorten; i++)
		data[i] = (pdata[i / 8] >> (i & 0x7)) & 1;

	fflush(stdout);

	if (cnt > imgptr)
		goto repeat;

	printf("\r\n");
	fclose(f);

	/*
	 * output file
	 */
	if (!ofn) {
		ofn = malloc(256);
		if (!ofn) {
			printf("internal memory alloc failed...\n");
			goto out;
		}
		free_ofn = 1;
		sprintf(ofn, "%s.ecc", ifn);
	}

	f = fopen(ofn, "wb");
	if (!f) {
		printf("output file open failed...\n");
		goto out;
	}
	fwrite(wfile, 1, fsize, f);

	printf("nand boot image(%s) generation done\n", ofn);
	fclose(f);

out:
	if (free_ofn)
		free(ofn);
	free(wfile);

	free(data_p);
	free(data);
	free(ecc);

	free(index_of);
	free(alpha_to);
	free(T_G_R);

	return 0;
}
