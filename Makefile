# AliSecBypass v4.4 - Theos Makefile
# fishhook + Dobby + ObjC Runtime 混合方案
# 纯库文件编译，无 Logos，TrollStore / 非越狱注入

TARGET := iphone:clang:latest:15.0
ARCHS = arm64

THEOS ?= $(HOME)/theos
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = AliSecBypass_v4

# 源码文件
AliSecBypass_v4_FILES = AliSecBypass_v4.mm

# ========== 第三方库路径配置 ==========
# fishhook 路径（相对项目根目录）
FISHHOOK_PATH ?= $(PWD)/fishhook
# Dobby 路径（相对项目根目录）
DOBBY_PATH ?= $(PWD)/Dobby

# ========== 编译标志 ==========
AliSecBypass_v4_CFLAGS = -fobjc-arc -std=c++11 -fno-modules -fno-implicit-modules \
  -Wno-unused-function -Wno-unused-variable \
  -I$(FISHHOOK_PATH) \
  -I$(DOBBY_PATH)/include

AliSecBypass_v4_CCFLAGS = -std=c++11 -fno-modules -fno-implicit-modules \
  -Wno-unused-function -Wno-unused-variable \
  -I$(FISHHOOK_PATH) \
  -I$(DOBBY_PATH)/include

# ========== 自动查找 fishhook 静态库 ==========
FISHHOOK_LIB = $(shell find $(FISHHOOK_PATH) -name "libfishhook.a" | head -1)
ifeq ($(FISHHOOK_LIB),)
  $(warning [WARN] fishhook static library not found in $(FISHHOOK_PATH))
else
  AliSecBypass_v4_LDFLAGS += $(FISHHOOK_LIB)
  $(info [INFO] Using fishhook library: $(FISHHOOK_LIB))
endif

# ========== 自动查找 Dobby 静态库 ==========
DOBBY_LIB = $(shell find $(DOBBY_PATH) -name "libdobby.a" | head -1)
ifeq ($(DOBBY_LIB),)
  $(warning [WARN] Dobby static library not found in $(DOBBY_PATH))
else
  AliSecBypass_v4_LDFLAGS += $(DOBBY_LIB)
  $(info [INFO] Using Dobby library: $(DOBBY_LIB))
endif

# ========== 链接标志 ==========
AliSecBypass_v4_LDFLAGS += -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/library.mk
