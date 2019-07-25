#ifndef FIRMWARE_UPDATE_STREAM_H
#define FIRMWARE_UPDATE_STREAM_H

#include <SmingCore.h>
#include "WriteStream.h"
#include <sodium/crypto_sign.h>
#include <rboot-api.h>

class FirmwareUpdateStream: public WriteStream
{
    uint32_t flashSize_;
    enum {
        State_Error,
        State_Header,
        State_ImageHeader,
        State_SkipRom,
        State_FlashRom,
        State_Checksum,
        State_Complete
    } state_ = State_Header;
    
    size_t remainingBytes_ = 0;
    uint8_t *destinationPtr_ = nullptr;
    uint8_t romIndex_ = 0xFF;
    String error_;
    
    struct {
        uint32_t magic;
        uint32_t count;
    } header_;
    struct {
        uint32_t flashAddress;
        uint32_t size;
    } imageHeader_;
    
    rboot_config config_;
    rboot_write_status writeStatus_;
    
    struct {
        uint8_t signature[crypto_sign_BYTES];
    } checksum_;
    
    crypto_sign_state verifierState_;
    const uint8_t *verificationKey_;
    
    bool consume(const uint8_t *&buffer, size_t &size);
    void nextImage();   
    bool slotFits(uint8_t slot) const;
    size_t findSlot() const;
    
    void setError(const char *message = nullptr);
    
public:
    FirmwareUpdateStream(const uint8_t *verificationKey);
    
    size_t write(const uint8_t* buffer, size_t size) override;
    
    bool completed() const
    {
        return (state_ == State_Complete) || (state_ == State_Error);
    }
    bool ok() const 
    {
        return (state_ != State_Error);
    }
    const String& errorMessage() const 
    {
        return error_;
    }
};

#endif // FIRMWARE_UPDATE_STREAM_H
