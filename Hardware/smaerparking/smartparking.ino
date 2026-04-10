#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include "DHT.h"

// --- NETWORK CONFIG ---
const char* ssid = "ECE IEDC_LAB"; // [cite: 2]
const char* password = "uem@kolkata"; 
const char* firebase_url = "https://parking-bc5fe-default-rtdb.firebaseio.com/";

// --- PIN DEFINITIONS ---
// Parking Slots (Ultrasonic) [cite: 33, 31, 28, 43]
const int TRIG_PINS[] = {25, 27, 33, 18, 23}; 
const int ECHO_PINS[] = {26, 32, 35, 5, 34}; // [cite: 54]
// Fusion & Gate
const int IR_PIN = 4; // [cite: 23, 40]
const int SERVO_PIN = 13;
// Safety Suite (D14 and D2)
#define DHTPIN 14
#define DHTTYPE DHT11
#define MQ2_DIGITAL_PIN 2 

// --- OBJECT INITIALIZATION ---
LiquidCrystal_I2C lcd(0x27, 16, 2); // [cite: 45]
Servo gateServo;
DHT dht(DHTPIN, DHTTYPE);

// --- GLOBAL STATES ---
int currentCarsInLot = 0;
unsigned long slotStartTime[3] = {0, 0, 0};
bool isOccupied[3] = {false, false, false};
unsigned long gateOpenTime = 0;
bool gateIsOpen = false;
unsigned long lastSafetyUpdate = 0;

// --- CORE FUNCTIONS ---

void syncToFirebase(String path, String jsonPayload) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(firebase_url + path + ".json");
    http.setConnectTimeout(400); // Prevents hardware lag [cite: 83]
    http.PATCH(jsonPayload);
    http.end();
  }
}

long getDist(int i) {
  digitalWrite(TRIG_PINS[i], LOW); delayMicroseconds(2);
  digitalWrite(TRIG_PINS[i], HIGH); delayMicroseconds(10);
  digitalWrite(TRIG_PINS[i], LOW);
  long dur = pulseIn(ECHO_PINS[i], HIGH, 15000); // 15cm threshold logic [cite: 64]
  if (dur == 0) return 400; 
  return (dur * 0.034) / 2;
}

void setup() {
  Serial.begin(115200);
  
  // LCD Setup [cite: 46]
  lcd.init(); 
  lcd.backlight();
  lcd.print("SmartPark Boot");

  // Sensor & Actuator Setup
  gateServo.attach(SERVO_PIN);
  gateServo.write(0);
  dht.begin();
  pinMode(MQ2_DIGITAL_PIN, INPUT);
  
  for(int i=0; i<5; i++) {
    pinMode(TRIG_PINS[i], OUTPUT);
    pinMode(ECHO_PINS[i], INPUT);
  }
  pinMode(IR_PIN, INPUT);

  // WiFi Connect [cite: 18, 90]
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  
  lcd.clear();
}

void loop() {
  // 1. SLOT MONITORING (LCD PRIORITY) [cite: 15, 67, 84]
  for(int i=0; i<3; i++) {
    long d = getDist(i);
    bool s_now;
    
    // Slot 1: Dual-Sensor Fusion (IR + Ultrasonic) 
    if (i == 0) s_now = (d < 8 && digitalRead(IR_PIN) == LOW); 
    else s_now = (d < 8); // Slots 2 & 3: Ultrasonic only [cite: 34, 32]
    
    if(s_now != isOccupied[i]) {
      isOccupied[i] = s_now;
      if(isOccupied[i]) slotStartTime[i] = millis();
      
      // Instant LCD Update [cite: 21, 57]
      lcd.setCursor(0, 0);
      lcd.print("1:"); lcd.print(isOccupied[0]?"OCC":"AVL");
      lcd.print(" 2:"); lcd.print(isOccupied[1]?"OCC":"AVL");
      lcd.print(" 3:"); lcd.print(isOccupied[2]?"OCC":"AVL");
      
      // Sync to Firebase [cite: 68]
      String path = "slots/slot" + String(i+1);
      String payload = "{\"is_free\":" + String(isOccupied[i] ? "false" : "true") + 
                       ", \"status\":\"" + String(isOccupied[i] ? "occupied" : "free") + "\"}";
      syncToFirebase(path, payload);
    }
  }

  // 2. GATE LOGIC
  long dEntry = getDist(3); // Entry Sensor
  long dExit = getDist(4);  // Exit Sensor

  if ((dEntry < 8 || dExit < 8) && !gateIsOpen) {
    gateServo.write(90);
    gateIsOpen = true;
    gateOpenTime = millis();
    
    if (dEntry < 8) currentCarsInLot++;
    else if (currentCarsInLot > 0) currentCarsInLot--;
    
    syncToFirebase("analytics", "{\"total_cars\":" + String(currentCarsInLot) + "}");
  }

  if (gateIsOpen && (millis() - gateOpenTime > 3000)) {
    gateServo.write(0);
    gateIsOpen = false;
  }

  // 3. SAFETY SUITE (DHT11 & MQ-2)
  if (millis() - lastSafetyUpdate > 5000) {
    float t = dht.readTemperature();
    float h = dht.readHumidity();
    bool gasDanger = (digitalRead(MQ2_DIGITAL_PIN) == HIGH); 

    String payload = "{\"temp\":" + String(t) + 
                     ", \"humidity\":" + String(h) + 
                     ", \"gas_alert\":" + String(gasDanger ? "true" : "false") + "}";
    syncToFirebase("safety", payload);
    
    if(gasDanger) {
      lcd.setCursor(0, 1);
      lcd.print("!! GAS ALERT !! ");
    } else {
      lcd.setCursor(0, 1);
      lcd.print("In Lot: "); lcd.print(currentCarsInLot); lcd.print("   ");
    }
    lastSafetyUpdate = millis();
  }

  delay(50); // Continuous loop [cite: 71]
}