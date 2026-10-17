#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

/* 
This ESP32 BLE demo advertises the ESP32 so that the Godot application can find and connect to it.
Receives message from Godot and sends an updating couter value to the application through BLE notifications.
Prints connection events and received messages to the serial monitor.
*/

// Unique UUIDs for the BLE service and characteristic
#define SERVICE_UUID        "4faac1ea-1841-4c5a-a838-a384a8c4d357"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Create pointer for BLE server
BLEServer* pServer = nullptr;

// Lets setup() and loop() access the same characteristic
BLECharacteristic* pCharacteristic = nullptr;

// A changing test value
unsigned long testCounter = 0;

// Keeps track of whether a device is currently connected over BLE
bool deviceConnected = false;


// Handles changes that happen within the BLE server
class MyServerCallbacks : public BLEServerCallbacks {

  // Called automatically when a device connects
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;

    Serial.println("Connection established!");
  }

  // Called automatically when a device disconnects
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;

    Serial.println("Device disconnected.");

    // Start advertising again so another device can connect
    BLEDevice::startAdvertising();

    Serial.println("Advertising restarted.");
  }
};


// Handles changes that happen within the BLE characteristic
class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {

  // Called automatically when a device writes data to the characteristic
  void onWrite(BLECharacteristic* pCharacteristic) {

    // Get the value that was sent to the ESP32
    String receivedValue = pCharacteristic->getValue();

    // Check that a message was actually received
    if (receivedValue.length() > 0) {

      Serial.print("Received message: ");
      Serial.println(receivedValue);
    }
  }
};


void setup() {

  // Start communication
  Serial.begin(115200);

  // Start message
  Serial.println("Starting BLE...");

  // Initialize and name BLE device
  BLEDevice::init("Haptic_Glove_ESP32");

  // Create the BLE server
  pServer = BLEDevice::createServer();

  // Assign the connection callbacks to the BLE server
  pServer->setCallbacks(new MyServerCallbacks());

  // Create a service on the BLE server
  BLEService* pService = pServer->createService(SERVICE_UUID);

  // Allow reading, writing, and notifications
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );

  // Allow the connected client to enable notifications
  pCharacteristic->addDescriptor(new BLE2902());

  // Initial value available for reading
  pCharacteristic->setValue("ESP32 ready");

  // Run MyCharacteristicCallbacks when Godot writes to this characteristic.
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());

  // Start the BLE service
  pService->start();

  // Add the service to the advertising data
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);

  // Start advertising the ESP32
  pAdvertising->start();

  Serial.println("BLE advertising started.");
  Serial.println("Waiting for a Bluetooth connection...");
}


void loop() {

  // Only update while a peripheral is connected
  if (deviceConnected) {

    String message = "Count: " + String(testCounter);

    // Store the new value and attempt to notify the client
    pCharacteristic->setValue(message.c_str());
    pCharacteristic->notify();

    Serial.print("Updated test value: ");
    Serial.println(message);

    testCounter++;
  }

  // One update per 500 milliseconds
  delay(500);
}