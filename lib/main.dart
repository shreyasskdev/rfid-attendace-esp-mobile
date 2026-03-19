import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() => runApp(
  const MaterialApp(home: AttendanceApp(), debugShowCheckedModeBanner: false),
);

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});
  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  BluetoothDevice? espDevice;
  BluetoothCharacteristic? writeChar;
  List<String> liveLogs = [];
  List<String> historyLogs = [];
  String detectedUID = "Scan a card...";
  final TextEditingController nameC = TextEditingController();
  final TextEditingController rollC = TextEditingController();

  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String notifyUuid = "6d680001-70b3-4000-8000-000000000000";
  final String writeUuid = "6d680002-70b3-4000-8000-000000000000";

  void connect() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == "ESP32_Attendance") {
          r.device.connect(license: License.free).then((_) async {
            List<BluetoothService> services = await r.device.discoverServices();
            for (var s in services) {
              if (s.uuid.toString() == serviceUuid) {
                for (var c in s.characteristics) {
                  if (c.uuid.toString() == notifyUuid) {
                    await c.setNotifyValue(true);
                    c.onValueReceived.listen(handleData);
                  }
                  if (c.uuid.toString() == writeUuid) writeChar = c;
                }
              }
            }
            // SYNC TIME AUTOMATICALLY
            String timeCmd =
                "TIME:${DateTime.now().millisecondsSinceEpoch ~/ 1000}";
            writeChar?.write(utf8.encode(timeCmd));
            setState(() => espDevice = r.device);
          });
        }
      }
    });
  }

  void handleData(List<int> data) {
    String msg = utf8.decode(data);
    if (msg.startsWith("NEW_UID:"))
      setState(() => detectedUID = msg.substring(8));
    else if (msg == "END_HISTORY")
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Sync Complete")));
    else if (msg.startsWith("PRESENT:"))
      setState(() => liveLogs.insert(0, "Live: ${msg.substring(8)}"));
    else
      setState(() => historyLogs.insert(0, msg)); // Full history lines
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("RFID Attendance"),
          backgroundColor: Colors.blueGrey[900],
          foregroundColor: Colors.white,
          bottom: const TabBar(
            tabs: [
              Tab(text: "Register & Live"),
              Tab(text: "Full History"),
            ],
          ),
        ),
        body: TabBarView(children: [_buildRegisterTab(), _buildHistoryTab()]),
      ),
    );
  }

  Widget _buildRegisterTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (espDevice == null)
            ElevatedButton(
              onPressed: connect,
              child: const Text("Connect to System"),
            ),
          Text(
            "UID: $detectedUID",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.blue,
            ),
          ),
          TextField(
            controller: nameC,
            decoration: const InputDecoration(labelText: "Student Name"),
          ),
          TextField(
            controller: rollC,
            decoration: const InputDecoration(labelText: "Roll No"),
          ),
          ElevatedButton(
            onPressed: () {
              writeChar?.write(
                utf8.encode("ADD:${detectedUID},${nameC.text},${rollC.text}"),
              );
              nameC.clear();
              rollC.clear();
            },
            child: const Text("Register Student"),
          ),
          const Divider(),
          const Text("Live Scans:"),
          Expanded(
            child: ListView(
              children: liveLogs.map((e) => ListTile(title: Text(e))).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: () {
                setState(() => historyLogs.clear());
                writeChar?.write(utf8.encode("GET_HISTORY"));
              },
              child: const Text("Sync History from ESP32"),
            ),
            ElevatedButton(
              onPressed: () => writeChar?.write(utf8.encode("CLEAR_LOGS")),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                "Clear ESP32 Logs",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: historyLogs.length,
            itemBuilder: (c, i) => ListTile(
              leading: const Icon(Icons.history),
              title: Text(historyLogs[i]),
            ),
          ),
        ),
      ],
    );
  }
}
