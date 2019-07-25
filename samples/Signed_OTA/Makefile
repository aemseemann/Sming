#####################################################################
#### Please don't change this file. Use component.mk instead ####
#####################################################################

-include env.mk

SMING_HOME = $(abspath ../../Sming)
SMING_ARCH = Esp8266
# Image will not fit into slot if build without -Os
SMING_RELEASE = 1

include $(SMING_HOME)/project.mk

# Linker script generation for ROM1
# TODO: move this logic into rboot component
RBOOT_LD_1 := $(abspath out/rboot-rom1.ld)
$(RBOOT_LD_1): $(ARCH_BASE)/Compiler/ld/$(RBOOT_LD_0)
	@echo Generating linker script for ROM1
	$(Q) sed -r "s/(^\s*irom0_0_seg *: *).*/\\1org = $$((0x40200010 + $(RBOOT_ROM1_ADDR))), len = \(1M - $(RBOOT_ROM1_ADDR)\)/" $< > $@
# setup linker script dependency for ROM1
$(TARGET_OUT_1): $(RBOOT_LD_1)

# always update SPIFFS
.PHONY: $(SPIFF_BIN_OUT)

