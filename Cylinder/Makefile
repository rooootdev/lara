THEOS_DEVICE_IP = 192.168.1.253

FINALPACKAGE = 1

TARGET := iphone:clang:latest:14.0

export ADDITIONAL_CFLAGS = -DTHEOS_LEAN_AND_MEAN -fobjc-arc

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Cylinder
Cylinder_FILES = $(wildcard tweak/*.swift) tweak/tweak.x tweak/CALayer+Cylinder.m
Cylinder_SWIFT_BRIDGING_HEADER = tweak/Cylinder-Bridging-Header.h

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
SUBPROJECTS += settings
include $(THEOS_MAKE_PATH)/aggregate.mk
