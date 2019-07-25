#ifndef WRITE_STREAM_H
#define WRITE_STREAM_H

#include <Data/Stream/ReadWriteStream.h>

// TODO: move to Data/Stream/WriteStream.h

class WriteStream: public ReadWriteStream 
{
public:
    uint16_t readMemoryBlock(char* data, int bufSize) override
    {
        return 0;
    }

    bool seek(int len) override
    {
        return false;
    }

    bool isFinished() override
    {
        return true;
    }    
};

#endif // WRITE_STREAM_H
