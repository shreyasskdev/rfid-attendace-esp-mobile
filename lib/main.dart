import 'dart:convert';
import 'dart:io';
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
  bool isConnecting = false;

  final TextEditingController nameC = TextEditingController();
  final TextEditingController rollC = TextEditingController();

  // Security Key (Must match ESP32)
  final String adminKey = "SECURE123";

  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String notifyUuid = "6d680001-70b3-4000-8000-000000000000";
  final String writeUuid = "6d680002-70b3-4000-8000-000000000000";

  void connect() async {
    setState(() => isConnecting = true);
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    var subscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName == "ESP32_Attendance") {
          FlutterBluePlus.stopScan();
          try {
            await r.device.connect(license: License.free);

            // IMPROVEMENT: Request MTU for long strings
            if (Platform.isAndroid) await r.device.requestMtu(255);

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

            // SYNC TIME
            String timeCmd =
                "TIME:${DateTime.now().millisecondsSinceEpoch ~/ 1000}";
            await writeChar?.write(utf8.encode(timeCmd));

            setState(() {
              espDevice = r.device;
              isConnecting = false;
            });
          } catch (e) {
            setState(() => isConnecting = false);
          }
        }
      }
    });
  }

  void handleData(List<int> data) {
    String msg = utf8.decode(data);
    if (msg.startsWith("NEW_UID:")) {
      setState(() => detectedUID = msg.substring(8));
    } else if (msg == "END_HISTORY") {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Sync Complete")));
    } else if (msg.startsWith("PRESENT:")) {
      setState(
        () => liveLogs.insert(
          0,
          "${DateTime.now().hour}:${DateTime.now().minute} - ${msg.substring(8)}",
        ),
      );
    } else {
      setState(() => historyLogs.insert(0, msg));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("RFID Attendance Pro"),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          bottom: const TabBar(
            tabs: [
              Tab(text: "Register"),
              Tab(text: "History"),
            ],
          ),
        ),
        body: isConnecting
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_buildRegisterTab(), _buildHistoryTab()]),
      ),
    );
  }

  Widget _buildRegisterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (espDevice == null)
            ElevatedButton.icon(
              onPressed: connect,
              icon: const Icon(Icons.bluetooth),
              label: const Text("Connect System"),
            ),
          const SizedBox(height: 20),
          Card(
            color: Colors.blueGrey[50],
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    "Detected UID",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  Text(
                    detectedUID,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextField(
            controller: nameC,
            decoration: const InputDecoration(labelText: "Student Name"),
          ),
          TextField(
            controller: rollC,
            decoration: const InputDecoration(labelText: "Roll Number"),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () {
              if (detectedUID.contains("Scan")) return;
              // SECURITY: Sending Key + Data
              String cmd =
                  "ADD:$adminKey,$detectedUID,${nameC.text},${rollC.text}";
              writeChar?.write(utf8.encode(cmd));
              nameC.clear();
              rollC.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Registration Sent")),
              );
            },
            child: const Text("Register / Update Student"),
          ),
          const Divider(height: 40),
          const Text(
            "Recent Scans",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: liveLogs.length,
            itemBuilder: (c, i) => ListTile(
              leading: const Icon(Icons.person, color: Colors.green),
              title: Text(liveLogs[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => historyLogs.clear());
                    writeChar?.write(utf8.encode("GET_HISTORY"));
                  },
                  child: const Text("Sync History"),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => writeChar?.write(utf8.encode("CLEAR_LOGS")),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: historyLogs.length,
            separatorBuilder: (c, i) => const Divider(height: 1),
            itemBuilder: (c, i) => ListTile(
              title: Text(historyLogs[i], style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ],
    );
  }
}
