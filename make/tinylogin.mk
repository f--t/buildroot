#############################################################
#
# tinylogin
#
#############################################################
TINYLOGIN_DIR:=$(BUILD_DIR)/tinylogin-1.4
TINYLOGIN_SOURCE:=tinylogin-1.4.tar.bz2
TINYLOGIN_SITE:=http://tinylogin.busybox.net/downloads

$(DL_DIR)/$(TINYLOGIN_SOURCE):
	$(WGET) -P $(DL_DIR) $(TINYLOGIN_SITE)/$(TINYLOGIN_SOURCE)

tinylogin-source: $(DL_DIR)/$(TINYLOGIN_SOURCE)

$(TINYLOGIN_DIR)/Config.h: $(DL_DIR)/$(TINYLOGIN_SOURCE)
	bzcat $(DL_DIR)/$(TINYLOGIN_SOURCE) | tar -C $(BUILD_DIR) -xvf -
	perl -i -p -e "s/\`id -u\` -ne 0/0 == 1/;" \
		-e "s/4755 --owner=root --group=root/755/" \
		$(TINYLOGIN_DIR)/install.sh
	perl -i -p -e "s/^DOSTATIC.*/DOSTATIC=false/g;" $(TINYLOGIN_DIR)/Makefile
	perl -i -p -e "s/^DODEBUG.*/DODEBUG=false/g;" $(TINYLOGIN_DIR)/Makefile
	# date test this one
	touch $(TINYLOGIN_DIR)/Config.h

$(TINYLOGIN_DIR)/tinylogin: $(TINYLOGIN_DIR)/Config.h
	make CROSS="$(TARGET_CROSS)" -C $(TINYLOGIN_DIR)

$(TARGET_DIR)/bin/tinylogin: $(TINYLOGIN_DIR)/tinylogin
	make CROSS="$(TARGET_CROSS)" PREFIX="$(TARGET_DIR)" -C $(TINYLOGIN_DIR) install

tinylogin: uclibc $(TARGET_DIR)/bin/tinylogin

tinylogin-clean:
	rm -f $(TARGET_DIR)/bin/tinylogin
	-make -C $(TINYLOGIN_DIR) clean

tinylogin-dirclean:
	rm -rf $(TINYLOGIN_DIR)
