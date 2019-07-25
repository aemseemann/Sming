This example demonstrates Over-The-Air (OTA) firmware updates which are also secured by a cryptographic signature.

It was tested on an ESP01 board with 1MB of flash memory. (See component.mk for partitioning)

1. Setup your Wifi credentials (either via environment variables, in Makefile or #define them directly in application.cpp)

WIFI_SSID = ...
WIFI_PWD = ...

2. make otafile

To build the project and generate firmware.ota. This file combines images for both ROM slots.
At first run, a private 'signing.key' is generated. The corresponding public key is embedded into the firmware to allow signature verification.
For obvious reasons, the private key must be kept secret. 
The same private key can be shared between multiple projects to generate compatible OTA images.

3. Initial flashing via serial cable

Connect (USB-to-)serial cable and run 'make flash' to write rboot, the first rom image and the file system.
This must be done only once. (Unless you brick your device with a faulty firmware.)

4. Update via Browser

- Direct your browser to esp8266.local (or use the IP address assigned by your router)
- Select 'firmware.ota' and hit 'Go'
- After a few seconds, it should show a "Firmware Update Successful"
- (During the update process, some status messages are printed to the serial console, which might be helpful for troubleshooting)

5. Update via 'make ota'

This command uses curl to emulate the file upload. Also, after a successful update the device is automatically rebooted.

Limitations:
- The OTA mechanism currently has no support for updating the bootloader or the file system.
- (Unsecured) file system updates could be realized by adding FTP server functionality to the firmware.


