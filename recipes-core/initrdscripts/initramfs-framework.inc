FILESEXTRAPATHS:prepend := "${THISDIR}/initramfs-framework-dm:"

SRC_URI:append = "\
    file://dmverity2 \
"
do_compile (){
cp dmverity2 dmverity
}
do_install:append() {
    # dm-verity
    install ${WORKDIR}/dmverity2 ${D}/init.d/80-dmverity
}

SUMMARY:initramfs-module-dmverity = "initramfs dm-verity rootfs support"
RDEPENDS:initramfs-module-dmverity = "${PN}-base"
FILES:initramfs-module-dmverity = "/init.d/80-dmverity"

