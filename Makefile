# AliSecBypass v4 - Theos Makefile
# 支持本地编译 + GitHub Actions 远程编译
# TrollStore / 非越狱注入

TARGET := iphone:clang:latest:15.0
ARCHS = arm64

# 自动检测 Theos 路径
THEOS ?= $(HOME)/theos
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AliSecBypass_v4

# ========== 主文件 ==========
AliSecBypass_v4_FILES = AliSecBypass_v4.mm

# ========== C/C++ 编译选项 ==========
AliSecBypass_v4_CFLAGS = -fobjc-arc -std=c++11
AliSecBypass_v4_CCFLAGS = -std=c++11

# ========== Dobby 路径 ==========
# 本地: DOBBY_PATH 环境变量或默认 ./dobby
DOBBY_PATH ?= $(PWD)/dobby

# 头文件
AliSecBypass_v4_CFLAGS += -I$(DOBBY_PATH)/include

# 静态库路径（自动查找）
DOBBY_LIB = $(shell find $(DOBBY_PATH) -name "libdobby.a" | head -1)

ifeq ($(DOBBY_LIB),)
  $(warning Dobby static library not found! Run: ./setup.sh)
  $(warning Or set DOBBY_PATH env variable)
else
  AliSecBypass_v4_LDFLAGS += $(DOBBY_LIB)
  $(info Using Dobby library: $(DOBBY_LIB))
endif

# ========== 其他链接选项 ==========
AliSecBypass_v4_LDFLAGS += -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk
