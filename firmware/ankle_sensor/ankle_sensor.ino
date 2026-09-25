#include <WiFi.h>
#include <esp_wifi.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <Wire.h>

// Flash this board as "HEEL", change to "FOREFOOT" and reflash for the other board.
#define SENSOR_ROLE "HEEL"

// Pins for ESP32-C3 SuperMini
#define SDA_PIN 8
#define SCL_PIN 9
#define RED_PIN   2
#define GREEN_PIN 3
#define BLUE_PIN  4
#define COMMON_ANODE 1

int MPU_ADDR = 0x68;
int16_t AcX, AcY, AcZ;
int16_t GyX, GyY, GyZ;

AsyncWebServer server(80);

// --- Status LED ---
void setColor(bool r, bool g, bool b) {
  if (COMMON_ANODE) {
    digitalWrite(RED_PIN,   !r);
    digitalWrite(GREEN_PIN, !g);
    digitalWrite(BLUE_PIN,  !b);
  } else {
    digitalWrite(RED_PIN,    r);
    digitalWrite(GREEN_PIN,  g);
    digitalWrite(BLUE_PIN,   b);
  }
}

// --- MPU6050 Helper ---
// Burst-reads accel (0x3B-0x40) + temp (0x41-0x42) + gyro (0x43-0x48) in one
// 14-byte transaction so both readings are from the same sample instant.
void readMPU() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14, true);
  if (Wire.available() == 14) {
    AcX = Wire.read() << 8 | Wire.read();
    AcY = Wire.read() << 8 | Wire.read();
    AcZ = Wire.read() << 8 | Wire.read();
    Wire.read(); Wire.read(); // discard temperature (0x41-0x42)
    GyX = Wire.read() << 8 | Wire.read();
    GyY = Wire.read() << 8 | Wire.read();
    GyZ = Wire.read() << 8 | Wire.read();
  }
}

// --- WiFi & SmartConfig ---
void initWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.setTxPower(WIFI_POWER_8_5dBm);

  setColor(0, 0, 1); // Blue: Waiting for App
  Serial.println("Waiting for SmartConfig...");
  WiFi.beginSmartConfig();

  while (!WiFi.smartConfigDone()) {
    delay(500);
    Serial.print(".");
  }

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print("*");
  }

  Serial.println("\nWiFi Connected!");
  Serial.println(WiFi.localIP());
  setColor(0, 1, 0); // Green: Connected
}

void setup() {
  Serial.begin(115200);
  delay(2000);

  pinMode(RED_PIN, OUTPUT);
  pinMode(GREEN_PIN, OUTPUT);
  pinMode(BLUE_PIN, OUTPUT);

  // Initialize I2C for MPU6050
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B); // Wake up
  Wire.write(0);
  if (Wire.endTransmission() != 0) {
    setColor(1, 0, 0); // Red: Hardware Error
    while(1);
  }

  initWiFi();

  // IDENTITY ENDPOINT — lets the app sort this board into heel/forefoot
  server.on("/whoami", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send(200, "text/plain", SENSOR_ROLE);
  });

  // APP DATA ENDPOINT
  server.on("/data", HTTP_GET, [](AsyncWebServerRequest *request) {
    readMPU();
    // Convert to G-units
    float ax = AcX / 16384.0;
    float ay = AcY / 16384.0;
    float az = AcZ / 16384.0;
    // Convert to deg/s (default MPU6050 gyro range is +/-250 deg/s)
    float gx = GyX / 131.0;
    float gy = GyY / 131.0;
    float gz = GyZ / 131.0;

    String json = "{";
    json += "\"ax\":" + String(ax, 3) + ",";
    json += "\"ay\":" + String(ay, 3) + ",";
    json += "\"az\":" + String(az, 3) + ",";
    json += "\"gx\":" + String(gx, 3) + ",";
    json += "\"gy\":" + String(gy, 3) + ",";
    json += "\"gz\":" + String(gz, 3);
    json += "}";

    request->send(200, "application/json", json);
  });

  server.begin();
}

void loop() {}
