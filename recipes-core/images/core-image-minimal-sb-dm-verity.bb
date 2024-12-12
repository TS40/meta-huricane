IMAGE_INSTALL = "packagegroup-core-boot ${CORE_IMAGE_EXTRA_INSTALL}"

IMAGE_LINGUAS = " "

LICENSE = "MIT"

inherit core-image

IMAGE_ROOTFS_SIZE ?= "8192"
IMAGE_ROOTFS_EXTRA_SPACE:append = "${@bb.utils.contains("DISTRO_FEATURES", "systemd", " + 4096", "", d)}"

DEPENDS += "\
    os-release \
    systemd-boot \
    systemd-boot-native \
    virtual/${TARGET_PREFIX}binutils \
    virtual/kernel \
    python3-pefile-native\
"

def create_uefiapp(d, uuid=None, app_suffix=''):
    import glob, re, shutil
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
        ukify_cmd += " --cmdline='rootwait root=/dev/sda2 selinux=1 '"

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
    
    if os.path.exists("%s/boot" % (deploy_dir_image)):
        shutil.rmtree("%s/boot" % (deploy_dir_image))
    os.mkdir("%s/boot" % (deploy_dir_image))
    os.mkdir("%s/boot/EFI" % (deploy_dir_image)) 
    os.mkdir("%s/boot/EFI/BOOT" % (deploy_dir_image)) 
    output = " --output=%s/boot/EFI/BOOT/bootx64.efi" % (deploy_dir_image)
    ukify_cmd += " %s" % (output)

    # Run the ukify command
    bb.debug(2, "uki: running command: %s" % (ukify_cmd))
    bb.process.run(ukify_cmd, shell=True)
    if os.path.exists("%s/boot.img" % (deploy_dir_image)):
        os.remove("%s/boot.img"% (deploy_dir_image)) 
    bb.process.run("dd if=/dev/zero of=%s/boot.img bs=1M count=100"% (deploy_dir_image), shell=True)
    bb.process.run("mkfs.vfat -n MSDOS %s/boot.img"% (deploy_dir_image), shell=True)
    bb.process.run("mcopy -i %s/boot.img %s/boot/EFI/  ::"% (deploy_dir_image,deploy_dir_image), shell=True)
    bb.process.run("mcopy -i %s/boot.img %s/boot/EFI/BOOT  ::EFI/"% (deploy_dir_image,deploy_dir_image), shell=True)

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
do_image_complete[depends] += "${@ '${INITRD_IMAGE}:do_image_complete' if d.getVar('INITRD_IMAGE') else ''}"
do_image_complete[depends] += " \
                         intel-microcode:do_deploy \
                         systemd-boot:do_deploy \
                         virtual/kernel:do_deploy \
                       "
python do_image_complete() {
    bb.build.exec_func('create_uefiapps', d)
}
