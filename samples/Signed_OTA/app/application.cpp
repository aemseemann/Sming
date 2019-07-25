#include <SmingCore.h>
#include "FirmwareUpdateStream.h"
#include "FormDataRequest.h"
#include "ota_verification_key.h"

#define LED_PIN 2 // GPIO2
static HttpServer server;

static const char hostname[] = "esp8266";


class FirmwareUpdateRequest: public FormDataRequest
{
    FirmwareUpdateStream updateStream_;   
    bool updateStarted_ = false; 
public:
    FirmwareUpdateRequest(const HttpRequest &request)
        : FormDataRequest(request) 
        , updateStream_(OTA_VerificationKey)
    { }
    
protected:
    WriteStream *onFile(const String& name, const String& filename, HttpResponse& response) override
    {
        if ((name == "fwimage") && (!updateStarted_)) {
            Serial.printf("Start firmware update with image file %s\n", filename.c_str());
            updateStarted_ = true;
            return &updateStream_;
        }
        
        // reject any other file upload request
        response.code = HTTP_STATUS_BAD_REQUEST;
        return nullptr;
    }
    bool onComplete(HttpResponse& response) override
    {
        bool ok = FormDataRequest::onComplete(response);
        if (ok) {
            if (updateStarted_) {
                if (updateStream_.completed()) {
                    if (updateStream_.ok()) {
                        response.sendFile("updatecomplete.htm");
                    } else {
                        sendError(response, "Firmware update failed: " + updateStream_.errorMessage(), HTTP_STATUS_INTERNAL_SERVER_ERROR);
                    }                    
                } else {
                    sendError(response, "Incomplete firmware update file received.");
                }
            } else {
                sendError(response, "No firmware update file received");
            }
        }
        return ok;
    }
    
private:
    void sendError(HttpResponse& response, const String& message, enum http_status code = HTTP_STATUS_BAD_REQUEST)
    {
        response.code = code;
        response.setContentType(MIME_HTML);

        String html = "<H2 color='#444'>" + message + "</H2>";
        response.headers[HTTP_HEADER_CONTENT_LENGTH] = html.length();
        response.headers[HTTP_HEADER_CONNECTION] = "close";
        response.sendString(html);
    }
};


void onLedControl(HttpRequest& request, HttpResponse& response) 
{
    if (request.method == HTTP_GET) {
        const auto& q = request.uri.Query;
        if (q.contains("on")) {
            digitalWrite(LED_PIN, false);
        } else if (q.contains("off")) {
            digitalWrite(LED_PIN, true);
        }
    }
    response.sendFile("ledcontrol.htm");
}

void onFile(HttpRequest &request, HttpResponse &response) 
{
    String file = request.uri.Path;
    if (file[0] == '/') {
        file = file.substring(1);
    }
    if (!file.length()) {
        file = "index.htm";
    }

    if (!response.sendFile(file)) {        
        response.code = HTTP_STATUS_NOT_FOUND;
        response.sendFile("not-found.htm");
    }
}

void onRebootRequest(HttpRequest &request, HttpResponse &response)
{
    Serial.printf("Reboot request received\n");
    response.code = HTTP_STATUS_OK;
    response.setContentType(MIME_TEXT);
    response.sendString("Rebooting now...");
    System.restart(250 /* ms delay to allow sending the response */);
}


static void startWebServer()
{
    server.listen(80);
    server.paths.set("/ledcontrol.htm", onLedControl);
    server.paths.set("/reboot", onRebootRequest);
    server.paths.set("/fwupgrade", new FormDataResource<FirmwareUpdateRequest>);
    server.paths.setDefault(onFile);
    
    Serial.println(F("=== WEB SERVER STARTED ==="));
}

void startMDns() 
{
    espconn_mdns_close(); // release resources in case it is/was already running    
    
    struct mdns_info info = {};
    info.host_name = const_cast<char *>(hostname);
    info.ipAddr = WifiStation.getIP();
    info.server_name = const_cast<char *>("web_interface");
    info.server_port = 80;

    // The struct is copied by mdns_init, but strings must stay available after the function call
    espconn_mdns_init(&info);
}

static void wifiConnectOk(IPAddress ip, IPAddress mask, IPAddress gateway) 
{
    Serial.printf("Connection established: (IP: %s, mask: %s, gateway: %s)\n", ip.toString().c_str(), mask.toString().c_str(), gateway.toString().c_str());
    digitalWrite(LED_PIN, false); // LED on
    
    startMDns();
    startWebServer();
}

static void wifiDisconnected(String ssid, uint8_t ssidLen, uint8_t bssid[6], uint8_t reason) 
{
    Serial.printf("Wifi Connection lost from %s, reason = %u\n", ssid.c_str(), +reason);
    digitalWrite(LED_PIN, true); // LED off
}

void init()
{
    Serial.begin(SERIAL_BAUD_RATE);
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, true); // LED off (inverted)
    spiffs_mount(); // Mount file system
    
    // start WiFi connection
    WifiAccessPoint.enable(false);
    
    WifiStation.enable(true);
    WifiStation.config(WIFI_SSID, WIFI_PWD);
    WifiStation.enableDHCP(true);
    WifiStation.setHostname(hostname);
    
    // Set callback that should be triggered when we have assigned IP
    WifiEvents.onStationGotIP(wifiConnectOk);
    WifiEvents.onStationDisconnect(wifiDisconnected);
}
