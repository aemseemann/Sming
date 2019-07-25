#ifndef FORMDATA_REQUEST_H
#define FORMDATA_REQUEST_H

#include "MultipartResource.h"
#include "WriteStream.h"

class FormDataRequest: public MultipartRequest
{
public:
    FormDataRequest(const HttpRequest &request) { }

protected:
    virtual bool onField(const String& name, const String& value, HttpResponse& response) 
    {
        // accept everything
        return true;
    }

    /* In order to process file uploads, the implementation has to provide a pointer to a stream
     * No ownership is transferred by returning the pointer. The request implementation is responsible for
     * managing the lifetime of the stream. It must stay available until the next onPartComplete callback.
     */
    // default implementation does not accept any file uploads
    virtual WriteStream *onFile(const String& name, const String& filename, HttpResponse& response) 
    {
        response.code = HTTP_STATUS_NOT_ACCEPTABLE;
        return nullptr;
    }
    
    bool onPartHeadersComplete(const HttpHeaders &headers, HttpResponse &response) override;
    bool onPartBody(const char *at, int length, HttpResponse &response) override;
    bool onPartComplete(HttpResponse &response) override;
    
private:
    String currentField_;
    String currentValue_;
    bool partIsField_ = false;
    WriteStream *fileStream_ = nullptr;
};

template <typename RequestType>
class FormDataResource: public MultipartResource
{
public:
    FormDataResource() 
    { }

protected:    
    MultipartRequest* onMultipartHeadersComplete(const String& subtype, const HttpRequest &request, HttpResponse &response) override
    {
        if (subtype != "form-data") {
            response.code = HTTP_STATUS_NOT_ACCEPTABLE;
            return nullptr;
        }
        return new RequestType(request);
    }
};


#endif // FORMDATA_REQUEST_H
