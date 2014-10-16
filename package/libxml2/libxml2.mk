################################################################################
#
# libxml2
#
################################################################################

LIBXML2_VERSION = 2.9.2
LIBXML2_SITE = ftp://xmlsoft.org/libxml2
LIBXML2_INSTALL_STAGING = YES
LIBXML2_AUTORECONF = YES
LIBXML2_LICENSE = MIT
LIBXML2_LICENSE_FILES = COPYING
LIBXML2_CONFIG_SCRIPTS = xml2-config

ifneq ($(BR2_LARGEFILE),y)
LIBXML2_CONF_ENV = CC="$(TARGET_CC) $(TARGET_CFLAGS) -DNO_LARGEFILE_SOURCE"
endif

LIBXML2_CONF_OPTS = --with-gnu-ld --without-python --without-debug --without-lzma

HOST_LIBXML2_DEPENDENCIES = host-pkgconf
LIBXML2_DEPENDENCIES = host-pkgconf

HOST_LIBXML2_CONF_OPTS = --without-zlib --without-lzma --without-python

ifeq ($(BR2_PACKAGE_ZLIB),y)
LIBXML2_DEPENDENCIES += zlib
LIBXML2_CONF_OPTS += --with-zlib
else
LIBXML2_CONF_OPTS += --without-zlib
endif

LIBXML2_DEPENDENCIES += $(if $(BR2_PACKAGE_LIBICONV),libiconv)

ifeq ($(BR2_ENABLE_LOCALE)$(BR2_PACKAGE_LIBICONV),y)
LIBXML2_CONF_OPTS += --with-iconv
else
LIBXML2_CONF_OPTS += --without-iconv
endif

$(eval $(autotools-package))
$(eval $(host-autotools-package))

# libxml2 for the host
LIBXML2_HOST_BINARY = $(HOST_DIR)/usr/bin/xmllint
