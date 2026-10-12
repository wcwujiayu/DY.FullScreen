# DY.FullScreen - Theos/Logos tweak, following the DYYY multi-scheme build flow
-include Makefile.local

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

SCHEME ?= rootless
ifeq ($(SCHEME),roothide)
    export THEOS_PACKAGE_SCHEME = roothide
    export FINALPACKAGE = 1
else ifeq ($(SCHEME),rootful)
    unexport THEOS_PACKAGE_SCHEME
else ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
    export FINALPACKAGE = 1
else
    $(error Unknown SCHEME=$(SCHEME); use rootless, rootful, or roothide)
endif

ifeq ($(GITHUB_ACTIONS),true)
    export INSTALL = 0
    export FINALPACKAGE = 1
endif

export DEBUG = 0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DY.FullScreen
DY.FullScreen_FILES = src/Tweak.m src/DYFSCommon.m src/DYFSContext.m src/DYFSLayout.m src/DYFSChrome.m src/DYFSSettings.m src/DYLiveFeedFullscreen.m
DY.FullScreen_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
DY.FullScreen_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	@rm -rf .theos packages build
