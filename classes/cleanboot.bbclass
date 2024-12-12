# This class brings a more generic version of the UEFI combo app from refkit to meta-intel.
# It uses a combo file, containing kernel, initramfs and
# command line, presented to the BIOS as UEFI application, by prepending
# it with the efi stub obtained from systemd-boot.

# Don't add syslinux or build an ISO
PCBIOS:forcevariable = "0"
NOISO:forcevariable  = "1"
DEPENDS += "\
    os-release \
    systemd-boot \
    systemd-boot-native \
    virtual/${TARGET_PREFIX}binutils \
    virtual/kernel \
    python3-pefile-native\
"
# image-live.bbclass will default INITRD_LIVE to the image INITRD_IMAGE creates.
# We want behavior to be consistent whether or not "live" is in IMAGE_FSTYPES, so
# we default INITRD_LIVE to the INITRD_IMAGE as well.
INITRD_IMAGE ?= "dm-verity-image-initramfs"
INITRD_LIVE ?= " ${@ ('${DEPLOY_DIR_IMAGE}/' + d.getVar('INITRD_IMAGE', expand=True) + '-${MACHINE}.cpio.gz') if d.getVar('INITRD_IMAGE', True) else ''}"

# INITRD_IMAGE is added to INITRD_LIVE, which we use to create our initrd, so depend on it if it is set


# The image does without traditional bootloader.
# In its place, instead, it uses a single UEFI executable binary, which is
# composed by:
#   - an UEFI stub
#     The linux kernel can generate a UEFI stub, however the one from systemd-boot can fetch
#     the command line from a separate section of the EFI application, avoiding the need to
#     rebuild the kernel.
#   - the kernel
#   - an initramfs (optional)

UKIFY_CMD ?= "ukify build"
UKI_CONFIG_FILE ?= "${UNPACKDIR}/uki.conf"
UKI_FILENAME ?= "uki.efi"
UKI_KERNEL_FILENAME ?= "${KERNEL_IMAGETYPE}"
UKI_CMDLINE ?= "rootwait root=LABEL=active console=${KERNEL_CONSOLE} selinux=1"
# secure boot keys and cert, needs sbsign-tools-native (meta-secure-core)
#UKI_SB_KEY ?= ""
#UKI_SB_CERT ?= ""



fakeroot do_uefiapp_deploy() {
    rm -rf ${IMAGE_ROOTFS}/boot/*
    dest=${IMAGE_ROOTFS}/boot/EFI/BOOT
    mkdir -p $dest

}

do_uefiapp_deploy[depends] += "${PN}:do_uefiapp virtual/fakeroot-native:do_populate_sysroot"


# This decides when/how we add our tasks to the image
python () {
    image_fstypes = d.getVar('IMAGE_FSTYPES', True)
    initramfs_fstypes = d.getVar('INITRAMFS_FSTYPES', True)

    # Don't add any of these tasks to initramfs images
    if initramfs_fstypes not in image_fstypes:
        bb.build.addtask('uefiapp', 'do_image', 'do_rootfs', d)
        bb.build.addtask('uefiapp_deploy', 'do_image', 'do_rootfs', d)
}

SIGN_AFTER ?= "do_uefiapp"
SIGN_BEFORE ?= "do_uefiapp_deploy"
SIGNING_DIR ?= "${DEPLOY_DIR_IMAGE}"
SIGNING_BINARIES ?= "${IMAGE_LINK_NAME}.boot*.efi"


# Legacy hddimg support below this line
efi_hddimg_populate() {
    uefiapp_deploy_at "$1"
}

build_efi_cfg() {
    # The command line is built into the combo app, so this is a null op
    :
}

populate_kernel:append() {
    # The kernel and initrd are built into the app, so we don't need these
    if [ -f $dest/initrd ]; then
        rm $dest/initrd
    fi
    if [ -f $dest/vmlinuz ]; then
        rm $dest/vmlinuz
    fi
}


