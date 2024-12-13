FILESEXTRAPATHS:prepend := "${THISDIR}/initramfs-framework-dm:"
DEPENDS +="openssl"
SRC_URI:append = "\
    file://dmverity2 \
"
do_compile (){
cp dmverity2 dmverity
cp ${SECURE_BOOT_SIGNING_CERT}.pub ${WORKDIR}/cert.pem
}
do_install:append() {
    # dm-verity 
    install ${WORKDIR}/cert.pem ${D}
}
PACKAGES:append = " initramfs-module-dmverity-sig"
SUMMARY:initramfs-module-dmverity = "initramfs dm-verity rootfs support"
RDEPENDS:initramfs-module-dmverity = "${PN}-base"
FILES:initramfs-module-dmverity-sig += " cert.pem"
