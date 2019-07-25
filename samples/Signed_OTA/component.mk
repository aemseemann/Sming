## Application Component configuration
## Parameters configured here will override default and ENV values
## Uncomment and change examples:

## Add your source directories here separated by space
COMPONENT_SRCDIRS += app

# COMPONENT_SRCFILES :=
# COMPONENT_INCDIRS :=

## If you require any Arduino Libraries list them here
# ARDUINO_LIBRARIES :=

## List the names of any additional Components required for this project
COMPONENT_DEPENDS := libsodium

## Set paths for any GIT submodules your application uses
# COMPONENT_SUBMODULES :=

## Append any targets to be built as dependencies of the project, such as generation of additional binary files
# CUSTOM_TARGETS += 

## Additional object files to be included with the application library
# EXTRA_OBJ :=

## Additional libraries to be linked into the project
# EXTRA_LIBS :=

## Update any additional compiler flags

# CFLAGS +=

# CXXFLAGS +=

## Configure flash parameters (for ESP12-E and other new boards):
# SPI_MODE = dio
SPI_SIZE = 1M

## SPIFFS options
DISABLE_SPIFFS = 0
SPIFF_FILES = files

# use lwip_open
ENABLE_CUSTOM_LWIP = 1
#ENABLE_SSL = 1
# espconn_... functions needed for mDns
ENABLE_ESPCONN = 1

# RBOOT configuration 
# The sample assumes a 1MB flash chip, partitioned with 2 application slots of approx. 450kB
# and the remaining space allocated to a small SPIFFS
RBOOT_ENABLED = 1
RBOOT_BIG_FLASH = 0
RBOOT_TWO_ROMS = 1
# RBOOT_ROM0_ADDR = 0x2000
RBOOT_ROM1_ADDR = 0x70000
RBOOT_SPIFFS_0 = 0xE0000
SPIFF_SIZE = 110592

## COM port parameter is reqruied to flash firmware correctly.
COM_PORT = /dev/ttyUSB0
COM_SPEED = 115200
COM_SPEED_ESPTOOL=1000000

# use internal SDK (SDK_BASE has to point somewhere into SMING_HOME)
SDK_BASE = $(SMING_HOME)

BOARD_URL = esp8266.local

# Reboot via HTTP request
OTAGEN_SCRIPT = $(COMPONENT_PATH)/otagen.py
OTA_GEN := $(PYTHON2) $(OTAGEN_SCRIPT)
OTA_SIGNING_KEY := $(COMPONENT_PATH)/signing.key
OTA_VERIFICATION_HEADER := $(COMPONENT_PATH)/app/ota_verification_key.h

$(OTA_SIGNING_KEY):
	@echo "#########################################################"
	@echo "# Generating new signing key for OTA images             #"
	@echo "#                                                       #"
	@echo "# If this is not what you want, replace the generated   #"
	@echo "# key without your own (e. g. from a previous project)  #"
	@echo "# and run 'make' again.                                 #"
	@echo "#########################################################"
	$(Q) $(OTA_GEN) --genkey --keyfile=$@

.PHONY: generate_ota_signing_key
generate_ota_signing_key: 
	@echo Generate a new OTA signing key on explicit request.
	$(Q) $(OTA_GEN) --genkey --keyfile=$(OTA_SIGNING_KEY)

$(OTA_VERIFICATION_HEADER): $(OTA_SIGNING_KEY) $(OTAGEN_SCRIPT)
	$(Q) $(OTA_GEN) --keyfile=$< --pubkey-header=$@

# add dependency to trigger automatic generation of verification key header
$(COMPONENT_PATH)/app/application.cpp: $(OTA_VERIFICATION_HEADER)

OTA_FILE := firmware.ota
$(OTA_FILE): $(RBOOT_ROM_0_BIN) $(RBOOT_ROM_1_BIN) $(OTA_SIGNING_KEY)
	@echo Generating OTA firmware update file...
	$(Q) $(OTA_GEN) --keyfile=$(OTA_SIGNING_KEY) --out "$(OTA_FILE)" "$(ROM_0_ADDR)=$(RBOOT_ROM_0_BIN)" "$(RBOOT_ROM1_ADDR)=$(RBOOT_ROM_1_BIN)"

BOARD_URL = esp8266.local

.PHONY: otafile ota reboot

otafile: $(OTA_FILE)

ota: $(OTA_FILE) 
	@curl --fail -H 'Expect:' -F fwimage=@$(OTA_FILE) http://$(BOARD_URL)/fwupgrade > /dev/null && curl http://$(BOARD_URL)/reboot > /dev/null

reboot:
	@curl http://$(BOARD_URL)/reboot



