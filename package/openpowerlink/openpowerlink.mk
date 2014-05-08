################################################################################
#
# openpowerlink
#
################################################################################

OPENPOWERLINK_VERSION = V1.08.4
OPENPOWERLINK_SITE = http://git.code.sf.net/p/openpowerlink/code
OPENPOWERLINK_SITE_METHOD = git
OPENPOWERLINK_LICENSE = BSD-2c, GPLv2
OPENPOWERLINK_LICENSE_FILES = license.txt
OPENPOWERLINK_INSTALL_STAGING = YES

ifeq ($(BR2_i386),y)
OPENPOWERLINK_ARCH = x86
endif

ifeq ($(BR2_x86_64),y)
OPENPOWERLINK_ARCH = x86_64
endif

OPENPOWERLINK_CONF_OPT = -DCMAKE_SYSTEM_PROCESSOR=$(OPENPOWERLINK_ARCH)

# There is no shared lib in openpowerlink,
# so force static lib to build libpowerlink.a
OPENPOWERLINK_CONF_OPT += -DBUILD_SHARED_LIBS=OFF

ifeq ($(BR2_ENABLE_DEBUG),y)
OPENPOWERLINK_CONF_OPT += -DCMAKE_BUILD_TYPE=Debug
else
OPENPOWERLINK_CONF_OPT += -DCMAKE_BUILD_TYPE=Release
endif

OPENPOWERLINK_CONF_OPT += -DCFG_DEBUG_LVL=$(call qstrip,$(BR2_PACKAGE_OPENPOWERLINK_DEBUG_LEVEL))

ifeq ($(BR2_PACKAGE_OPENPOWERLINK_LIBPCAP),y)
#  use the user space stack (libpcap)
OPENPOWERLINK_CONF_OPT += -DCFG_KERNEL_STACK=OFF
OPENPOWERLINK_DEPENDENCIES = libpcap
define OPENPOWERLINK_REMOVE_LIB
	rm $(TARGET_DIR)/usr/lib/libpowerlink.a
endef
OPENPOWERLINK_POST_INSTALL_TARGET_HOOKS += OPENPOWERLINK_REMOVE_LIB
else
# use the kernel stack
OPENPOWERLINK_CONF_OPT += -DCFG_KERNEL_STACK=ON \
		-DCFG_KERNEL_DIR=$(LINUX_DIR) \
		-DCMAKE_SYSTEM_VERSION=$(LINUX_VERSION)
OPENPOWERLINK_DEPENDENCIES = linux
endif

ifeq ($(BR2_PACKAGE_OPENPOWERLINK_82573),y)
OPENPOWERLINK_CONF_OPT += -DCFG_POWERLINK_EDRV=82573
else ifeq ($(BR2_PACKAGE_OPENPOWERLINK_RTL8139),y)
OPENPOWERLINK_CONF_OPT += -DCFG_POWERLINK_EDRV=8139
else ifeq ($(BR2_PACKAGE_OPENPOWERLINK_8255x),y)
OPENPOWERLINK_CONF_OPT += -DCFG_POWERLINK_EDRV=8255x
endif

ifeq ($(BR2_PACKAGE_OPENPOWERLINK_MN),y)
OPENPOWERLINK_CONF_OPT += -DCFG_POWERLINK_MN=ON
else
OPENPOWERLINK_CONF_OPT += -DCFG_POWERLINK_MN=OFF
endif

ifeq ($(BR2_PACKAGE_OPENPOWERLINK_DEMO_MN_CONSOLE),y)
OPENPOWERLINK_CONF_OPT += -DCFG_X86_DEMO_MN_CONSOLE=ON
else
OPENPOWERLINK_CONF_OPT += -DCFG_X86_DEMO_MN_CONSOLE=OFF
endif

ifeq ($(BR2_PACKAGE_OPENPOWERLINK_DEMO_MN_QT),y)
OPENPOWERLINK_CONF_OPT += -DCFG_X86_DEMO_MN_QT=ON
OPENPOWERLINK_DEPENDENCIES += qt
else
OPENPOWERLINK_CONF_OPT += -DCFG_X86_DEMO_MN_QT=OFF
endif

ifeq ($(BR2_PACKAGE_OPENPOWERLINK_DEMO_CN_CONSOLE),y)
OPENPOWERLINK_CONF_OPT += -DCFG_X86_DEMO_CN_CONSOLE=ON
else
OPENPOWERLINK_CONF_OPT += -DCFG_X86_DEMO_CN_CONSOLE=OFF
endif

ifeq ($(BR2_PACKAGE_OPENPOWERLINK_DEMO_LINUX_KERNEL),y)
OPENPOWERLINK_CONF_OPT += -DCFG_X86_DEMO_LINUX_KERNEL=ON
else
OPENPOWERLINK_CONF_OPT += -DCFG_X86_DEMO_LINUX_KERNEL=OFF
endif

$(eval $(cmake-package))
