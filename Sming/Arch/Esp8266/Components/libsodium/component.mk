# umm_malloc (custom heap allocation)

COMPONENT_SUBMODULES	:= libsodium

CUSTOM_BUILD = 1

LIBSODIUM_ROOT = $(COMPONENT_PATH)/libsodium
CONFIGURE_LD_FLAGS = $(LDFLAGS) -L$(SDK_LIBDIR) -nostdlib -Wl,--start-group -lmain -lnet80211 -lwpa -llwip -lpp -lphy -lc -lcrypto -Wl,--end-group -lgcc -T$(SDK_BASE)/ld/eagle.app.v6.ld
CONFIGURE_CFLAGS = $(CFLAGS) -Wno-unused-function -Wno-unknown-pragmas -Wno-undef

LIBSODIUM_INSTALL := $(COMPONENT_BUILD_DIR)/install

COMPONENT_INCDIRS = $(LIBSODIUM_INSTALL)/include

$(COMPONENT_RULE)$(COMPONENT_LIBPATH):
	@echo Configuring libsodium...
	$(Q) $(LIBSODIUM_ROOT)/configure CFLAGS="$(CONFIGURE_CFLAGS)" LDFLAGS="$(CONFIGURE_LD_FLAGS)" --host=$(CONFIG_TOOLPREFIX:-=) --prefix=$(LIBSODIUM_INSTALL) --disable-shared --enable-static --disable-ssp --without-pthreads --disable-asm
	@echo Building libsodium...
	$(Q) $(MAKE) install
	$(Q) cp $(LIBSODIUM_INSTALL)/lib/libsodium.a $(COMPONENT_LIBPATH)
