import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';

void main() => runApp(
  const MaterialApp(home: AttendanceApp(), debugShowCheckedModeBanner: false),
);

class Student {
  String uid, name, roll;
  Student(this.uid, this.name, this.roll);
}

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});
  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  BluetoothDevice? dev;
  BluetoothCharacteristic? writeChar;
  Map<String, Student> allStudents = {};
  Set<String> presentToday = {};
  List<String> historyLogs = [];
  bool isAttOpen = true, isListeningForCard = false, isConnecting = false;
  String detectedUID = "Scan a card...";
  final nameC = TextEditingController(), rollC = TextEditingController();

  void connect() async {
    setState(() => isConnecting = true);
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName == "ESP32_Attendance") {
          FlutterBluePlus.stopScan();
          await r.device.connect(license: License.free);
          if (Platform.isAndroid) await r.device.requestMtu(255);
          var services = await r.device.discoverServices();
          for (var s in services) {
            for (var c in s.characteristics) {
              if (c.uuid.toString().contains("0001")) {
                await c.setNotifyValue(true);
                c.onValueReceived.listen(handleData);
              }
              if (c.uuid.toString().contains("0002")) writeChar = c;
            }
          }
          syncEverything();
          setState(() {
            dev = r.device;
            isConnecting = false;
          });
        }
      }
    });
  }

  void syncEverything() {
    writeChar?.write(
      utf8.encode("TIME:${DateTime.now().millisecondsSinceEpoch ~/ 1000}"),
    );
    writeChar?.write(utf8.encode("GET_STATUS"));
    writeChar?.write(utf8.encode("GET_STUDENTS"));
    writeChar?.write(utf8.encode("GET_TODAY"));
  }

  void handleData(List<int> data) {
    String msg = utf8.decode(data).trim();
    if (msg.startsWith("NEW_UID:")) {
      String uid = msg.substring(8);
      if (isListeningForCard) {
        setState(() {
          detectedUID = uid;
          isListeningForCard = false;
        });
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Unknown: $uid"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (msg.startsWith("LIVE:") || msg.startsWith("TOD:")) {
      if (!msg.contains("END"))
        setState(() => presentToday.add(msg.substring(msg.indexOf(':') + 1)));
    } else if (msg.startsWith("STU:")) {
      if (msg == "STU:END") return;
      var p = msg.substring(4).split(',');
      if (p.length >= 3)
        setState(() => allStudents[p[0]] = Student(p[0], p[1], p[2]));
    } else if (msg.startsWith("STAT:")) {
      setState(() => isAttOpen = msg.contains("OPEN"));
    } else if (msg.startsWith("HIS:")) {
      if (msg != "HIS:END") setState(() => historyLogs.add(msg.substring(4)));
    }
  }

  void _showScanDialog() {
    writeChar?.write(utf8.encode("PREP_REG"));
    setState(() {
      detectedUID = "Waiting...";
      isListeningForCard = true;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _PulseDialog(onCancel: () => isListeningForCard = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("RFID Attendance"),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          bottom: const TabBar(
            tabs: [
              Tab(text: "Today"),
              Tab(text: "Students"),
              Tab(text: "History"),
            ],
          ),
          actions: [
            if (dev != null)
              IconButton(
                icon: const Icon(Icons.sync),
                onPressed: syncEverything,
              ),
          ],
        ),
        body: dev == null
            ? Center(
                child: isConnecting
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: connect,
                        child: const Text("Connect System"),
                      ),
              )
            : TabBarView(children: [_todayTab(), _manageTab(), _historyTab()]),
      ),
    );
  }

  Widget _todayTab() {
    List<Student> pList = [];
    List<Student> aList = [];
    allStudents.forEach(
      (u, s) => presentToday.contains(u) ? pList.add(s) : aList.add(s),
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: isAttOpen ? Colors.green[50] : Colors.blueGrey[50],
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isAttOpen ? "SESSION: ACTIVE" : "SESSION: STOPPED",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (isAttOpen)
                    ElevatedButton(
                      onPressed: () {
                        writeChar?.write(utf8.encode("STOP_ATT"));
                        setState(() => isAttOpen = false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text(
                        "Stop Session",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
              if (!isAttOpen) const SizedBox(height: 10),
              if (!isAttOpen)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text("Start Fresh"),
                      onPressed: () {
                        setState(() {
                          presentToday.clear();
                          isAttOpen = true;
                        });
                        writeChar?.write(utf8.encode("START_ATT"));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text("Continue"),
                      onPressed: () {
                        setState(() => isAttOpen = true);
                        writeChar?.write(utf8.encode("RESUME_ATT"));
                        writeChar?.write(
                          utf8.encode("GET_TODAY"),
                        ); // Fetch existing logs
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              _sectionHeader("ABSENT (${aList.length})", Colors.red),
              ...aList.map(
                (s) => ListTile(
                  title: Text(s.name),
                  subtitle: Text(s.roll),
                  leading: const Icon(Icons.close, color: Colors.red),
                ),
              ),
              _sectionHeader("PRESENT (${pList.length})", Colors.green),
              ...pList.map(
                (s) => ListTile(
                  title: Text(s.name),
                  subtitle: Text(s.roll),
                  leading: const Icon(Icons.check, color: Colors.green),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _manageTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: nameC,
            decoration: const InputDecoration(
              labelText: "Student Name",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: rollC,
            decoration: const InputDecoration(
              labelText: "Roll Number",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    "UID: $detectedUID",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _showScanDialog,
                child: const Text("Scan Card"),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (detectedUID.contains("Scan") || detectedUID.contains("Wait"))
                return;
              writeChar?.write(
                utf8.encode("ADD:$detectedUID,${nameC.text},${rollC.text}"),
              );
              nameC.clear();
              rollC.clear();
              detectedUID = "Scan a card...";
              syncEverything();
            },
            child: const Text("Register Student"),
          ),
          const Divider(height: 40),
          const Text(
            "Registered Students",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...allStudents.values.map(
            (s) => ListTile(
              title: Text(s.name),
              subtitle: Text("Roll: ${s.roll} | ID: ${s.uid}"),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  writeChar?.write(utf8.encode("DEL:${s.uid}"));
                  setState(() => allStudents.remove(s.uid));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: const Text("Select Date"),
            onPressed: () async {
              DateTime? d = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
              );
              if (d != null) {
                setState(() => historyLogs.clear());
                writeChar?.write(
                  utf8.encode("GET_HIST:${DateFormat('dd-MM-yyyy').format(d)}"),
                );
              }
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: historyLogs.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(
                allStudents[historyLogs[i]]?.name ?? "Unknown Student",
              ),
              subtitle: Text("UID: ${historyLogs[i]}"),
              leading: const Icon(Icons.history),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    width: double.infinity,
    color: c.withOpacity(0.1),
    child: Text(
      t,
      style: TextStyle(color: c, fontWeight: FontWeight.bold),
    ),
  );
}

class _PulseDialog extends StatefulWidget {
  final VoidCallback onCancel;
  const _PulseDialog({required this.onCancel});
  @override
  State<_PulseDialog> createState() => _PulseDialogState();
}

class _PulseDialogState extends State<_PulseDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Card Registration"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.2).animate(_c),
            child: const Icon(Icons.nfc, size: 80, color: Colors.indigo),
          ),
          const SizedBox(height: 20),
          const Text("Tap the card on the reader now..."),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onCancel();
            Navigator.pop(context);
          },
          child: const Text("Cancel"),
        ),
      ],
    );
  }
}
