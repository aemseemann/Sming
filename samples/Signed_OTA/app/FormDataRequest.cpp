#include "FormDataRequest.h"

static String unquote(const String &in) {
    int begin = 0;
    int end = in.length();
    if (end >= 2) {
        if (in[0] == '"') {
            ++begin;
            if (in[end - 1] == '"') --end;
        }
    }
    return in.substring(begin, end);
}

bool FormDataRequest::onPartHeadersComplete(const HttpHeaders &headers, HttpResponse &response)
{
    if (!headers.contains(HTTP_HEADER_CONTENT_DISPOSITION)) return false;

    // cannot use const String& because splitString lacks const qualifier :(
    String cd = headers[HTTP_HEADER_CONTENT_DISPOSITION];
    Vector<String> args;
    splitString(cd, ';', args);
    if(args.isEmpty()) return false;
    args[0].trim();
    if (args[0] != "form-data") return false;
    bool hasName = false;
    bool hasFilename = false;
    String filename;

    for (std::size_t i = 1; i < args.size(); ++i) {
        args[i].trim();
        if (!hasName) {
            if (args[i].startsWith("name=")) {
                currentField_ = unquote(args[i].substring(5));
                hasName = true;
            }
        }
        if (!hasFilename) {
            if (args[i].startsWith("filename=")) {
                filename = unquote(args[i].substring(9));
                hasFilename = true;
            }
        }
    }
    if (!hasName) return false;
    
    partIsField_ = (!hasFilename);
    if (partIsField_) {
        currentValue_.setLength(0);
    } else {
        fileStream_ = onFile(currentField_, filename, response);
    }

    return true;
}

bool FormDataRequest::onPartBody(const char *at, int length, HttpResponse &response) 
{
    if (partIsField_) {
        currentValue_.concat(at, length);
    } else if (fileStream_) {
        if (fileStream_->write(reinterpret_cast<const uint8_t *>(at), length) < length) {
            response.code = HTTP_STATUS_INTERNAL_SERVER_ERROR;
            return false;
        }
    }
    return true;
}

bool FormDataRequest::onPartComplete(HttpResponse &response) 
{
    if (partIsField_) {
        partIsField_ = false;
        return onField(currentField_, currentValue_, response);
    } else if (fileStream_) {
        fileStream_ = nullptr;
    }
    return true;
}
