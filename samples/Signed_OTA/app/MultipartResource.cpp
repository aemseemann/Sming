#include "MultipartResource.h"

int MultipartResource::checkHeaders(HttpServerConnection& connection, HttpRequest& request, HttpResponse& response)
{
    // parse content-type header
    String ct = request.headers["Content-Type"]; // for some reason HTTP_HEADER_CONTENT_TYPE does not work...
    if (!ct.startsWith("multipart/")) {
        response.code = HTTP_STATUS_BAD_REQUEST;
        return -1;
    }
    ct = ct.substring(10); // trim "multipart/"
    int semi = ct.indexOf(';');
    if (semi < 0) {
        response.code = HTTP_STATUS_BAD_REQUEST;
        return -1;
    }
    String subtype = ct.substring(0, semi);
    subtype.trim();
    ct = ct.substring(semi + 1);
    ct.trim();
    // make sure there is just one parameter
    if (ct.indexOf(';') >= 0) {
        response.code = HTTP_STATUS_BAD_REQUEST;
        return -1;
    }
    if (!ct.startsWith("boundary=")) {
        response.code = HTTP_STATUS_BAD_REQUEST;
        return -1;
    }
    String delimiter = ct.substring(9);
    delimiter.trim();
    if (!delimiter) { // delimiter may not be empty!
        response.code = HTTP_STATUS_BAD_REQUEST;
        return -1;
    }
    // delimiter may be enclosed in double quotes ('"')
    if (delimiter[0] == '"') {
        if ((delimiter.length() < 2) || (delimiter[delimiter.length() - 1] != '"')) {
            response.code = HTTP_STATUS_BAD_REQUEST;
            return -1;
        }
        delimiter = delimiter.substring(1, delimiter.length() - 1);
    }
    
    // call implementation to decide what to do with this request
    MultipartRequest *req = onMultipartHeadersComplete(subtype, request, response);
    if (!req) {
        // set response code if not done by callback
        if (response.code < 400) {
            response.code = HTTP_STATUS_INTERNAL_SERVER_ERROR;
        }
        return -1;
    }
    
    if (request.args != nullptr) {
        delete reinterpret_cast<MultipartRequest *>(request.args);
    }
    request.args = req;
    req->setup(response, delimiter);
    
    return 0;
}

int MultipartResource::processBody(HttpServerConnection& connection, HttpRequest& request, const char* at, int length) 
{
    MultipartRequest *req = reinterpret_cast<MultipartRequest *>(request.args);
    if (req == nullptr) return -1;
    return req->parseChunk(at, length) ? 0 : -1;
}

void MultipartRequest::setup(HttpResponse& response, const String& delimiter)
{
    ok_ = true;
    response_ = &response;

    delimParser_.delimiter = "\r\n--" + delimiter.substring(0, 70); // make sure the delimiter does not exceed 70 chars

    delimParser_.state = DelimParser::Scan;
    delimParser_.bufferSize = 0;
    delimParser_.charsFound = 2; // skip trailing CRLF

    partParser_.state = PartParser::Preamble;
}


bool MultipartRequest::parseChunk(const char* at, int length) 
{
    if (!ok_) return false;

    // The parser operates on the concatenation of delimParser_.buffer and the provided chunk, where
    // negative position indexes point into the buffer (-1 is last pos, -2 is penultimate pos, etc.) and nonnegatie indexes point into the chunk
    // At the end of the function, a potential delimiter part from the chunk is copied into the buffer for the next invocation
    auto &p = delimParser_;
    
    const char *const pBuf = p.buffer + p.bufferSize; // pointer to end of buffer, such that indexing with negative values >= startPos will retrieve valid elements

    int startPos = -p.bufferSize;
    int pos = startPos;
    int delimStart = startPos;

    while (pos < length) {
        const char ch = (pos < 0) ? pBuf[pos] : at[pos];
        ++pos;
        switch(p.state) {
        case DelimParser::Scan:
            if (ch == p.delimiter[p.charsFound]) {
                if ((++p.charsFound) == p.delimiter.length()) {
                    p.state = DelimParser::Complete; 
                    // delimiter prefix found - forward everything up to the delimiter to the 2nd level parser
                    if (startPos < delimStart) {
                        int amount = delimStart - startPos;
                        if (startPos < 0) {
                            int amountBuf = std::min(delimStart, 0) - startPos;
                            ok_ = parsePartChunk(pBuf + startPos, amountBuf);
                            startPos += amountBuf;
                            amount -= amountBuf;
                        }
                        if (ok_ && (amount > 0)) {
                            assert(startPos >= 0);
                            assert(startPos + amount == delimStart);
                            ok_ = parsePartChunk(at + startPos, amount);
                        }
                        startPos = delimStart;
                    }
                }
            } else {
                if ((ch == '\n') && (p.charsFound == 0)) {
                    // accept LF (instead of CR+LF) by exception
                    p.charsFound = 1;
                    --pos;
                } else {
                    // restart delimiter parsing at the next char in the buffer
                    p.charsFound = 0;
                    ++delimStart;
                    pos = delimStart;
                }
            }
            break;
        case DelimParser::Complete:
            if (ch == '-') {
                p.state = DelimParser::Dash;
                break;
            }
            // [[fall-through]];
        case DelimParser::Space:
        case DelimParser::DashDash:
            switch(ch) {
            case ' ':
            case '\t':
                p.state = (p.state == DelimParser::Complete) ? DelimParser::Space : p.state;
                break; // stay in state
            case '\n': // accept single LF as well as CR+LF
            case '\r':
                p.state = (p.state == DelimParser::DashDash) ? DelimParser::DashDashCr : DelimParser::Cr;
                if (ch == '\n') --pos; // repeat
                break;
            default:
                ok_ = false;
            }
            break;
        case DelimParser::Dash:
            // got prefix + single dash ('-'): expect another dash
            if (ch == '-') {
                p.state = DelimParser::DashDash;
            } else {
                ok_ = false;
            }
            break;
        case DelimParser::Cr:
        case DelimParser::DashDashCr:
            if (ch == '\n') {
                // delimiter complete
                ok_ = handleDelimiter(/* last = */ p.state == DelimParser::DashDashCr);
                p.state = DelimParser::Scan;
                p.charsFound = 0;
                startPos = delimStart = pos;
            } else {
                ok_ = false;
            }
            break;
        default: // should not happen
            ok_ = false;
        }
        
        // exit on parser error
        if (!ok_) {
            return false;
        }
    }
    
    // parsing of chunk finished - forward everything up to an incomplete delimiter prefix to the 2nd level parser
    if (startPos < delimStart) {
        int amount = delimStart - startPos;
        if (startPos < 0) {
            int amountBuf = std::min(delimStart, 0) - startPos;
            ok_ = parsePartChunk(pBuf + startPos, amountBuf);
            if (!ok_) return false;
            startPos += amountBuf;
            amount -= amountBuf;
        }
        if (amount > 0) {
            assert(startPos >= 0);
            ok_ = parsePartChunk(at + startPos, amount);
            if (!ok_) return false;
        }
    }
    
    // copy an unfinished prefix to the beginning of p.buffer
    p.bufferSize = pos - delimStart;
    if (p.bufferSize > 0) {
        char *pDest = p.buffer;
        if (delimStart < 0) {
            pDest = std::copy_n(pBuf + delimStart, -delimStart, pDest);
            delimStart = 0;
        }
        std::copy_n(at + delimStart, pos - delimStart, pDest);
    }

    return true;
}

bool MultipartRequest::handleDelimiter(bool last)
{
    assert(ok_);
    auto &p = partParser_;
    switch(p.state) {
    case PartParser::Preamble:
        if (last) {
            p.state = PartParser::Epilogue;
        } else {
            nextPart();
        }
        break;
    case PartParser::Body:
        ok_ = onPartComplete(*response_);
        if (ok_) {
            if (last) {
                p.state = PartParser::Epilogue;
            } else {
                nextPart();
            }
        }
        break;
    case PartParser::Headers: // delimiter may not occur inside part header
    case PartParser::Epilogue: // no delimiters should follow the last one
    default:
        ok_ = false;
    }
    
    return ok_;
}

void MultipartRequest::nextPart() 
{
    auto &p = partParser_;
    p.state = PartParser::Headers;
    p.headers.clear();
    p.headerState = PartParser::HeaderStart;
}

bool MultipartRequest::parsePartChunk(const char* at, int length)
{
    assert(ok_);
    auto &p = partParser_;
    switch(p.state) {
    case PartParser::Preamble:
        onPreamble(at, length, *response_);
        break;
    case PartParser::Epilogue:
        onEpilogue(at, length, *response_);
        break;
    case PartParser::Headers:
        ok_ = parsePartHeaders(at, length);
        break;
    case PartParser::Body:
        ok_ = onPartBody(at, length, *response_);
        break;
    default:
        ok_ = false;
    }
    return ok_;
}

bool MultipartRequest::parsePartHeaders(const char *at, int length) 
{
    auto &p = partParser_;    
    assert(ok_ && (p.state == PartParser::Headers));

    int pos = 0;
    int startPos = pos;
    while((pos < length) && (p.state == PartParser::Headers)) {
        const char ch = at[pos];
        ++pos;
        switch(p.headerState) {
        case PartParser::HeaderStart:
            if ((ch == '\r') || (ch == '\n')) {
                p.headerState = PartParser::HeaderBlankCr;
                if (ch == '\n') --pos; // repeat
                break;
            }
            // begin new header field
            p.headerState = PartParser::HeaderField;
            p.headerField.setLength(0);
            startPos = pos - 1; // pos was already incremented
            // [[fallthrough]];
        case PartParser::HeaderField:
            switch(ch) {
            case ':':
                p.headerField.concat(at + startPos, pos - startPos - 1);
                p.headerField.trim();
                ok_ = !!p.headerField;
                startPos = pos;
                p.headerState = PartParser::HeaderValue;
                break;
            case '\r':
            case '\n':
                ok_ = false; // line breaks not allowed in header field
                break;
            }
            break;
        case PartParser::HeaderValue:
            if (ch == '\r' || ch == '\n') {
                p.headers[p.headerField].concat(at + startPos, pos - startPos - 1);
                p.headers[p.headerField].trim();
                p.headerState = PartParser::HeaderCr;
                if (ch == '\n') --pos; // repeat
            }
            break;
        case PartParser::HeaderCr:
        case PartParser::HeaderBlankCr:
            if (ch == '\n') {
                if (p.headerState == PartParser::HeaderBlankCr) {
                    // headers complete
                    p.state = PartParser::Body;
                    // TBD: transparently decode BASE64-encoded bodies (Content-Transfer-Encoding)
                    ok_ = onPartHeadersComplete(p.headers, *response_);
                } else {
                    p.headerState = PartParser::HeaderStart;
                }
            } else {
                ok_ = false;
            }
            break;
        default:
            ok_ = false;
        }
        if (!ok_) return false;
    }
    
    if (p.state == PartParser::Headers) {
        assert(pos == length);
        // append remaining chunk to either field or value
        switch(p.headerState) {
        case PartParser::HeaderField:
            p.headerField.concat(at + startPos, pos - startPos);
            break;
        case PartParser::HeaderValue:
            p.headers[p.headerField].concat(at + pos, pos - startPos);
            break;
        default: break;
        }
    } else if (p.state == PartParser::Body) {
        ok_ = onPartBody(at + pos, length - pos, *response_);
    }

    return ok_;
}

bool MultipartRequest::onComplete(HttpResponse& response)
{
    if (!ok_) return false;

    if (partParser_.state != PartParser::Epilogue) {
        ok_ = false;
        response.code = HTTP_STATUS_BAD_REQUEST;
        
        if (partParser_.state == PartParser::Body) {
            // inform part parser that it can stop now
            onPartComplete(response);
            // return value is most likely false, but doesn't matter, since we already know that the request failed
        }
    }
    
    return ok_;
}

int MultipartResource::handleRequestComplete(HttpServerConnection& connection, HttpRequest& request, HttpResponse& response)
{
    MultipartRequest *req = reinterpret_cast<MultipartRequest *>(request.args);
    if (req) {
        if (!req->onComplete(response)) {
            if (response.code < 400) {
                response.code = HTTP_STATUS_BAD_REQUEST;
            }
        }
        delete req;
        request.args = nullptr;
    }
    return 0;
}

