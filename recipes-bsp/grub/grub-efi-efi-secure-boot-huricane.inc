
do_compile:append(){
sed -i 's/LABEL=root/LABEL=active/g' ../boot-menu.inc
}
