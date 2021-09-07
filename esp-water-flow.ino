#include <ESP8266WiFi.h>
#include <ESPAsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoOTA.h>
#include <LittleFS.h>

#define SENSOR_PIN 2
#define SENSOR_INTERRUPT digitalPinToInterrupt(SENSOR_PIN)
#define US_TO_S_FACTOR 1000000
#define BUFFER_MESSAGE_SIZE 32

//#define USE_WIFI_STA
#ifdef USE_WIFI_STA
  #define SSID "PixelBox"
  #define PASSWORD "Valentixeline26:-*"
  #define TCP_SERVER_HOSTNAME "valentin.ddns.info"
#else 
  #define SSID "Water-Flow"
  #define TCP_SERVER_HOSTNAME "192.168.4.2"
#endif

#define TCP_SERVER_PORT 8700
#define TIME_BEFORE_SEND 1000
//#define CONTINUE_SENDING // for debug

volatile byte pulseCount = 0;
byte lastPulse = 0; 
unsigned int pulseToSendTcp = 0, pulseToSendWs = 0;
String serverBuffer;
bool wifiConnecting;

unsigned long oldTime = 0, currentTime = 0;

AsyncClient *client = NULL;
AsyncWebServer server(80);
AsyncWebSocket ws("/ws"); 

void IRAM_ATTR pulseCounter() {
  pulseCount++;
}

void onEvent(AsyncWebSocket * server, AsyncWebSocketClient * client, AwsEventType type, void * arg, uint8_t *data, size_t len){
  if(type == WS_EVT_CONNECT){
    Serial.println(F("WebSocket new connection"));
  } else if(type == WS_EVT_DISCONNECT){
    Serial.println(F("WebSocket disconnected"));
  }
}

void runAsyncClient(){
  if(client != NULL) { //client already exists
    return;
  }

  Serial.println(F("Connection to TCP server"));

  client = new AsyncClient();
  if(client == NULL) { // Allocation failed
    Serial.println(F("Failed to create TCP client"));
    return;
  }

  client->onError([](void * arg, AsyncClient *c, int error){
    Serial.println(F("Connect TCP Error"));
    client = NULL;
    delete c;
  }, NULL);

  client->onConnect([](void * arg, AsyncClient *c){
    Serial.println(F("Connected to TCP server"));
    client->onError(NULL, NULL); // No more needed

    client->onDisconnect([](void * arg, AsyncClient *c){
      Serial.println(F("Disconnected from TCP server"));
      client = NULL;
      delete c;
    }, NULL);

    send();
  }, NULL);
    
  if(!client->connect(TCP_SERVER_HOSTNAME, TCP_SERVER_PORT)){
    Serial.println(F("Connect fail to TCP server"));
    delete client;
    client = NULL;
  }
}

void send() {
  digitalWrite(LED_BUILTIN, LOW);

  pulseToSendWs += pulseCount;
  pulseToSendTcp += pulseCount;

  if (ws.count() > 0) {
    serverBuffer.remove(0);
    serverBuffer += String(currentTime);
    serverBuffer += String(F(","));
    serverBuffer += String(pulseToSendWs);
    serverBuffer += String(F("\r\n"));
    
    ws.textAll(serverBuffer);
    pulseToSendWs = 0;
  }

  if (client != NULL) {
    serverBuffer.remove(0);
    serverBuffer += String(currentTime);
    serverBuffer += String(F(","));
    serverBuffer += String(pulseToSendTcp);
    serverBuffer += String(F("\r\n"));
      
    if (client->write(serverBuffer.c_str())) {
      pulseToSendTcp = 0;
    }
  }
  
  digitalWrite(LED_BUILTIN, HIGH);
}

void initOTA() {
  ArduinoOTA.onStart([]() {
    ws.enable(false);
    ws.closeAll();
    
    String type;
    if (ArduinoOTA.getCommand() == U_FLASH) {
      type = "sketch";
    } else { // U_FS
      type = "filesystem";
    }

    // NOTE: if updating FS this would be the place to unmount FS using FS.end()
    LittleFS.end();
    Serial.println("Start updating " + type);
  });
  ArduinoOTA.onEnd([]() {
    Serial.println("\nEnd");
  });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("Progress: %u%%\r", (progress / (total / 100)));
  });
  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("Error[%u]: ", error);
    if (error == OTA_AUTH_ERROR) {
      Serial.println("Auth Failed");
    } else if (error == OTA_BEGIN_ERROR) {
      Serial.println("Begin Failed");
    } else if (error == OTA_CONNECT_ERROR) {
      Serial.println("Connect Failed");
    } else if (error == OTA_RECEIVE_ERROR) {
      Serial.println("Receive Failed");
    } else if (error == OTA_END_ERROR) {
      Serial.println("End Failed");
    }
  });
  ArduinoOTA.begin();
}

void handleNotFound(AsyncWebServerRequest *request) {
  request->send(404);
}

void connectWiFi() {
  #ifdef USE_WIFI_STA
    Serial.println(F("Connection to box "));
    WiFi.begin(SSID, PASSWORD);
    wifiConnecting = true;
  #else
    WiFi.softAP(SSID);
    initOTA();
  #endif
}

void manageWiFi() {
  #ifdef USE_WIFI_STA
    if (WiFi.status() == WL_CONNECTED) {
      if (wifiConnecting) {
        Serial.print(F("Connected to box ")); Serial.println(WiFi.localIP());
        wifiConnecting = false;
        initOTA();
      }
  
      runAsyncClient();
      ws.cleanupClients();
    
      ArduinoOTA.handle();
    } else if (!wifiConnecting) {
      connectWiFi();
    }
  #else
    Serial.print(F("WiFi AP ")); Serial.println(WiFi.softAPIP());
        
    runAsyncClient();
    ws.cleanupClients();
  
    ArduinoOTA.handle();
  #endif
}

void setup() {
  serverBuffer.reserve(BUFFER_MESSAGE_SIZE);
  
  Serial.begin(115200);
  delay(100);
  Serial.println(F("\r\nStarting..."));
  
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH);
  
  pinMode(SENSOR_PIN, INPUT);
  digitalWrite(SENSOR_PIN, HIGH);
  
  oldTime = millis();
  attachInterrupt(SENSOR_INTERRUPT, pulseCounter, FALLING);

  #ifdef USE_WIFI_STA
    WiFi.mode(WIFI_STA);
  #else
    WiFi.mode(WIFI_AP);
  #endif
  connectWiFi();

  if (!LittleFS.begin()) {
    Serial.println(F("Impossible to open LittleFS"));
  }
  
  ws.onEvent(onEvent);
  server.addHandler(&ws);  
  server.onNotFound(handleNotFound);
  server.serveStatic("/", LittleFS, "/").setDefaultFile("index.html");
  server.begin();

  Serial.println(F("Started !"));
}

void loop() {
  currentTime = millis();

  if((currentTime - oldTime) >= TIME_BEFORE_SEND) {
    manageWiFi();
    
    detachInterrupt(SENSOR_INTERRUPT);

    #ifndef CONTINUE_SENDING
    if (pulseCount > 0 || lastPulse > 0) { 
    #endif   
      Serial.print(F("Pulse ")); Serial.println(pulseCount);
      send();
      lastPulse = pulseCount;
      pulseCount = 0;
    #ifndef CONTINUE_SENDING
    }
    #endif
  
    oldTime = millis();
    attachInterrupt(SENSOR_INTERRUPT, pulseCounter, FALLING);
  }
}
