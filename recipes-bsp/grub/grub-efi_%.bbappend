require ${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', 'grub-efi-efi-secure-boot-huricane.inc', '', d)}
