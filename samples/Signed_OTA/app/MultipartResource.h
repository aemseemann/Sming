#ifndef MULTIPART_RESSOURCE_H
#define MULTIPART_RESSOURCE_H

#include <SmingCore.h>

class MultipartResource;

/**
 * @brief Base class for multipart/* request handlers
 * 
 * This is the abstract base class for handlers/parsers of requests with Content-Type 'multipart/*'.
 * Implementations must override the [pure] virtual methods to parse and process the headers and bodies of individual part of the request.
 */
class MultipartRequest 
{
    friend class MultipartResource;
public:
    virtual ~MultipartRequest() 
    {
    }

protected:
    // TODO: Remove the 'response' parameter from all those callbacks and make it accessible via a member function instead
    
    // prologue and epilogue are typically irrelevant. Hooks are provided for completeness
    virtual void onPreamble(const char *at, int length, HttpResponse& response) { }
    virtual void onEpilogue(const char *at, int length, HttpResponse& response) { }
    
    // Invoked when message is completely parsed. 
    // It depends on a particular implementation, if this callback is needed or if all work can be handled in onPartComplete
    virtual bool onComplete(HttpResponse& response);
    
    /** 
     * @brief This callback is invoked at the beginning of each part after the headers have been successfully parsed.
     * @return \c true to continue parsing. \c false if the header contains unacceptable data. The implementation should set the response code to an appropriate value in this case.
     */
    virtual bool onPartHeadersComplete(const HttpHeaders &headers, HttpResponse &response) = 0;
    /**
     * @brief This callback is invoked repeatedly for the body of each part. Each invocation provides one chunk of data to be parsed/processed.
     * @return \c true to continue parsing or \c false to stop parsing due to an unacceptable error. The implementation should set the response code to an appropriate value in this case.
     */
    virtual bool onPartBody(const char *at, int length, HttpResponse &response) = 0;
    /**
     * @brief This callback is invoked upon completion of a part. 
     * @return \c true to continue parsing or \c false to stop parsing due to an unacceptable error condition. The implementation should set the response code to an appropriate value in this case.
     */
    virtual bool onPartComplete(HttpResponse &response) = 0;
    
private:
    // callbacks for Resource
    void setup(HttpResponse& response, const String& delimiter); // invoked before first parseChunk call to setup the parser
    bool parseChunk(const char* at, int length); // invoked from processBody
    bool handleRequestComplete();

    bool ok_ = false;
    HttpResponse *response_ = nullptr;    

    /* 1st level parser: Detect delimiters
     * At this level, the parser detects delimiters only.
     * Non-delimiter data is forwarded to the 2nd level parser, which is also informed about every delimiter.
     */
    struct DelimParser {
         enum {
             Scan, // More delimiter characters expected
             Complete, // Delimiter string found: Expect '-', space or CR
             Dash, // Delimiter string + '-' found: Expect second '-'
             DashDash, // delimtier string + '--' + optional space found: expect space or CR
             Space, // Delimiter string + an arbitrary number of spaces found: Expect more space or CR
             Cr, // Delimiter string + optional space + CR found: expect LF
             DashDashCr, // Delimiter string + '--' + optional space + CR found: expect LF
         } state;
         String delimiter; // delimiter string, including prefix, i. e. '\r\n--' + delimiter from HTTP header, whose maximum size is 70 chars.
         char buffer[73]; // If a delimiter line spans across multiple chunks, the incomlete part must be buffered at the end of the current chunk,
                      // because the decision if it is part of a delimiter or just regular data has to be deferred to a subsequent chunk.
                      // The size of this buffer is one char less than the maximum size of the delimiter string, which is at most 74 chars.
        int bufferSize; // number of bytes currently occupied in \c buffer
        int charsFound; // number of chars from delimiter that have been found already, i. e. delimiter[charsFound] is compared next
    } delimParser_;
    
    /* 2nd level parser: Part headers + body
     * This parser level is responsible for parsing and collecting HTTP headers for each part and invoking the onPart... callbacks.
     * It also invokes the Preamble and Epilogue callbacks.
     */
    struct PartParser {
        enum {
            Preamble,
            Headers,
            Body,
            Epilogue
        } state;
        HttpHeaders headers;
        enum {
            HeaderStart,
            HeaderField,
            HeaderValue,
            HeaderCr,
            HeaderBlankCr
        } headerState;
        String headerField;
    } partParser_;

    bool handleDelimiter(bool last = false);
    bool parsePartChunk(const char* at, int length);    
    bool parsePartHeaders(const char *at, int length);
    void nextPart();
};

/**
 *  @brief Base class for HTTP server resources processing multipart/* requests
 */
class MultipartResource: public HttpResource
{
public:
    MultipartResource()
    {
        onHeadersComplete = HttpResourceDelegate(&MultipartResource::checkHeaders, this);
        onBody = HttpServerConnectionBodyDelegate(&MultipartResource::processBody, this);
        onRequestComplete = HttpResourceDelegate(&MultipartResource::handleRequestComplete, this);
    }
protected:
    /**
     * @brief Callback after request headers have been completely processed. 
     * 
     * Implementations should create an appropriate MultiPartRequest instance based on the subtype to continue processing the request.
     * The callee takes ownership of the returned instance and deletes it upon completion of the request. (TODO: use unique_ptr<MultipartRequest> or decide for different memory allocation model!)
     * If the subtype does not match expectations, a \c nullptr must be returned. In this case, the implementation should also set the 
     * response code to a meaningful value. If this is not done, a 500 (internal server error) response will be sent. If this response is appropriate
     * (e. g. in case of an allocation failure) the implementation does not have to do anything.
     */
    virtual MultipartRequest* onMultipartHeadersComplete(const String& subtype, const HttpRequest &request, HttpResponse &response) = 0;

private:
    int processBody(HttpServerConnection& connection, HttpRequest&, const char* at, int length);
    int checkHeaders(HttpServerConnection& connection, HttpRequest& request, HttpResponse& response);    
    int handleRequestComplete(HttpServerConnection& connection, HttpRequest& request, HttpResponse& response);
};

#endif 
