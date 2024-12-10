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
INITRD_IMAGE ?= "core-image-minimal-initramfs"
INITRD_LIVE ?= " ${@ ('${DEPLOY_DIR_IMAGE}/' + d.getVar('INITRD_IMAGE', expand=True) + '-${MACHINE}.cpio.gz') if d.getVar('INITRD_IMAGE', True) else ''}"

do_uefiapp[depends] += " \
                         intel-microcode:do_deploy \
                         systemd-boot:do_deploy \
                         virtual/kernel:do_deploy \
                       "

# INITRD_IMAGE is added to INITRD_LIVE, which we use to create our initrd, so depend on it if it is set
do_uefiapp[depends] += "${@ '${INITRD_IMAGE}:do_image_complete' if d.getVar('INITRD_IMAGE') else ''}"

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
UKI_CMDLINE ?= "rootwait root=LABEL=active console=${KERNEL_CONSOLE}"
# secure boot keys and cert, needs sbsign-tools-native (meta-secure-core)
#UKI_SB_KEY ?= ""
#UKI_SB_CERT ?= ""


def create_uefiapp(d, uuid=None, app_suffix=''):
    import glob, re
    import bb.process
    ukify_cmd = d.getVar('UKIFY_CMD')
    build_dir = d.getVar('B')
    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE')

    # architecture
    target_arch = d.getVar('EFI_ARCH')
    if target_arch:
        ukify_cmd += " --efi-arch %s" % (target_arch)

    # systemd stubs
    stub = "%s/linuxx64.efi.stub" % d.getVar('DEPLOY_DIR_IMAGE')
    if not os.path.exists(stub):
        bb.fatal(f"ERROR: cannot find {stub}.")
    ukify_cmd += " --stub %s" % (stub)
	
    # initrd
    initrd = '%s/initrd' % build_dir
    initramfs_image = "%s" % (d.getVar('INITRD_ARCHIVE'))
    if d.getVar('INITRD_LIVE'):
        with open(initrd, 'wb') as dst:
            for cpio in d.getVar('INITRD_LIVE').split():
                with open(cpio, 'rb') as src:
                    dst.write(src.read())
        ukify_cmd += " --initrd=%s" % initrd
    else:
        ukify_cmd += ""

    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE')

    # kernel
    kernel_filename = d.getVar('UKI_KERNEL_FILENAME') or None
    if kernel_filename:
        kernel = "%s/%s" % (deploy_dir_image, kernel_filename)
        if not os.path.exists(kernel):
            bb.fatal(f"ERROR: cannot find %s" % (kernel))
        ukify_cmd += " --linux=%s" % (kernel)
        # not always needed, ukify can detect version from kernel binary
        kernel_version = d.getVar('KERNEL_VERSION')
        if kernel_version:
            ukify_cmd += "--uname %s" % (kernel_version)
    else:
        bb.fatal("ERROR - UKI_KERNEL_FILENAME not set")

    # command line
    cmdline = d.getVar('UKI_CMDLINE')
    if cmdline:
        ukify_cmd += " --cmdline='%s'" % (cmdline)

    # dtb
    if d.getVar('KERNEL_DEVICETREE'):
        for dtb in d.getVar('KERNEL_DEVICETREE').split():
            dtb_path = "%s/%s" % (deploy_dir_image, dtb)
            if not os.path.exists(dtb_path):
                bb.fatal(f"ERROR: cannot find {dtb_path}.")
            ukify_cmd += " --devicetree %s" % (dtb_path)

    # custom config for ukify
    if os.path.exists(d.getVar('UKI_CONFIG_FILE')):
        ukify_cmd += " --config=%s" % (d.getVar('UKI_CONFIG_FILE'))

    # systemd tools
    ukify_cmd += " --tools=%s%s/lib/systemd/tools" % \
        (d.getVar("RECIPE_SYSROOT_NATIVE"), d.getVar("prefix"))

    # version
    ukify_cmd += " --os-release=@%s%s/lib/os-release" % \
        (d.getVar("RECIPE_SYSROOT"), d.getVar("prefix"))

    # TODO: tpm2 measure for secure boot, depends on systemd-native and TPM tooling
    # needed in systemd > 254 to fulfill ConditionSecurity=measured-uki
    # Requires TPM device on build host, thus not supported at build time.
    #ukify_cmd += " --measure"

    # securebooot signing, also for kernel
    key = d.getVar('SECURE_BOOT_SIGNING_KEY')
    if key:
        ukify_cmd += " --sign-kernel --secureboot-private-key='%s'" % (key)
    cert = d.getVar('SECURE_BOOT_SIGNING_CERT')
    if cert:
        ukify_cmd += " --secureboot-certificate='%s'" % (cert)

    # custom output UKI filename
    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE')
    image_link_name = d.getVar('IMAGE_LINK_NAME')
    m = re.match(r"\S*(ia32|x64)(.efi)\S*", os.path.basename(stub))
    app = "boot%s%s%s" % (m.group(1), app_suffix, m.group(2))
    output = " --output=%s/%s.%s" % (deploy_dir_image, image_link_name, app)
    ukify_cmd += " %s" % (output)

    # Run the ukify command
    bb.debug(2, "uki: running command: %s" % (ukify_cmd))
    bb.process.run(ukify_cmd, shell=True)

python create_uefiapps () {
    # We must clean up anything that matches the expected output pattern, to ensure that
    # the next steps do not accidentally use old files.
    import glob
    pattern = d.expand('${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.boot*.efi')
    for old_efi in glob.glob(pattern):
        os.unlink(old_efi)
    uuid = d.getVar('DISK_SIGNATURE_UUID')
    create_uefiapp(d, uuid=uuid)
}

# This is intentionally split into different parts. This way, derived
# classes or images can extend the individual parts. We can also use
# whatever language (shell script or Python) is more suitable.
python do_uefiapp() {
    bb.build.exec_func('create_uefiapps', d)
}

do_uefiapp[vardeps] += "APPEND DISK_SIGNATURE_UUID INITRD_LIVE KERNEL_IMAGETYPE IMAGE_LINK_NAME"

uefiapp_deploy_at() {
    dest=$1
    for i in ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.boot*.efi; do
        target=`basename $i`
        target=`echo $target | sed -e 's/${IMAGE_LINK_NAME}.//'`
        cp  --preserve=timestamps -r $i $dest/$target
    done
}

fakeroot do_uefiapp_deploy() {
    rm -rf ${IMAGE_ROOTFS}/boot/*
    dest=${IMAGE_ROOTFS}/boot/EFI/BOOT
    mkdir -p $dest
    uefiapp_deploy_at $dest
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


