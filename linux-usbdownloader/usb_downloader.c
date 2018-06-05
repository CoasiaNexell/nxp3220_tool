#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <getopt.h>
#include <fcntl.h>
#include <usb.h>

#define	VER_STR		"Nexell USB Downloader Version 0.1.0-Alpha (Only Artik310/NXP3220)"

/* Global variables */
char *nsih_file = NULL;
char *bin_file = NULL;
char *secondboot_file = NULL;
char *processor_type = NULL;

char *down_address = NULL;
char *start_address = NULL;

enum{
	NEXELL_VID    = 0x2375,
	SAMSUNG_VID   = 0x04E8,
	NXP3220_PID   = 0x3220,
	S5PXX18_PID   = 0x1234,
};

static size_t get_file_size(FILE *fd)
{
	size_t file_size;
	long cur_pose;

	cur_pose = ftell( fd );

	fseek(fd, 0, SEEK_END);
	file_size = ftell( fd );
	fseek(fd, cur_pose, SEEK_SET );

	return file_size;
}

static void print_downlod_info(const char *msg)
{
	printf( "==================================================================\n" );
	printf( " %s \n", VER_STR);
	printf( " %s, %s \n", __DATE__, __TIME__ );
	printf( " %s \n", msg );
	printf( " Processor type  : %s\n", processor_type?processor_type:"NULL" );
	printf( " Bin file        : %s\n", bin_file?bin_file:"NULL" );
	printf( " Download addr   : %s\n", down_address?down_address:"default" );
	printf( " Start addr      : %s\n", start_address?start_address:"default" );
	printf( "==================================================================\n" );
}

static void usage(void)
{
	printf("\n%s, %s, %s\nusage : \n", VER_STR, __DATE__, __TIME__);
	printf("   -h : show usage\n");
	printf("   -f [file name]      : send file name\n");
	printf("   -t [processor type] : select target processor type\n");
	printf("      ( type : nxp3220 )\n" );
	printf("   -a [address]        : download address\n");
	printf("   -j [address]        : jump address\n");
	printf("\n");
	printf(" case 1. nxp3220 Boot Loader Level1 Download\n" );
	printf("  #>sudo ./usb-downloader -t nxp3220 -f bl1.bin -a 0xFFFF0000 -j 0xFFFF0000 \n" );
	printf(" case 2. nxp3220 Image Downloade \n" );
	printf("  #>sudo ./usb-downloader -t nxp3220 -f u-boot.bin -a 0x40000000 -j 0x40000000 \n" );
	printf("\n");
}


static int is_init_usb = 0;

static usb_dev_handle *get_usb_dev_handle(int vid, int pid)
{
	struct usb_bus *bus;
	struct usb_device *dev;

	if (!is_init_usb) {
		usb_init();
		is_init_usb = 1;
	}

	usb_find_busses();
	usb_find_devices();

	for (bus = usb_get_busses(); bus ; bus = bus->next) {
		for (dev = bus->devices; dev ; dev = dev->next) {
			if ((dev->descriptor.idVendor == vid
				&& dev->descriptor.idProduct == pid ) ||
				(dev->descriptor.idVendor == pid
					&& dev->descriptor.idProduct == vid )) {
				return usb_open(dev);
			}
		}
	}
	return NULL;
}

int send_data(int vid, int pid, unsigned char *data, int size)
{
	int ret;
	usb_dev_handle *dev_handle;

	dev_handle = get_usb_dev_handle(vid, pid);

	if (NULL == dev_handle) {
		printf("Cannot found matching USB device."
				"(vid=0x%04x, pid=0x%04x)\n", vid, pid);
		return -1;
	}

	if (usb_claim_interface(dev_handle, 0) < 0) {
		printf("usb_claim_interface() fail!!!\n");
		usb_close(dev_handle);
		return -1;
	}

	printf("=> Downloading %d bytes\n", size);

	ret = usb_bulk_write(dev_handle, 2, (void *)data, size, 5 * 1000 * 1000);

	if (ret == size) {
		printf("=> Download Success!!!\n");
	} else {
		printf("=> Download Failed!!(ret=%d)\n", ret);
		usb_close(dev_handle);
		return -1;
	}

	usb_release_interface(dev_handle, 0);
	usb_close(dev_handle);

	return 0;
}

int receive_data(int vid, int pid, unsigned char *data, int size)
{
	int ret = 0;
	usb_dev_handle *dev_handle;

	dev_handle = get_usb_dev_handle(vid, pid);

	if (NULL == dev_handle) {
		printf("Cannot found matching USB device."
				"(vid=0x%04x, pid=0x%04x)\n", vid, pid);
		return -1;
	}

	if (usb_claim_interface(dev_handle, 0) < 0) {
		printf("usb_claim_interface() fail!!!\n");
		usb_close(dev_handle);
		return -1;
	}
	printf("=> try get %d bytes\n", size);

	ret = usb_bulk_read(dev_handle, 1, (void *)data, size, 5 * 1000 * 1000);

	if (ret == size) {
		printf("=> data received. ret:%d, size:%d\n", ret, size);
	} else {
		printf("=> cannot get data!!(ret=%d)\n", ret);
		usb_close(dev_handle);
		return ret;
	}

	usb_release_interface(dev_handle, 0);
	usb_close(dev_handle);

	return 0;
}

static int nxp3220_image_transfer(unsigned int vendor_id, unsigned int product_id)
{
	FILE *fd_image = NULL;
	unsigned char *send_buf = NULL;
	unsigned int buf_size, read_size;
	unsigned int *header;
	unsigned int down_addr = 0xFFFF0000;
	unsigned int start_addr = 0xFFFF0000;
	int ret;

	if (down_address)
		down_addr  = strtoul(down_address , NULL, 16);
	if (start_address)
		start_addr = strtoul(start_address, NULL, 16);

	fd_image = fopen(bin_file , "rb");
	if (!fd_image) {
		printf("File open failed!! check filename!!\n");
		goto error_exit;
	}

	buf_size = get_file_size(fd_image);
	send_buf = malloc(buf_size);


	read_size = fread(send_buf, 1, buf_size, fd_image);
	if ((read_size < 0) || (read_size != buf_size)) {
		printf("File Size is not the same!! (%d:%d) \n", read_size, buf_size);
		goto error_exit;
	}

	header = (unsigned int*)send_buf;
	header[2] = down_addr;
	header[3] = start_addr;

	ret = send_data(vendor_id, product_id, send_buf, buf_size);

	print_downlod_info("Boot Loader");
	printf("Download %s !\n", (ret == 0) ? "Success" : "Fail");

	free(send_buf);
	if (fd_image)
		fclose(fd_image);

	return 0;

error_exit:
	free(send_buf);
	if (fd_image)
		fclose(fd_image);

	return -1;
}

int main(int argc, char **argv)
{
	int param_opt;
	printf("USB Download Tool\n");
	printf("\n");

	while (-1 != (param_opt = getopt(argc, argv, "a:j:f:t:h"))) {
		switch (param_opt) {
			case 'a':
				down_address = strdup(optarg);
				break;
			case 'j':
				start_address = strdup(optarg);
				break;
			case 'f':
				bin_file = strdup(optarg);
				break;
			case 't':
				processor_type = strdup(optarg);
				break;
			case 'h':
				usage();
				return 0;
			default:
				printf("unkown option parameter(%c)\n", param_opt);
				usage();
				break;
		}
	}

	if (processor_type == NULL) {
		printf("Error !!!, Set processor type!!!\n");
		return -1;
	}

	if (!strncmp("nxp3220", processor_type ,7)) {
		if (0 != nxp3220_image_transfer(NEXELL_VID, NXP3220_PID)) {
//		if (0 != nxp3220_image_transfer(SAMSUNG_VID, S5PXX18_PID)) {
			printf("NXP3220_ImageDownload Failed\n");
			return -1;
		}
	}

	return 0;
}
