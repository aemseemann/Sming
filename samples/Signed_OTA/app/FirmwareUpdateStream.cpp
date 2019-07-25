#include "FirmwareUpdateStream.h"

static size_t getFlashSize() 
{
    union {
        uint32_t u;
        uint8_t bytes[4];
    } data;
    spi_flash_read(0x0000, &data.u, sizeof(data));
    switch((data.bytes[3] & 0xF0) >> 4) {
    case 0x0: // 4 Mbit (512KB)
        return 512 * 1024;
    case 0x1: // 2 MBit (256KB)
        return 256 * 1024;
    case 0x2: // 8 MBit (1MB)
        return 1024 * 1024;
    case 0x3: // 16 MBit (2MB)
        return 2048 * 1024;
    case 0x4: // 32 MBit (4MB)
        return 4 * 1024 * 1024;
    case 0x8: // 64 MBit (8MB)
        return 8 * 1024 * 1024;
    case 0x9: // 128 MBit (16MB)
        return 16 * 1024 * 1024;
    default:
        return 0;
    }
} 

FirmwareUpdateStream::FirmwareUpdateStream(const uint8_t *verificationKey)
    : verificationKey_(verificationKey)
{ 
    crypto_sign_init(&verifierState_);
    
    config_ = rboot_get_config();
    flashSize_ = getFlashSize();
    // begin reading header
    remainingBytes_ = sizeof(header_);
    destinationPtr_ = reinterpret_cast<uint8_t *>(&header_);
}


size_t FirmwareUpdateStream::write(const uint8_t* buffer, size_t size)
{
    size_t available = size;
    
    while((state_ != State_Error) && (available > 0)) {
        switch(state_) {
        case State_Header:
            if (consume(buffer, available)) {
                if (header_.magic == 0xf01af02a) {
                    Serial.printf("Starting firmware update, receive %u image(s)\n", header_.count);
                    nextImage();
                } else {
                    setError("Invalid/Unrecognized update image format");
                }
            }
            break;
        case State_ImageHeader:
            if (consume(buffer, available)) {
                bool use = false;
                if (romIndex_ >= config_.count) {
                    // no ROM flashed yet
                    romIndex_ = findSlot();
                    use = (romIndex_ < config_.count);
                }
                remainingBytes_ = imageHeader_.size;
                if (use) {
                    Serial.printf("=> Updating slot %u (0x%08X..0x%08X)\n", romIndex_, config_.roms[romIndex_], config_.roms[romIndex_] + imageHeader_.size);
                    state_ = State_FlashRom;
                    writeStatus_ = rboot_write_init(config_.roms[romIndex_]);
                } else {
                    Serial.printf("=> Ignoring image for 0x%08X..0x%08X)\n", imageHeader_.flashAddress, imageHeader_.flashAddress + imageHeader_.size);
                    state_ = State_SkipRom;
                }
            }
            break;
        case State_FlashRom:
            {
                bool ok = rboot_write_flash(&writeStatus_, buffer, std::min(remainingBytes_, available));
                if (ok) {
                    if (consume(buffer, available)) {
                        ok = rboot_write_end(&writeStatus_);
                        nextImage();
                    }
                }
                if (!ok) {
                    setError("Error while writing Flash memory");
                }
            }
            break;
        case State_SkipRom:
            if (consume(buffer, available)) {
                nextImage();
            }
            break;
        case State_Checksum:
            if (consume(buffer, available)) {
                state_ = State_Complete;
                const bool signatureMatch = (crypto_sign_final_verify(&verifierState_, checksum_.signature, verificationKey_) == 0);
                if (signatureMatch) {
                    Serial.printf("Signature verified\n");
                    if (romIndex_ < config_.count) {
                        if (rboot_set_current_rom(romIndex_)) {
                            Serial.printf("Image activated\n");
                            state_ = State_Complete;
                        } else {
                            setError("Could not activate updated ROM");
                        }
                    } else {
                        setError("No suitable ROM slot found");
                    }
                } else {
                    setError("Signature verification failed");
                    
                    if (romIndex_ < config_.count){                            
                        // destroy header of updated slot to prevent accidental booting of unverified image
                        spi_flash_erase_sector(config_.roms[romIndex_] / SECTOR_SIZE);
                    }
                }
            }
            break;
            
        case State_Complete:
            // ignore whatever is arriving after the checksum
            available = 0;
            break;
            
        case State_Error:
        default:
            setError("Internal error");
            break;                
        }
    }
    
    return size;
}

bool FirmwareUpdateStream::consume(const uint8_t *&buffer, size_t &size) 
{
    size_t chunkSize = std::min(size, remainingBytes_);
    if (state_ != State_Checksum) {
        crypto_sign_update(&verifierState_, static_cast<const unsigned char *>(buffer), chunkSize);
    }
    if (destinationPtr_ != nullptr) {
        memcpy(destinationPtr_, buffer, chunkSize);
        destinationPtr_ += chunkSize;
    }
    remainingBytes_ -= chunkSize;
    buffer += chunkSize;
    size -= chunkSize;        
    if (remainingBytes_ == 0) {
        destinationPtr_ = nullptr;
        return true;
    } else {
        return false;
    }
}
    
void FirmwareUpdateStream::nextImage() 
{
    const bool hasMoreImages = header_.count > 0;
    if (hasMoreImages) {
        state_ = State_ImageHeader;
        destinationPtr_ = reinterpret_cast<uint8_t *>(&imageHeader_);
        remainingBytes_ = sizeof(imageHeader_);
        --header_.count;
    } else {
        state_ = State_Checksum;
        destinationPtr_ = reinterpret_cast<uint8_t *>(&checksum_);
        remainingBytes_ = sizeof(checksum_);
    }
}

bool FirmwareUpdateStream::slotFits(uint8_t slot) const 
{
    if (slot < config_.count) {
        size_t maxSize = (flashSize_ - 7 * SPI_FLASH_SEC_SIZE);
        maxSize -= std::min(maxSize, imageHeader_.flashAddress);
        if (imageHeader_.size < maxSize) {
            const size_t end = imageHeader_.flashAddress + imageHeader_.size;
            // test if rom does not exceed its maximum size
            
            bool fits = true;
            for (size_t other = 0; fits && (other < config_.count); ++other) {
                if ((slot != other) && (imageHeader_.flashAddress < config_.roms[other])) {
                    fits = (end <= config_.roms[other]);
                }
            }
            if (fits) {
#ifdef RBOOT_SPIFFS_0
                fits = (imageHeader_.flashAddress > RBOOT_SPIFFS_0) || (end <= RBOOT_SPIFFS_0);
#elif defined(RBOOT_SPIFFS_1)
                fits = (imageHeader_.flashAddress > RBOOT_SPIFFS_1) || (end <= RBOOT_SPIFFS_1);
#endif
            }
            if (fits) {
                return true;
            }
        }
    }
    return false;
}
    
size_t FirmwareUpdateStream::findSlot() const 
{
    size_t slotIndex = config_.current_rom;
    for (size_t i = 0; i < config_.count; ++i) {
        if ((config_.roms[slotIndex] % SECTOR_SIZE) != 0){
             continue; // ROM slots are expected to be sector aligned
        }
        // mask both addresses by 1MB, since each 1MB of flash is mapped to the same 1MB address range
        if ((imageHeader_.flashAddress & 0x000FFFFF) == (config_.roms[slotIndex] & 0x00FFFFF)) {
            
            // protect current slot and GPIO slot (if used)
            if ((slotIndex != config_.current_rom) && (config_.mode != MODE_GPIO_ROM || (slotIndex != config_.gpio_rom))) {
                if (slotFits(slotIndex)) {
                    return slotIndex; 
                }
            }
        }
        if (++slotIndex >= config_.count) {
            slotIndex = 0;
        }
    }
    return 0xFF;
}
    
void FirmwareUpdateStream::setError(const char *message) 
{
    Serial.printf("Error: %s\n", message ? message : "");
    state_ = State_Error;
    error_ = message;
}
