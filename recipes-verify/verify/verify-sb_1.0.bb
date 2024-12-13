DESCRIPTION = "DESCRIPTION"
HOMEPAGE = "HOMEPAGE"
LICENSE = "MIT"
SUMMARY = "sumary"
SECTION = "SECTION"

LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
SRC_URI:append = "\
    file://verify.cpp\
"
TARGET_CC_ARCH += "${LDFLAGS}"
SRC_URI = ""
DEPENDS="openssl"
do_compile(){
${CC} ${WORKDIR}/verify.cpp -lcrypto -o ${WORKDIR}/verify
}

do_install(){

install ${WORKDIR}/verify ${D}

}

PACKAGES = "verify-sb verify-sb-dbg"
FILES:${PN}="verify"
FILES:${PN}-dbg=".debug/"
RDEPENDS:${PN} = "openssl glibc"
