# AliSecBypass v4.3 - Theos Makefile
# fishhook + ObjC Runtime 混合方案
# 纯库文件编译，无 Logos，TrollStore / 非越狱注入

TARGET := iphone:clang:latest:15.0
ARCHS = arm64

THEOS ?= $(HOME)/theos
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = AliSecBypass_v4

# fishhook 路径
FISHHOOK_PATH ?= $(PWD)/fishhook

AliSecBypass_v4_FILES = AliSecBypass_v4.mm
AliSecBypass_v4_CFLAGS = -fobjc-arc -std=c++11 -fno-modules -fno-implicit-modules \
  -Wno-unused-function -Wno-unused-variable \
  -I$(FISHHOOK_PATH)
AliSecBypass_v4_CCFLAGS = -std=c++11 -fno-modules -fno-implicit-modules \
  -Wno-unused-function -Wno-unused-variable \
  -I$(FISHHOOK_PATH)

# 自动查找 fishhook 静态库
FISHHOOK_LIB = $(shell find $(FISHHOOK_PATH) -name "libfishhook.a" | head -1)

ifeq ($(FISHHOOK_LIB),)
  $(warning fishhook static library not found!)
else
  AliSecBypass_v4_LDFLAGS += $(FISHHOOK_LIB)
  $(info Using fishhook library: $(FISHHOOK_LIB))
endif

AliSecBypass_v4_LDFLAGS += -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/library.mk
