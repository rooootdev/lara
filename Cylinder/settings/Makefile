include $(THEOS)/makefiles/common.mk

export TARGET := iphone:clang:16.5:14.0

BUNDLE_NAME = CylinderSettings
CylinderSettings_FILES = CLAlignedTableViewCell.m CLDonateController.m CLEffect.m CLEffectsController.m CLFormulasController.m CLTwitterCell.m CylinderSettings.m
CylinderSettings_INSTALL_PATH = /Library/PreferenceBundles
CylinderSettings_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Cylinder.plist$(ECHO_END)