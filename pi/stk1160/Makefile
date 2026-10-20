# Out-of-tree build of the stk1160 driver (kernel source: raspberrypi/linux
# stable_20260911, kernel 6.18.50+rpt). Kbuild holds the module definition.
KDIR ?= /lib/modules/$(shell uname -r)/build
obj-m += stk1160.o
stk1160-y := stk1160-core.o stk1160-v4l.o stk1160-video.o stk1160-i2c.o stk1160-ac97.o

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
