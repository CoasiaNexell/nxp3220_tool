/*
 * Copyright (C) 2010 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#define _LARGEFILE64_SOURCE
#include <sparse/sparse.h>

#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef O_BINARY
#define O_BINARY 0
#endif

static void usage()
{
	fprintf(stderr, "Usage: simg2dev <sparse_image_file> <raw_image_file> <device_offset(hex)>\n");
}

int main(int argc, char *argv[])
{
	struct sparse_file *s = NULL;
	char *i_file, *o_file;
	int in, out;
	off64_t offset = 0, seek;
	int ret;

	if (argc < 3) {
		usage();
		exit(-1);
	}

	i_file = argv[1];
	o_file = argv[2];

	if (argc == 4)
		offset = strtoul(argv[3], NULL, 16);

	fprintf(stdout, "%s -> %s, offset:0x%zx\n", i_file, o_file, offset);

	out = open(o_file, O_RDWR | O_CREAT | O_BINARY, 0644);
	if (out < 0) {
		fprintf(stderr, "Cannot open output file %s:%s\n",
			o_file, strerror(errno));
		exit(-1);
	}
	lseek(out, 0, SEEK_SET);

	in = open(i_file, O_RDONLY | O_BINARY);
	if (in < 0) {
		fprintf(stderr, "Cannot open input file %s:%s\n",
			o_file, strerror(errno));
		exit(-1);
	}

	s = sparse_file_import(in, true, false);
	if (!s) {
		fprintf(stderr, "Failed to read sparse file\n");
		exit(-1);
	}

	seek = lseek(out, offset, SEEK_CUR);
	if (seek != offset) {
		fprintf(stderr, "Failed to lseek to 0x%zx:%s\n",
			offset, strerror(errno));
		exit(-1);
	}

	ret = sparse_file_write(s, out, false, false, false);
	if (ret < 0) {
		fprintf(stderr, "Cannot write output file\n");
		exit(-1);
	}

	lseek(out, 0, SEEK_SET);
	sparse_file_destroy(s);

	close(in);
	close(out);

	fprintf(stdout, "ok\n");

	return 0;
}

