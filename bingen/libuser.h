#ifndef __LIBUSER_H__
#define __LIBUSER_H__

void swap(char *buf, int size);

unsigned int get_fcs(unsigned int fcs, unsigned char data);
unsigned int calc_crc(unsigned char *data, int size);

unsigned int hexa_to_int(const char *string);
unsigned int deca_to_int(const char *string);

void to_upper(char* string);
void to_lower(char* string);

int process_nsih(const char *fname, unsigned char *buf);

void ltb_e(char *dst, char *src, int size);

int get_fsize(char *fname);
int s_fwrite(char *fname, char *buf, int size);
int s_fprint(char *fname, char *buf, int size);

void dbg_dump_keyfile(mbedtls_rsa_context *ctx, char *key_name);
void dbg_dump_hash(unsigned int *hash, int size, int div_unit);

#endif
