# AliSecBypass v4 - Theos Makefile
# 纯库文件编译，无 Logos，TrollStore / 非越狱注入

TARGET := iphone:clang:latest:15.0
ARCHS = arm64

THEOS ?= $(HOME)/theos
include $(THEOS)/makefiles/common.mk

# 用 library.mk 代替 tweak.mk，纯 dylib 不需要 plist
LIBRARY_NAME = AliSecBypass_v4

AliSecBypass_v4_FILES = AliSecBypass_v4.mm

# C/C++ 编译选项
AliSecBypass_v4_CFLAGS = -fobjc-arc -std=c++11 -fno-modules -fno-implicit-modules -Wno-unused-function -Wno-unused-variable
AliSecBypass_v4_CCFLAGS = -std=c++11 -fno-modules -fno-implicit-modules -Wno-unused-function -Wno-unused-variable

# Dobby 路径
DOBBY_PATH ?= $(PWD)/dobby
AliSecBypass_v4_CFLAGS += -I$(DOBBY_PATH)/include

# 自动查找 Dobby 静态库
DOBBY_LIB = $(shell find $(DOBBY_PATH) -name "libdobby.a" | head -1)

ifeq ($(DOBBY_LIB),)
  $(warning Dobby static library not found!)
else
  AliSecBypass_v4_LDFLAGS += $(DOBBY_LIB)
  $(info Using Dobby library: $(DOBBY_LIB))
endif

AliSecBypass_v4_LDFLAGS += -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/library.mk
