

all: disk.img

disk.img: $(shell find rootfs)
	fallocate -l 4G "$@" 
	
	mformat -i "$@"
	mcopy -i "$@" rootfs/* ::/
	mdir -i "$@"
	
	syslinux --install disk.img
	
run: disk.img
	qemu-system-x86_64 \
		-hda "$<" \
		-m 2G \
		-enable-kvm \
		-serial stdio


.PHONY: run
.SUFFIXES:
