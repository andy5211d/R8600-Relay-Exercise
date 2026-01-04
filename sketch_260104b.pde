//  ICOM Relay exercise routine.  Only run one a month, at most!
//  From an idea by John Rowing
//  2026/01/04 V1.2 ACH-G8NTH Uses json file for config data.  
//  Woking, freq and attn tables scanned. 

import processing.serial.*;
import java.util.*;

Serial civPort;

String serialPortName;
int serialBaud;
int civAddress;
int dwellMs;

class FrequencyEntry {
  String label;
  int freq;
}

class AttenuatorEntry {
  String label;
  int value;
}

ArrayList<FrequencyEntry> frequencyTable = new ArrayList<FrequencyEntry>();
ArrayList<AttenuatorEntry> attenuatorTable = new ArrayList<AttenuatorEntry>();

boolean scanning = false;
boolean freqPhase = true;   // true = scanning frequency_table, false = scanning attenuator_table

int scanIndex = 0;
int attIndex = 0;
int lastStepTime = 0;

String lastSentLabel = "";
int lastSentFreq = 0;
String lastAttLabel = "";
int lastAttValue = 0;

// Loop control
int loopCount = 0;
int maxLoops = 4;

// GUI button geometry
int btnX = 20;
int btnY = 320;
int btnW = 140;
int btnH = 40;

void setup() {
  size(250, 400);

  loadConfig();

  println("Opening serial port: " + serialPortName + " @ " + serialBaud);

  delay(500);  // avoid Processing serial init bug

  civPort = new Serial(this, serialPortName, serialBaud);
  civPort.clear();

  delay(200);

  println("Loaded " + frequencyTable.size() + " frequencies.");
  println("Loaded " + attenuatorTable.size() + " attenuator entries.");
}

void draw() {
  background(0);
  fill(255);

  textSize(14);
  text("ICOM R8600 Relay Exerciser", 20, 20);
  text("Serial: " + serialPortName, 20, 40);
  text("Baud: " + serialBaud, 20, 60);
  text("CI-V Addr: 0x" + hex(civAddress, 2), 20, 80);
  text("Dwell: " + dwellMs + " ms", 20, 100);

  text("Last Frequency sent:", 20, 140);
  text(lastSentLabel + " → " + lastSentFreq + " Hz", 20, 160);

  text("Last Attenuator setting:", 20, 190);
  text(lastAttLabel + " (value " + lastAttValue + ")", 20, 210);

  text("Loop: " + loopCount + " / " + maxLoops, 20, 240);

  text("Phase: " + (freqPhase ? "FREQ" : "ATTN"), 20, 260);

  drawButton();

  if (scanning) {
    text("SCANNING...", 20, 290);

    if (millis() - lastStepTime >= dwellMs) {
      stepScan();
      lastStepTime = millis();
    }
  } else {
    text("Scanner is idle", 20, 290);
  }
}

void drawButton() {
  if (scanning) fill(180, 50, 50);
  else fill(50, 180, 50);

  rect(btnX, btnY, btnW, btnH, 6);

  fill(0);
  textAlign(CENTER, CENTER);
  text(scanning ? "STOP" : "START", btnX + btnW/2, btnY + btnH/2);
  textAlign(LEFT, BASELINE);
}

void mousePressed() {
  if (mouseX > btnX && mouseX < btnX + btnW &&
      mouseY > btnY && mouseY < btnY + btnH) {

    scanning = !scanning;

    if (scanning) {
      // Reset state for a fresh run
      scanIndex = 0;
      attIndex  = 0;
      loopCount = 0;
      freqPhase = true;   // start each loop with frequency table
      lastStepTime = millis();

      // Start with the first frequency
      sendFrequency(frequencyTable.get(scanIndex));
    }
  }
}

void stepScan() {
  if (freqPhase) {
    // ---------------------------
    // PHASE 1: frequency_table
    // ---------------------------
    if (scanIndex < frequencyTable.size() - 1) {
      scanIndex++;
      sendFrequency(frequencyTable.get(scanIndex));
      return;
    }

    // Finished frequencies for this loop
    scanIndex = 0;
    freqPhase = false;   // switch to attenuator phase

    // Start attenuator phase with first entry
    attIndex = 0;
    sendAttenuator(attenuatorTable.get(attIndex));
    return;

  } else {
    // ---------------------------
    // PHASE 2: attenuator_table
    // ---------------------------
    if (attIndex < attenuatorTable.size() - 1) {
      attIndex++;
      sendAttenuator(attenuatorTable.get(attIndex));
      return;
    }

    // Finished attenuator phase for this loop
    attIndex = 0;
    freqPhase = true;   // next loop starts again with freq table

    loopCount++;
    println("Completed loop " + loopCount + " of " + maxLoops);

    if (loopCount >= maxLoops) {
      scanning = false;
      println("Scan complete after " + maxLoops + " loops.");
      return;
    }

    // Start next loop with first frequency
    scanIndex = 0;
    sendFrequency(frequencyTable.get(scanIndex));
  }
}

void sendFrequency(FrequencyEntry fe) {
  lastSentLabel = fe.label;
  lastSentFreq = fe.freq;

  println("Tuning to: " + fe.freq);

  byte[] cmd = buildCivFrequencyCommand(civAddress, 0xE0, fe.freq);
  civPort.write(cmd);

  print("Sent FREQ: ");
  for (int i = 0; i < cmd.length; i++) print(hex(cmd[i], 2) + " ");
  println();
}

void sendAttenuator(AttenuatorEntry ae) {
  lastAttLabel = ae.label;
  lastAttValue = ae.value;

  println("Setting attenuator: " + ae.label);

  byte[] frame = new byte[7];
  int i = 0;

  frame[i++] = (byte)0xFE;
  frame[i++] = (byte)0xFE;
  frame[i++] = (byte)civAddress;
  frame[i++] = (byte)0xE0;
  frame[i++] = 0x11;          // Attenuator command
  frame[i++] = (byte)ae.value;
  frame[i++] = (byte)0xFD;

  civPort.write(frame);

  print("Sent ATT: ");
  for (int j = 0; j < frame.length; j++) print(hex(frame[j], 2) + " ");
  println();
}

// ---------------------------
// CI-V IMPLEMENTATION
// ---------------------------

byte[] buildCivFrequencyCommand(int toAddr, int fromAddr, int freqHz) {
  byte[] bcd = toBcd5(freqHz);

  byte[] frame = new byte[11];
  int i = 0;

  frame[i++] = (byte)0xFE;
  frame[i++] = (byte)0xFE;
  frame[i++] = (byte)toAddr;
  frame[i++] = (byte)fromAddr;
  frame[i++] = 0x05;   // Set frequency

  for (int j = 0; j < 5; j++) frame[i++] = bcd[j];

  frame[i++] = (byte)0xFD;

  return frame;
}

byte[] toBcd5(int freq) {
  byte[] out = new byte[5];
  for (int i = 0; i < 5; i++) {
    int twoDigits = freq % 100;
    out[i] = (byte)(((twoDigits / 10) << 4) | (twoDigits % 10));
    freq /= 100;
  }
  return out;
}

// ---------------------------
// CONFIG LOADING
// ---------------------------

void loadConfig() {
  JSONObject cfg = loadJSONObject("config.json");

  JSONObject serialCfg = cfg.getJSONObject("serial");
  serialPortName = serialCfg.getString("port");
  serialBaud = serialCfg.getInt("baud");

  JSONObject civCfg = cfg.getJSONObject("civ");
  String civHex = civCfg.getString("address");
  civAddress = unhex(civHex.substring(2));

  dwellMs = cfg.getInt("dwell_ms");

  JSONArray arr = cfg.getJSONArray("frequency_table");
  for (int i = 0; i < arr.size(); i++) {
    JSONObject o = arr.getJSONObject(i);
    FrequencyEntry fe = new FrequencyEntry();
    fe.label = o.getString("label");
    fe.freq = o.getInt("freq");
    frequencyTable.add(fe);
  }

  JSONArray attArr = cfg.getJSONArray("attenuator_table");
  for (int i = 0; i < attArr.size(); i++) {
    JSONObject o = attArr.getJSONObject(i);
    AttenuatorEntry ae = new AttenuatorEntry();
    ae.label = o.getString("label");
    ae.value = o.getInt("value");
    attenuatorTable.add(ae);
  }
}
