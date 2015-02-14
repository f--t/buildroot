################################################################################
#
# toolchain-external
#
################################################################################

#
# This package implements the support for external toolchains, i.e
# toolchains that have not been produced by Buildroot itself and that
# Buildroot can download from the Web or that are already available on
# the system on which Buildroot runs. So far, we have tested this
# with:
#
#  * Toolchains generated by Crosstool-NG
#  * Toolchains generated by Buildroot
#  * Toolchains provided by Linaro for the ARM and AArch64
#    architectures
#  * Sourcery CodeBench toolchains (from Mentor Graphics) for the ARM,
#    MIPS, PowerPC, x86, x86_64 and NIOS 2 architectures. For the MIPS
#    toolchain, the -muclibc variant isn't supported yet, only the
#    default glibc-based variant is.
#  * Analog Devices toolchains for the Blackfin architecture
#  * Xilinx toolchains for the Microblaze architecture
#
# The basic principle is the following
#
#  1. If the toolchain is not pre-installed, download and extract it
#  in $(TOOLCHAIN_EXTERNAL_INSTALL_DIR). Otherwise,
#  $(TOOLCHAIN_EXTERNAL_INSTALL_DIR) points to were the toolchain has
#  already been installed by the user.
#
#  2. For all external toolchains, perform some checks on the
#  conformity between the toolchain configuration described in the
#  Buildroot menuconfig system, and the real configuration of the
#  external toolchain. This is for example important to make sure that
#  the Buildroot configuration system knows whether the toolchain
#  supports RPC, IPv6, locales, large files, etc. Unfortunately, these
#  things cannot be detected automatically, since the value of these
#  options (such as BR2_TOOLCHAIN_HAS_NATIVE_RPC) are needed at
#  configuration time because these options are used as dependencies
#  for other options. And at configuration time, we are not able to
#  retrieve the external toolchain configuration.
#
#  3. Copy the libraries needed at runtime to the target directory,
#  $(TARGET_DIR). Obviously, things such as the C library, the dynamic
#  loader and a few other utility libraries are needed if dynamic
#  applications are to be executed on the target system.
#
#  4. Copy the libraries and headers to the staging directory. This
#  will allow all further calls to gcc to be made using --sysroot
#  $(STAGING_DIR), which greatly simplifies the compilation of the
#  packages when using external toolchains. So in the end, only the
#  cross-compiler binaries remains external, all libraries and headers
#  are imported into the Buildroot tree.
#
#  5. Build a toolchain wrapper which executes the external toolchain
#  with a number of arguments (sysroot/march/mtune/..) hardcoded,
#  so we're sure the correct configuration is always used and the
#  toolchain behaves similar to an internal toolchain.
#  This toolchain wrapper and symlinks are installed into
#  $(HOST_DIR)/usr/bin like for the internal toolchains, and the rest
#  of Buildroot is handled identical for the 2 toolchain types.

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_GLIBC)$(BR2_TOOLCHAIN_EXTERNAL_UCLIBC),y)
LIB_EXTERNAL_LIBS += libc.so.* libcrypt.so.* libdl.so.* libgcc_s.so.* libm.so.* libnsl.so.* libresolv.so.* librt.so.* libutil.so.*
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_GLIBC)$(BR2_ARM_EABIHF),yy)
LIB_EXTERNAL_LIBS += ld-linux-armhf.so.*
else
LIB_EXTERNAL_LIBS += ld*.so.*
endif
ifeq ($(BR2_TOOLCHAIN_HAS_THREADS),y)
LIB_EXTERNAL_LIBS += libpthread.so.*
ifneq ($(BR2_PACKAGE_GDB)$(BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY),)
LIB_EXTERNAL_LIBS += libthread_db.so.*
endif # gdbserver
endif # ! no threads
endif

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_GLIBC),y)
LIB_EXTERNAL_LIBS += libnss_files.so.* libnss_dns.so.*
endif

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_MUSL),y)
LIB_EXTERNAL_LIBS += libc.so libgcc_s.so.*
endif

ifeq ($(BR2_INSTALL_LIBSTDCPP),y)
USR_LIB_EXTERNAL_LIBS += libstdc++.so.*
endif

LIB_EXTERNAL_LIBS += $(call qstrip,$(BR2_TOOLCHAIN_EXTRA_EXTERNAL_LIBS))

# Details about sysroot directory selection.
#
# To find the sysroot directory, we use the trick of looking for the
# 'libc.a' file with the -print-file-name gcc option, and then
# mangling the path to find the base directory of the sysroot.
#
# Note that we do not use the -print-sysroot option, because it is
# only available since gcc 4.4.x, and we only recently dropped support
# for 4.2.x and 4.3.x.
#
# When doing this, we don't pass any option to gcc that could select a
# multilib variant (such as -march) as we want the "main" sysroot,
# which contains all variants of the C library in the case of multilib
# toolchains. We use the TARGET_CC_NO_SYSROOT variable, which is the
# path of the cross-compiler, without the --sysroot=$(STAGING_DIR),
# since what we want to find is the location of the original toolchain
# sysroot. This "main" sysroot directory is stored in SYSROOT_DIR.
#
# Then, multilib toolchains are a little bit more complicated, since
# they in fact have multiple sysroots, one for each variant supported
# by the toolchain. So we need to find the particular sysroot we're
# interested in.
#
# To do so, we ask the compiler where its sysroot is by passing all
# flags (including -march and al.), except the --sysroot flag since we
# want to the compiler to tell us where its original sysroot
# is. ARCH_SUBDIR will contain the subdirectory, in the main
# SYSROOT_DIR, that corresponds to the selected architecture
# variant. ARCH_SYSROOT_DIR will contain the full path to this
# location.
#
# One might wonder why we don't just bother with ARCH_SYSROOT_DIR. The
# fact is that in multilib toolchains, the header files are often only
# present in the main sysroot, and only the libraries are available in
# each variant-specific sysroot directory.


TOOLCHAIN_EXTERNAL_PREFIX = $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_PREFIX))
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD),y)
TOOLCHAIN_EXTERNAL_INSTALL_DIR = $(HOST_DIR)/opt/ext-toolchain
else
TOOLCHAIN_EXTERNAL_INSTALL_DIR = $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_PATH))
endif

ifeq ($(TOOLCHAIN_EXTERNAL_INSTALL_DIR),)
ifneq ($(TOOLCHAIN_EXTERNAL_PREFIX),)
# if no path set, figure it out from path
TOOLCHAIN_EXTERNAL_BIN := $(shell dirname $(shell which $(TOOLCHAIN_EXTERNAL_PREFIX)-gcc))
endif
else
ifeq ($(BR2_bfin),y)
TOOLCHAIN_EXTERNAL_BIN := $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/$(TOOLCHAIN_EXTERNAL_PREFIX)/bin
else
TOOLCHAIN_EXTERNAL_BIN := $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/bin
endif
endif

TOOLCHAIN_EXTERNAL_CROSS = $(TOOLCHAIN_EXTERNAL_BIN)/$(TOOLCHAIN_EXTERNAL_PREFIX)-
TOOLCHAIN_EXTERNAL_CC = $(TOOLCHAIN_EXTERNAL_CROSS)gcc
TOOLCHAIN_EXTERNAL_CXX = $(TOOLCHAIN_EXTERNAL_CROSS)g++
TOOLCHAIN_EXTERNAL_READELF = $(TOOLCHAIN_EXTERNAL_CROSS)readelf
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS = -DBR_SYSROOT='"$(STAGING_SUBDIR)"'

ifeq ($(filter $(HOST_DIR)/%,$(TOOLCHAIN_EXTERNAL_BIN)),)
# TOOLCHAIN_EXTERNAL_BIN points outside HOST_DIR => absolute path
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += \
	-DBR_CROSS_PATH_ABS='"$(TOOLCHAIN_EXTERNAL_BIN)"'
else
# TOOLCHAIN_EXTERNAL_BIN points inside HOST_DIR => relative path
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += \
	-DBR_CROSS_PATH_REL='"$(TOOLCHAIN_EXTERNAL_BIN:$(HOST_DIR)/%=%)"'
endif

ifeq ($(call qstrip,$(BR2_GCC_TARGET_CPU_REVISION)),)
CC_TARGET_CPU_ := $(call qstrip,$(BR2_GCC_TARGET_CPU))
else
CC_TARGET_CPU_ := $(call qstrip,$(BR2_GCC_TARGET_CPU)-$(BR2_GCC_TARGET_CPU_REVISION))
endif
CC_TARGET_ARCH_ := $(call qstrip,$(BR2_GCC_TARGET_ARCH))
CC_TARGET_ABI_ := $(call qstrip,$(BR2_GCC_TARGET_ABI))
CC_TARGET_FPU_ := $(call qstrip,$(BR2_GCC_TARGET_FPU))
CC_TARGET_FLOAT_ABI_ := $(call qstrip,$(BR2_GCC_TARGET_FLOAT_ABI))
CC_TARGET_MODE_ := $(call qstrip,$(BR2_GCC_TARGET_MODE))

# march/mtune/floating point mode needs to be passed to the external toolchain
# to select the right multilib variant
ifeq ($(BR2_x86_64),y)
TOOLCHAIN_EXTERNAL_CFLAGS += -m64
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_64
endif
ifneq ($(CC_TARGET_ARCH_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -march=$(CC_TARGET_ARCH_)
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_ARCH='"$(CC_TARGET_ARCH_)"'
endif
ifneq ($(CC_TARGET_CPU_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mcpu=$(CC_TARGET_CPU_)
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_CPU='"$(CC_TARGET_CPU_)"'
endif
ifneq ($(CC_TARGET_ABI_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mabi=$(CC_TARGET_ABI_)
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_ABI='"$(CC_TARGET_ABI_)"'
endif
ifneq ($(CC_TARGET_FPU_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mfpu=$(CC_TARGET_FPU_)
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_FPU='"$(CC_TARGET_FPU_)"'
endif
ifneq ($(CC_TARGET_FLOAT_ABI_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mfloat-abi=$(CC_TARGET_FLOAT_ABI_)
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_FLOAT_ABI='"$(CC_TARGET_FLOAT_ABI_)"'
endif
ifneq ($(CC_TARGET_MODE_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -m$(CC_TARGET_MODE_)
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_MODE='"$(CC_TARGET_MODE_)"'
endif
ifeq ($(BR2_BINFMT_FLAT),y)
TOOLCHAIN_EXTERNAL_CFLAGS += -Wl,-elf2flt
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_BINFMT_FLAT
endif
ifeq ($(BR2_mipsel)$(BR2_mips64el),y)
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_MIPS_TARGET_LITTLE_ENDIAN
TOOLCHAIN_EXTERNAL_CFLAGS += -EL
endif
ifeq ($(BR2_mips)$(BR2_mips64),y)
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_MIPS_TARGET_BIG_ENDIAN
TOOLCHAIN_EXTERNAL_CFLAGS += -EB
endif
ifneq ($(BR2_TARGET_OPTIMIZATION),)
TOOLCHAIN_EXTERNAL_CFLAGS += $(call qstrip,$(BR2_TARGET_OPTIMIZATION))
# We create a list like '"-mfoo", "-mbar", "-mbarfoo"' so that each
# flag is a separate argument when used in execv() by the external
# toolchain wrapper.
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_ADDITIONAL_CFLAGS='$(foreach f,$(call qstrip,$(BR2_TARGET_OPTIMIZATION)),"$(f)",)'
endif

ifeq ($(BR2_SOFT_FLOAT),y)
TOOLCHAIN_EXTERNAL_CFLAGS += -msoft-float
TOOLCHAIN_EXTERNAL_WRAPPER_ARGS += -DBR_SOFTFLOAT=1
endif

# The Linaro ARMhf toolchain expects the libraries in
# {/usr,}/lib/arm-linux-gnueabihf, but Buildroot copies them to
# {/usr,}/lib, so we need to create a symbolic link.
define TOOLCHAIN_EXTERNAL_LINARO_ARMHF_SYMLINK
	ln -sf . $(TARGET_DIR)/lib/arm-linux-gnueabihf
	ln -sf . $(TARGET_DIR)/usr/lib/arm-linux-gnueabihf
endef

define TOOLCHAIN_EXTERNAL_LINARO_ARMEBHF_SYMLINK
	ln -sf . $(TARGET_DIR)/lib/armeb-linux-gnueabihf
	ln -sf . $(TARGET_DIR)/usr/lib/armeb-linux-gnueabihf
endef

define TOOLCHAIN_EXTERNAL_LINARO_AARCH64_SYMLINK
	ln -sf . $(TARGET_DIR)/lib/aarch64-linux-gnu
	ln -sf . $(TARGET_DIR)/usr/lib/aarch64-linux-gnu
endef

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_ARM201305),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/arm-none-linux-gnueabi/
TOOLCHAIN_EXTERNAL_SOURCE = arm-2013.05-24-arm-none-linux-gnueabi-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_ARM201311),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/arm-none-linux-gnueabi/
TOOLCHAIN_EXTERNAL_SOURCE = arm-2013.11-33-arm-none-linux-gnueabi-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_ARM201405),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/arm-none-linux-gnueabi/
TOOLCHAIN_EXTERNAL_SOURCE = arm-2014.05-29-arm-none-linux-gnueabi-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_ARAGO_ARMV7A_201109),y)
TOOLCHAIN_EXTERNAL_SITE = http://software-dl.ti.com/sdoemb/sdoemb_public_sw/arago_toolchain/2011_09/exports/
TOOLCHAIN_EXTERNAL_SOURCE = arago-2011.09-armv7a-linux-gnueabi-sdk.tar.bz2
define TOOLCHAIN_EXTERNAL_FIXUP_CMDS
	mv $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/arago-2011.09/armv7a/* $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/
	rm -rf $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/arago-2011.09/
endef
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_ARAGO_ARMV5TE_201109),y)
TOOLCHAIN_EXTERNAL_SITE = http://software-dl.ti.com/sdoemb/sdoemb_public_sw/arago_toolchain/2011_09/exports/
TOOLCHAIN_EXTERNAL_SOURCE = arago-2011.09-armv5te-linux-gnueabi-sdk.tar.bz2
define TOOLCHAIN_EXTERNAL_FIXUP_CMDS
	mv $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/arago-2011.09/armv5te/* $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/
	rm -rf $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/arago-2011.09/
endef
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_LINARO_ARM),y)
TOOLCHAIN_EXTERNAL_SITE = http://releases.linaro.org/14.09/components/toolchain/binaries/
TOOLCHAIN_EXTERNAL_SOURCE = gcc-linaro-arm-linux-gnueabihf-4.9-2014.09_linux.tar.xz
TOOLCHAIN_EXTERNAL_POST_INSTALL_STAGING_HOOKS += TOOLCHAIN_EXTERNAL_LINARO_ARMHF_SYMLINK
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_LINARO_ARMEB),y)
TOOLCHAIN_EXTERNAL_SITE = http://releases.linaro.org/14.09/components/toolchain/binaries/
TOOLCHAIN_EXTERNAL_SOURCE = gcc-linaro-armeb-linux-gnueabihf-4.9-2014.09_linux.tar.xz
TOOLCHAIN_EXTERNAL_POST_INSTALL_STAGING_HOOKS += TOOLCHAIN_EXTERNAL_LINARO_ARMEBHF_SYMLINK
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_MIPS201311),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/mips-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = mips-2013.11-36-mips-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_MIPS201405),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/mips-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = mips-2014.05-27-mips-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_MIPS201411),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/mips-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = mips-2014.11-22-mips-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_NIOSII201305),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/nios2-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = sourceryg++-2013.05-43-nios2-linux-gnu-i686-pc-linux-gnu.tar.bz2
TOOLCHAIN_EXTERNAL_POST_INSTALL_STAGING_HOOKS += TOOLCHAIN_EXTERNAL_SANITIZE_KERNEL_HEADERS
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_NIOSII201405),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/nios2-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = sourceryg++-2014.05-47-nios2-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_POWERPC201009),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/powerpc-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = freescale-2010.09-55-powerpc-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_POWERPC201103),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/powerpc-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = freescale-2011.03-38-powerpc-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_POWERPC201203),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/powerpc-mentor-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = mentor-2012.03-71-powerpc-mentor-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_SH201103),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/sh-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = renesas-2011.03-37-sh-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_SH201203),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/sh-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = renesas-2012.03-35-sh-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_SH201209),y)
TOOLCHAIN_EXTERNAL_SITE = https://sourcery.mentor.com/public/gnu_toolchain/sh-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = renesas-2012.09-61-sh-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_SH2A_201009),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/sh-uclinux/
TOOLCHAIN_EXTERNAL_SOURCE = renesas-2010.09-60-sh-uclinux-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_SH2A_201103),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/sh-uclinux/
TOOLCHAIN_EXTERNAL_SOURCE = renesas-2011.03-36-sh-uclinux-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_X86_201109),y)
TOOLCHAIN_EXTERNAL_SITE = https://sourcery.mentor.com/public/gnu_toolchain/i686-pc-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = ia32-2011.09-24-i686-pc-linux-gnu-i386-linux.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_X86_201203),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/i686-pc-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = ia32-2012.03-27-i686-pc-linux-gnu-i386-linux.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_X86_201209),y)
TOOLCHAIN_EXTERNAL_SITE = https://sourcery.mentor.com/public/gnu_toolchain/i686-pc-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = ia32-2012.09-62-i686-pc-linux-gnu-i386-linux.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_BLACKFIN_UCLINUX_2012R2),y)
TOOLCHAIN_EXTERNAL_SITE = http://downloads.sourceforge.net/project/adi-toolchain/2012R2/2012R2-RC2/i386/
TOOLCHAIN_EXTERNAL_SOURCE = blackfin-toolchain-2012R2-RC2.i386.tar.bz2
TOOLCHAIN_EXTERNAL_EXTRA_DOWNLOADS = blackfin-toolchain-uclibc-full-2012R2-RC2.i386.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_BLACKFIN_UCLINUX_2013R1),y)
TOOLCHAIN_EXTERNAL_SITE = http://downloads.sourceforge.net/project/adi-toolchain/2013R1/2013R1-RC1/i386/
TOOLCHAIN_EXTERNAL_SOURCE = blackfin-toolchain-2013R1-RC1.i386.tar.bz2
TOOLCHAIN_EXTERNAL_EXTRA_DOWNLOADS = blackfin-toolchain-uclibc-full-2013R1-RC1.i386.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_BLACKFIN_UCLINUX_2014R1),y)
TOOLCHAIN_EXTERNAL_SITE = http://downloads.sourceforge.net/project/adi-toolchain/2014R1/2014R1-RC2/i386/
TOOLCHAIN_EXTERNAL_SOURCE = blackfin-toolchain-2014R1-RC2.i386.tar.bz2
TOOLCHAIN_EXTERNAL_EXTRA_DOWNLOADS = blackfin-toolchain-uclibc-full-2014R1-RC2.i386.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_XILINX_MICROBLAZEEL_14_3),y)
TOOLCHAIN_EXTERNAL_SITE = http://sources.buildroot.net/
TOOLCHAIN_EXTERNAL_SOURCE = lin32-microblazeel-unknown-linux-gnu_14.3_early.tar.xz
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_XILINX_MICROBLAZEEL_V2),y)
TOOLCHAIN_EXTERNAL_SITE = http://sources.buildroot.net/
TOOLCHAIN_EXTERNAL_SOURCE = microblazeel-unknown-linux-gnu.tgz
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_XILINX_MICROBLAZEBE_14_3),y)
TOOLCHAIN_EXTERNAL_SITE = http://sources.buildroot.net/
TOOLCHAIN_EXTERNAL_SOURCE = lin32-microblaze-unknown-linux-gnu_14.3_early.tar.xz
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_XILINX_MICROBLAZEBE_V2),y)
TOOLCHAIN_EXTERNAL_SITE = http://sources.buildroot.net/
TOOLCHAIN_EXTERNAL_SOURCE = microblaze-unknown-linux-gnu.tgz
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_LINARO_AARCH64),y)
TOOLCHAIN_EXTERNAL_SITE = http://releases.linaro.org/14.09/components/toolchain/binaries/
TOOLCHAIN_EXTERNAL_SOURCE = gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux.tar.xz
TOOLCHAIN_EXTERNAL_POST_INSTALL_STAGING_HOOKS += TOOLCHAIN_EXTERNAL_LINARO_AARCH64_SYMLINK
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_AARCH64),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/aarch64-linux-gnu/
TOOLCHAIN_EXTERNAL_SOURCE = aarch64-2014.05-30-aarch64-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_MUSL_CROSS),y)
TOOLCHAIN_EXTERNAL_VERSION = 1.1.1
TOOLCHAIN_EXTERNAL_SITE = https://googledrive.com/host/0BwnS5DMB0YQ6bDhPZkpOYVFhbk0/musl-$(TOOLCHAIN_EXTERNAL_VERSION)/
ifeq ($(BR2_arm),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-arm-linux-musleabi-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_armeb),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-armeb-linux-musleabi-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_i386),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-i486-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_microblazebe),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-microblaze-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_mips),y)
ifeq ($(BR2_SOFT_FLOAT),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-mips-sf-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-mips-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
endif # BR2_SOFT_FLOAT
else ifeq ($(BR2_mipsel),y)
ifeq ($(BR2_SOFT_FLOAT),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-mipsel-sf-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-mipsel-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
endif # BR2_SOFT_FLOAT
else ifeq ($(BR2_powerpc),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-powerpc-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_x86_64),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-x86_64-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
endif
else
# Custom toolchain
TOOLCHAIN_EXTERNAL_SITE = $(dir $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_URL)))
TOOLCHAIN_EXTERNAL_SOURCE = $(notdir $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_URL)))
endif

# In fact, we don't need to download the toolchain, since it is already
# available on the system, so force the site and source to be empty so
# that nothing will be downloaded/extracted.
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED),y)
TOOLCHAIN_EXTERNAL_SITE =
TOOLCHAIN_EXTERNAL_SOURCE =
endif

TOOLCHAIN_EXTERNAL_ADD_TOOLCHAIN_DEPENDENCY = NO

TOOLCHAIN_EXTERNAL_INSTALL_STAGING = YES

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_BLACKFIN_UCLINUX_2012R2)$(BR2_TOOLCHAIN_EXTERNAL_BLACKFIN_UCLINUX_2013R1)$(BR2_TOOLCHAIN_EXTERNAL_BLACKFIN_UCLINUX_2014R1),y)
# Special handling for Blackfin toolchain, because of the split in two
# tarballs, and the organization of tarball contents. The tarballs
# contain ./opt/uClinux/{bfin-uclinux,bfin-linux-uclibc} directories,
# which themselves contain the toolchain. This is why we strip more
# components than usual.
define TOOLCHAIN_EXTERNAL_EXTRACT_CMDS
	mkdir -p $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)
	$(call suitable-extractor,$(TOOLCHAIN_EXTERNAL_SOURCE)) $(DL_DIR)/$(TOOLCHAIN_EXTERNAL_SOURCE) | \
		$(TAR) $(TAR_STRIP_COMPONENTS)=3 --hard-dereference -C $(TOOLCHAIN_EXTERNAL_INSTALL_DIR) $(TAR_OPTIONS) -
	$(call suitable-extractor,$(TOOLCHAIN_EXTERNAL_EXTRA_DOWNLOADS)) $(DL_DIR)/$(TOOLCHAIN_EXTERNAL_EXTRA_DOWNLOADS) | \
		$(TAR) $(TAR_STRIP_COMPONENTS)=3 --hard-dereference -C $(TOOLCHAIN_EXTERNAL_INSTALL_DIR) $(TAR_OPTIONS) -
endef
else ifneq ($(TOOLCHAIN_EXTERNAL_SOURCE),)
# Normal handling of toolchain tarball extraction.
define TOOLCHAIN_EXTERNAL_EXTRACT_CMDS
	mkdir -p $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)
	$(call suitable-extractor,$(TOOLCHAIN_EXTERNAL_SOURCE)) $(DL_DIR)/$(TOOLCHAIN_EXTERNAL_SOURCE) | \
		$(TAR) $(TAR_STRIP_COMPONENTS)=1 --exclude='usr/lib/locale/*' -C $(TOOLCHAIN_EXTERNAL_INSTALL_DIR) $(TAR_OPTIONS) -
	$(TOOLCHAIN_EXTERNAL_FIXUP_CMDS)
endef
endif

# Returns the location of the libc.a file for the given compiler + flags
define toolchain_find_libc_a
$$(readlink -f $$(LANG=C $(1) -print-file-name=libc.a))
endef

# Returns the sysroot location for the given compiler + flags
define toolchain_find_sysroot
$$(echo -n $(call toolchain_find_libc_a,$(1)) | sed -r -e 's:(usr/)?lib(32|64)?/([^/]*/)?libc\.a::')
endef

# Returns the lib subdirectory for the given compiler + flags (i.e
# typically lib32 or lib64 for some toolchains)
define toolchain_find_libdir
$$(echo -n $(call toolchain_find_libc_a,$(1)) | sed -r -e 's:.*/(usr/)?(lib(32|64)?)/([^/]*/)?libc.a:\2:')
endef

# Checks for an already installed toolchain: check the toolchain
# location, check that it supports sysroot, and then verify that it
# matches the configuration provided in Buildroot: ABI, C++ support,
# kernel headers version, type of C library and all C library features.
define TOOLCHAIN_EXTERNAL_CONFIGURE_CMDS
	$(Q)$(call check_cross_compiler_exists,$(TOOLCHAIN_EXTERNAL_CC))
	$(Q)$(call check_unusable_toolchain,$(TOOLCHAIN_EXTERNAL_CC))
	$(Q)SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC))" ; \
	if test -z "$${SYSROOT_DIR}" ; then \
		@echo "External toolchain doesn't support --sysroot. Cannot use." ; \
		exit 1 ; \
	fi ; \
	$(call check_kernel_headers_version,\
		$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC)),\
		$(call qstrip,$(BR2_TOOLCHAIN_HEADERS_AT_LEAST))); \
	if test "$(BR2_arm)" = "y" ; then \
		$(call check_arm_abi,\
			"$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS)",\
			$(TOOLCHAIN_EXTERNAL_READELF)) ; \
	fi ; \
	if test "$(BR2_INSTALL_LIBSTDCPP)" = "y" ; then \
		$(call check_cplusplus,$(TOOLCHAIN_EXTERNAL_CXX)) ; \
	fi ; \
	if test "$(BR2_TOOLCHAIN_EXTERNAL_UCLIBC)" = "y" ; then \
		$(call check_uclibc,$${SYSROOT_DIR}) ; \
	elif test "$(BR2_TOOLCHAIN_EXTERNAL_MUSL)" = "y" ; then \
		$(call check_musl,$${SYSROOT_DIR}) ; \
	else \
		$(call check_glibc,$${SYSROOT_DIR}) ; \
	fi
endef

# With the musl C library, the libc.so library directly plays the role
# of the dynamic library loader. We just need to create a symbolic
# link to libc.so with the appropriate name.
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_MUSL),y)
ifeq ($(BR2_i386),y)
MUSL_ARCH = i386
else
MUSL_ARCH = $(ARCH)
endif
define TOOLCHAIN_EXTERNAL_MUSL_LD_LINK
	ln -sf libc.so $(TARGET_DIR)/lib/ld-musl-$(MUSL_ARCH).so.1
endef
TOOLCHAIN_EXTERNAL_POST_INSTALL_STAGING_HOOKS += TOOLCHAIN_EXTERNAL_MUSL_LD_LINK
endif

# Integration of the toolchain into Buildroot: find the main sysroot
# and the variant-specific sysroot, then copy the needed libraries to
# the $(TARGET_DIR) and copy the whole sysroot (libraries and headers)
# to $(STAGING_DIR).
#
# Variables are defined as follows:
#
#  LIBC_A_LOCATION:     location of the libc.a file in the default
#                       multilib variant (allows to find the main
#                       sysroot directory)
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/usr/lib/libc.a
#
#  SYSROOT_DIR:         the main sysroot directory, deduced from
#                       LIBC_A_LOCATION by removing the
#                       usr/lib[32|64]/libc.a part of the path.
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/
#
# ARCH_LIBC_A_LOCATION: location of the libc.a file in the selected
#                       multilib variant (taking into account the
#                       CFLAGS). Allows to find the sysroot of the
#                       selected multilib variant.
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/mips16/soft-float/el/usr/lib/libc.a
#
# ARCH_SYSROOT_DIR:     the sysroot of the selected multilib variant,
#                       deduced from ARCH_LIBC_A_LOCATION by removing
#                       usr/lib[32|64]/libc.a at the end of the path.
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/mips16/soft-float/el/
#
# ARCH_LIB_DIR:         'lib', 'lib32' or 'lib64' depending on where libraries
#                       are stored. Deduced from ARCH_LIBC_A_LOCATION by
#                       looking at usr/lib??/libc.a.
#                       Ex: lib
#
# ARCH_SUBDIR:          the relative location of the sysroot of the selected
#                       multilib variant compared to the main sysroot.
#			Ex: mips16/soft-float/el
#
# SUPPORT_LIB_DIR:      some toolchains, such as recent Linaro toolchains,
#                       store GCC support libraries (libstdc++,
#                       libgcc_s, etc.) outside of the sysroot. In
#                       this case, SUPPORT_LIB_DIR is set to a
#                       non-empty value, and points to the directory
#                       where these support libraries are
#                       available. Those libraries will be copied to
#                       our sysroot, and the directory will also be
#                       considered when searching libraries for copy
#                       to the target filesystem.

define TOOLCHAIN_EXTERNAL_INSTALL_TARGET_LIBS
	$(Q)SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC))" ; \
	if test -z "$${SYSROOT_DIR}" ; then \
		@echo "External toolchain doesn't support --sysroot. Cannot use." ; \
		exit 1 ; \
	fi ; \
	ARCH_SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	ARCH_LIB_DIR="$(call toolchain_find_libdir,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	SUPPORT_LIB_DIR="" ; \
	if test `find $${ARCH_SYSROOT_DIR} -name 'libstdc++.a' | wc -l` -eq 0 ; then \
		LIBSTDCPP_A_LOCATION=$$(LANG=C $(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS) -print-file-name=libstdc++.a) ; \
		if [ -e "$${LIBSTDCPP_A_LOCATION}" ]; then \
			SUPPORT_LIB_DIR=`readlink -f $${LIBSTDCPP_A_LOCATION} | sed -r -e 's:libstdc\+\+\.a::'` ; \
		fi ; \
	fi ; \
	ARCH_SUBDIR=`echo $${ARCH_SYSROOT_DIR} | sed -r -e "s:^$${SYSROOT_DIR}(.*)/$$:\1:"` ; \
	if test -z "$(BR2_STATIC_LIBS)" ; then \
		$(call MESSAGE,"Copying external toolchain libraries to target...") ; \
		for libs in $(LIB_EXTERNAL_LIBS); do \
			$(call copy_toolchain_lib_root,$${ARCH_SYSROOT_DIR},$${SUPPORT_LIB_DIR},$${ARCH_LIB_DIR},$$libs,/lib); \
		done ; \
		for libs in $(USR_LIB_EXTERNAL_LIBS); do \
			$(call copy_toolchain_lib_root,$${ARCH_SYSROOT_DIR},$${SUPPORT_LIB_DIR},$${ARCH_LIB_DIR},$$libs,/usr/lib); \
		done ; \
	fi ; \
	if test "$(BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY)" = "y"; then \
		$(call MESSAGE,"Copying gdbserver") ; \
		gdbserver_found=0 ; \
		for d in $${ARCH_SYSROOT_DIR}/usr $${ARCH_SYSROOT_DIR}/../debug-root/usr $${ARCH_SYSROOT_DIR}/usr/$${ARCH_LIB_DIR} ; do \
			if test -f $${d}/bin/gdbserver ; then \
				install -m 0755 -D $${d}/bin/gdbserver $(TARGET_DIR)/usr/bin/gdbserver ; \
				gdbserver_found=1 ; \
				break ; \
			fi ; \
		done ; \
		if [ $${gdbserver_found} -eq 0 ] ; then \
			echo "Could not find gdbserver in external toolchain" ; \
			exit 1 ; \
		fi ; \
	fi
endef

define TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS
	$(Q)SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC))" ; \
	if test -z "$${SYSROOT_DIR}" ; then \
		@echo "External toolchain doesn't support --sysroot. Cannot use." ; \
		exit 1 ; \
	fi ; \
	ARCH_SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	ARCH_LIB_DIR="$(call toolchain_find_libdir,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	SUPPORT_LIB_DIR="" ; \
	if test `find $${ARCH_SYSROOT_DIR} -name 'libstdc++.a' | wc -l` -eq 0 ; then \
		LIBSTDCPP_A_LOCATION=$$(LANG=C $(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS) -print-file-name=libstdc++.a) ; \
		if [ -e "$${LIBSTDCPP_A_LOCATION}" ]; then \
			SUPPORT_LIB_DIR=`readlink -f $${LIBSTDCPP_A_LOCATION} | sed -r -e 's:libstdc\+\+\.a::'` ; \
		fi ; \
	fi ; \
	ARCH_SUBDIR=`echo $${ARCH_SYSROOT_DIR} | sed -r -e "s:^$${SYSROOT_DIR}(.*)/$$:\1:"` ; \
	$(call MESSAGE,"Copying external toolchain sysroot to staging...") ; \
	$(call copy_toolchain_sysroot,$${SYSROOT_DIR},$${ARCH_SYSROOT_DIR},$${ARCH_SUBDIR},$${ARCH_LIB_DIR},$${SUPPORT_LIB_DIR})
endef

# Special installation target used on the Blackfin architecture when
# FDPIC is not the primary binary format being used, but the user has
# nonetheless requested the installation of the FDPIC libraries to the
# target filesystem.
ifeq ($(BR2_BFIN_INSTALL_FDPIC_SHARED),y)
define TOOLCHAIN_EXTERNAL_INSTALL_BFIN_FDPIC
	$(Q)$(call MESSAGE,"Install external toolchain FDPIC libraries to target...") ; \
	FDPIC_EXTERNAL_CC=$(dir $(TOOLCHAIN_EXTERNAL_CC))/../../bfin-linux-uclibc/bin/bfin-linux-uclibc-gcc ; \
	FDPIC_SYSROOT_DIR="$(call toolchain_find_sysroot,$${FDPIC_EXTERNAL_CC} $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	FDPIC_LIB_DIR="$(call toolchain_find_libdir,$${FDPIC_EXTERNAL_CC} $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	FDPIC_SUPPORT_LIB_DIR="" ; \
	if test `find $${FDPIC_SYSROOT_DIR} -name 'libstdc++.a' | wc -l` -eq 0 ; then \
	        FDPIC_LIBSTDCPP_A_LOCATION=$$(LANG=C $${FDPIC_EXTERNAL_CC} $(TOOLCHAIN_EXTERNAL_CFLAGS) -print-file-name=libstdc++.a) ; \
	        if [ -e "$${FDPIC_LIBSTDCPP_A_LOCATION}" ]; then \
	                FDPIC_SUPPORT_LIB_DIR=`readlink -f $${FDPIC_LIBSTDCPP_A_LOCATION} | sed -r -e 's:libstdc\+\+\.a::'` ; \
	        fi ; \
	fi ; \
	for libs in $(LIB_EXTERNAL_LIBS); do \
	        $(call copy_toolchain_lib_root,$${FDPIC_SYSROOT_DIR},$${FDPIC_SUPPORT_LIB_DIR},$${FDPIC_LIB_DIR},$$libs,/lib); \
	done ; \
	for libs in $(USR_LIB_EXTERNAL_LIBS); do \
	        $(call copy_toolchain_lib_root,$${FDPIC_SYSROOT_DIR},$${FDPIC_SUPPORT_LIB_DIR},$${FDPIC_LIB_DIR},$$libs,/usr/lib); \
	done
endef
endif

# Special installation target used on the Blackfin architecture when
# shared FLAT is not the primary format being used, but the user has
# nonetheless requested the installation of the shared FLAT libraries
# to the target filesystem. The flat libraries are found and linked
# according to the index in name "libN.so". Index 1 is reserved for
# the standard C library. Customer libraries can use 4 and above.
ifeq ($(BR2_BFIN_INSTALL_FLAT_SHARED),y)
define TOOLCHAIN_EXTERNAL_INSTALL_BFIN_FLAT
	$(Q)$(call MESSAGE,"Install external toolchain FLAT libraries to target...") ; \
	FLAT_EXTERNAL_CC=$(dir $(TOOLCHAIN_EXTERNAL_CC))../../bfin-uclinux/bin/bfin-uclinux-gcc ; \
	FLAT_LIBC_A_LOCATION=`$${FLAT_EXTERNAL_CC} $(TOOLCHAIN_EXTERNAL_CFLAGS) -mid-shared-library -print-file-name=libc`; \
	if [ -f $${FLAT_LIBC_A_LOCATION} -a ! -h $${FLAT_LIBC_A_LOCATION} ] ; then \
	        $(INSTALL) -D $${FLAT_LIBC_A_LOCATION} $(TARGET_DIR)/lib/lib1.so; \
	fi
endef
endif

# We use --hash-style=both to increase the compatibility of
# the generated binary with older platforms, except for MIPS,
# where the only acceptable hash style is 'sysv'
ifeq ($(findstring mips,$(HOSTARCH)),mips)
TOOLCHAIN_EXTERNAL_WRAPPER_HASH_STYLE = sysv
else
TOOLCHAIN_EXTERNAL_WRAPPER_HASH_STYLE = both
endif

# Build toolchain wrapper for preprocessor, C and C++ compiler and setup
# symlinks for everything else. Skip gdb symlink when we are building our
# own gdb to prevent two gdb's in output/host/usr/bin.
define TOOLCHAIN_EXTERNAL_INSTALL_WRAPPER
	$(Q)$(call MESSAGE,"Building ext-toolchain wrapper")
	mkdir -p $(HOST_DIR)/usr/bin; cd $(HOST_DIR)/usr/bin; \
	for i in $(TOOLCHAIN_EXTERNAL_CROSS)*; do \
		base=$${i##*/}; \
		case "$$base" in \
		*cc|*cc-*|*++|*++-*|*cpp) \
			ln -sf ext-toolchain-wrapper $$base; \
			;; \
		*gdb|*gdbtui) \
			if test "$(BR2_PACKAGE_HOST_GDB)" != "y"; then \
				ln -sf $$(echo $$i | sed 's%^$(HOST_DIR)%../..%') .; \
			fi \
			;; \
		*) \
			ln -sf $$(echo $$i | sed 's%^$(HOST_DIR)%../..%') .; \
			;; \
		esac; \
	done ;
	$(HOSTCC) $(HOST_CFLAGS) $(TOOLCHAIN_EXTERNAL_WRAPPER_ARGS) \
		-s -Wl,--hash-style=$(TOOLCHAIN_EXTERNAL_WRAPPER_HASH_STYLE) \
		toolchain/toolchain-external/ext-toolchain-wrapper.c \
		-o $(HOST_DIR)/usr/bin/ext-toolchain-wrapper
endef

# This sed magic is taken from Linux headers_install.sh script.
define TOOLCHAIN_EXTERNAL_SANITIZE_KERNEL_HEADERS
	$(Q)$(call MESSAGE,"Sanitizing kernel headers");
	find $(STAGING_DIR)/usr/include/linux/ -name "*.h" | xargs sed -r -i \
		-e 's/([ \t(])(__user|__force|__iomem)[ \t]/\1/g' \
		-e 's/__attribute_const__([ \t]|$$)/\1/g' \
		-e 's@^#include <linux/compiler.h>@@' \
		-e 's/(^|[^a-zA-Z0-9])__packed([^a-zA-Z0-9_]|$$)/\1__attribute__((packed))\2/g' \
		-e 's/(^|[ \t(])(inline|asm|volatile)([ \t(]|$$)/\1__\2__\3/g' \
		-e 's@#(ifndef|define|endif[ \t]*/[*])[ \t]*_UAPI@#\1 @'
endef

define TOOLCHAIN_EXTERNAL_INSTALL_GDBINIT
	if test -f $(TARGET_CROSS)gdb ; then \
		$(call gen_gdbinit_file) ; \
	fi
endef

define TOOLCHAIN_EXTERNAL_INSTALL_STAGING_CMDS
	$(TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS)
	$(TOOLCHAIN_EXTERNAL_INSTALL_WRAPPER)
	$(TOOLCHAIN_EXTERNAL_INSTALL_GDBINIT)
endef

# Even though we're installing things in both the staging, the host
# and the target directory, we do everything within the
# install-staging step, arbitrarily.
define TOOLCHAIN_EXTERNAL_INSTALL_TARGET_CMDS
	$(TOOLCHAIN_EXTERNAL_INSTALL_TARGET_LIBS)
	$(TOOLCHAIN_EXTERNAL_INSTALL_BFIN_FDPIC)
	$(TOOLCHAIN_EXTERNAL_INSTALL_BFIN_FLAT)
endef

$(eval $(generic-package))
