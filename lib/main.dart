import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';

// --- Global Theme & Signal Management ---
ValueNotifier<String?> scanSignal = ValueNotifier(null);
ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

enum ThemeMode { system, light, dark }

void main() => runApp(const ZincApp());

class ZincColors {
  static const zinc50 = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc200 = Color(0xFFE4E4E7);
  static const zinc300 = Color(0xFFD4D4D8);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc800 = Color(0xFF27272A);
  static const zinc900 = Color(0xFF18181B);
  static const zinc950 = Color(0xFF09090B);

  static Brightness getBrightness(BuildContext context) {
    if (themeNotifier.value == ThemeMode.light) return Brightness.light;
    if (themeNotifier.value == ThemeMode.dark) return Brightness.dark;
    return MediaQuery.platformBrightnessOf(context);
  }

  static Color background(BuildContext context) =>
      getBrightness(context) == Brightness.dark ? zinc950 : zinc50;
  static Color surface(BuildContext context) =>
      getBrightness(context) == Brightness.dark
      ? zinc900
      : const Color(0xFFFFFFFF);
  static Color border(BuildContext context) =>
      getBrightness(context) == Brightness.dark ? zinc800 : zinc200;
  static Color text(BuildContext context) =>
      getBrightness(context) == Brightness.dark ? zinc50 : zinc950;
  static Color mutedText(BuildContext context) =>
      getBrightness(context) == Brightness.dark ? zinc400 : zinc500;
}

class ZincApp extends StatelessWidget {
  const ZincApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return CupertinoApp(
          theme: CupertinoThemeData(
            brightness: currentMode == ThemeMode.light
                ? Brightness.light
                : (currentMode == ThemeMode.dark ? Brightness.dark : null),
            primaryColor: CupertinoColors.label,
          ),
          home: const AttendanceApp(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

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
  List<Student> historyResults = [];
  bool isAttOpen = true, isConnecting = false, isHistorySyncing = false;
  String detectedUID = "---";

  final TextEditingController nameC = TextEditingController();
  final TextEditingController rollC = TextEditingController();

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
      detectedUID = uid;
      scanSignal.value = uid;
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
      if (msg == "HIS:END") {
        setState(() => isHistorySyncing = false);
        return;
      }
      String uid = msg.substring(4);
      if (allStudents.containsKey(uid))
        setState(() => historyResults.add(allStudents[uid]!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: ZincColors.surface(context),
        activeColor: ZincColors.text(context),
        border: Border(
          top: BorderSide(color: ZincColors.border(context), width: 0.5),
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.square_list),
            label: "Live",
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_2),
            label: "Directory",
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.archivebox),
            label: "History",
          ),
        ],
      ),
      tabBuilder: (context, i) {
        return CupertinoPageScaffold(
          backgroundColor: ZincColors.background(context),
          navigationBar: CupertinoNavigationBar(
            backgroundColor: ZincColors.surface(context).withOpacity(0.9),
            border: Border(
              bottom: BorderSide(color: ZincColors.border(context)),
            ),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              child: Icon(
                ZincColors.getBrightness(context) == Brightness.dark
                    ? CupertinoIcons.moon_fill
                    : CupertinoIcons.sun_max_fill,
                size: 20,
                color: ZincColors.text(context),
              ),
              onPressed: () {
                themeNotifier.value = themeNotifier.value == ThemeMode.light
                    ? ThemeMode.dark
                    : ThemeMode.light;
              },
            ),
            middle: Text(
              ["Attendance Board", "Student List", "History Archive"][i],
              style: TextStyle(
                color: ZincColors.text(context),
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: dev != null
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Icon(
                      CupertinoIcons.refresh,
                      size: 20,
                      color: ZincColors.text(context),
                    ),
                    onPressed: syncEverything,
                  )
                : null,
          ),
          child: SafeArea(
            child: dev == null
                ? _buildConnect()
                : [_todayTab(), _manageTab(), _historyTab()][i],
          ),
        );
      },
    );
  }

  Widget _buildConnect() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.antenna_radiowaves_left_right,
            size: 50,
            color: ZincColors.mutedText(context),
          ),
          const SizedBox(height: 20),
          CupertinoButton(
            color: ZincColors.text(context),
            onPressed: isConnecting ? null : connect,
            child: isConnecting
                ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                : Text(
                    "Connect Scanner",
                    style: TextStyle(
                      color: ZincColors.background(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // --- TAB 1: BOARD (RESTORED START FRESH) ---
  Widget _todayTab() {
    List<Student> students = allStudents.values.toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildZincCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Current State",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: ZincColors.mutedText(context),
                        ),
                      ),
                      Text(
                        isAttOpen ? "RECORDING" : "STOPPED",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: ZincColors.text(context),
                        ),
                      ),
                    ],
                  ),
                  if (isAttOpen)
                    CupertinoButton(
                      color: CupertinoColors.destructiveRed,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () {
                        writeChar?.write(utf8.encode("STOP_ATT"));
                        setState(() => isAttOpen = false);
                      },
                      child: const Text(
                        "Stop",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ),
                ],
              ),
              if (!isAttOpen) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.activeGreen,
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() => isAttOpen = true);
                          writeChar?.write(utf8.encode("RESUME_ATT"));
                        },
                        child: const Text(
                          "Continue",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CupertinoButton(
                        color: ZincColors.text(context),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() {
                            presentToday.clear();
                            isAttOpen = true;
                          });
                          writeChar?.write(utf8.encode("START_ATT"));
                        },
                        child: Text(
                          "Fresh Start",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: ZincColors.background(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildTable(
          headers: ["Roll", "Name", "Status"],
          rows: students.map((s) {
            bool present = presentToday.contains(s.uid);
            return [
              Text(
                s.roll,
                style: TextStyle(color: ZincColors.text(context), fontSize: 13),
              ),
              Text(
                s.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: ZincColors.text(context),
                  fontSize: 13,
                ),
              ),
              _buildStatusBadge(present ? "PRESENT" : "ABSENT", present),
            ];
          }).toList(),
        ),
      ],
    );
  }

  Widget _manageTab() {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildTable(
              headers: ["Name", "Roll", ""],
              rows: allStudents.values
                  .map(
                    (s) => [
                      Text(
                        s.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: ZincColors.text(context),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        s.roll,
                        style: TextStyle(
                          color: ZincColors.text(context),
                          fontSize: 13,
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Icon(
                          CupertinoIcons.trash,
                          size: 16,
                          color: CupertinoColors.destructiveRed,
                        ),
                        onPressed: () {
                          writeChar?.write(utf8.encode("DEL:${s.uid}"));
                          setState(() => allStudents.remove(s.uid));
                        },
                      ),
                    ],
                  )
                  .toList(),
              compact: true,
            ),
            const SizedBox(height: 80),
          ],
        ),
        Positioned(
          bottom: 20,
          right: 20,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _openAddStudentModal,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: ZincColors.text(context),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: CupertinoColors.black.withOpacity(0.2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.add,
                    color: ZincColors.background(context),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Add Student",
                    style: TextStyle(
                      color: ZincColors.background(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _historyTab() {
    DateTime selected = DateTime.now();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: CupertinoButton(
            color: ZincColors.surface(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.calendar,
                  color: ZincColors.text(context),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  "Query Date Archive",
                  style: TextStyle(
                    color: ZincColors.text(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            onPressed: () {
              showCupertinoModalPopup(
                context: context,
                builder: (context) => Container(
                  height: 320,
                  color: ZincColors.background(context),
                  child: Column(
                    children: [
                      Container(
                        color: ZincColors.surface(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Select Date",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: ZincColors.text(context),
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              child: Text(
                                "Done",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: ZincColors.text(context),
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  historyResults.clear();
                                  isHistorySyncing = true;
                                });
                                writeChar?.write(
                                  utf8.encode(
                                    "GET_HIST:${DateFormat('dd-MM-yyyy').format(selected)}",
                                  ),
                                );
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.date,
                          initialDateTime: selected,
                          onDateTimeChanged: (d) => selected = d,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 30,
          child: isHistorySyncing ? const CupertinoActivityIndicator() : null,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildTable(
                headers: ["Roll", "Name", "UID"],
                rows: historyResults
                    .map(
                      (s) => [
                        Text(
                          s.roll,
                          style: TextStyle(
                            color: ZincColors.text(context),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          s.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: ZincColors.text(context),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          s.uid,
                          style: TextStyle(
                            fontSize: 10,
                            color: ZincColors.mutedText(context),
                          ),
                        ),
                      ],
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openAddStudentModal() {
    detectedUID = "---";
    scanSignal.value = null;
    nameC.clear();
    rollC.clear();
    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.6,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: ZincColors.surface(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "New Registration",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: ZincColors.mutedText(context),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                CupertinoTextField(
                  controller: nameC,
                  placeholder: "Student Name",
                  style: TextStyle(color: ZincColors.text(context)),
                  decoration: _fieldBox(context),
                  padding: const EdgeInsets.all(14),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: rollC,
                  placeholder: "Roll Number",
                  style: TextStyle(color: ZincColors.text(context)),
                  decoration: _fieldBox(context),
                  padding: const EdgeInsets.all(14),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _fieldBox(context),
                  child: Row(
                    children: [
                      Icon(
                        detectedUID == "---"
                            ? CupertinoIcons.creditcard
                            : CupertinoIcons.check_mark_circled_solid,
                        color: detectedUID == "---"
                            ? ZincColors.mutedText(context)
                            : CupertinoColors.activeGreen,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          detectedUID == "---"
                              ? "No card detected"
                              : "UID: $detectedUID",
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 14,
                            color: detectedUID == "---"
                                ? ZincColors.mutedText(context)
                                : ZincColors.text(context),
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Text(
                          detectedUID == "---" ? "Scan Card" : "Rescan",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          writeChar?.write(utf8.encode("PREP_REG"));
                          await showCupertinoModalPopup(
                            context: context,
                            builder: (c) => const _PulseDialog(),
                          );
                          setModalState(
                            () => detectedUID = scanSignal.value ?? "---",
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                CupertinoButton(
                  color: ZincColors.text(context),
                  minSize: 50,
                  onPressed: (detectedUID == "---")
                      ? null
                      : () {
                          writeChar?.write(
                            utf8.encode(
                              "ADD:$detectedUID,${nameC.text},${rollC.text}",
                            ),
                          );
                          syncEverything();
                          Navigator.pop(context);
                        },
                  child: Center(
                    child: Text(
                      "Finalize Registration",
                      style: TextStyle(
                        color: ZincColors.background(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Helper UI methods
  Widget _buildTable({
    required List<String> headers,
    required List<List<Widget>> rows,
    bool compact = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: ZincColors.border(context)),
        borderRadius: BorderRadius.circular(8),
        color: ZincColors.surface(context),
      ),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: IntrinsicColumnWidth(),
          2: IntrinsicColumnWidth(),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: ZincColors.text(context).withOpacity(0.04),
            ),
            children: headers
                .map(
                  (h) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      h,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: ZincColors.text(context),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          ...rows.map(
            (row) => TableRow(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: ZincColors.border(context),
                    width: 0.5,
                  ),
                ),
              ),
              children: row
                  .map(
                    (cell) => Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: compact ? 8 : 14,
                      ),
                      child: cell,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String text, bool success) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: success ? const Color(0xFF166534) : const Color(0xFF991B1B),
        ),
      ),
    );
  }

  Widget _buildZincCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZincColors.surface(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ZincColors.border(context)),
      ),
      child: child,
    );
  }

  BoxDecoration _fieldBox(BuildContext context) => BoxDecoration(
    color: ZincColors.background(context).withOpacity(0.5),
    border: Border.all(color: ZincColors.border(context)),
    borderRadius: BorderRadius.circular(8),
  );
}

class _PulseDialog extends StatefulWidget {
  const _PulseDialog();
  @override
  State<_PulseDialog> createState() => _PulseDialogState();
}

class _PulseDialogState extends State<_PulseDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  bool isFinished = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    scanSignal.addListener(_onScanReceived);
  }

  void _onScanReceived() async {
    if (scanSignal.value != null && mounted) {
      setState(() => isFinished = true);
      _c.stop();
      _c.duration = const Duration(milliseconds: 300);
      _c.forward(from: 0.5);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    scanSignal.removeListener(_onScanReceived);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color activeColor = isFinished
        ? CupertinoColors.activeGreen
        : ZincColors.text(context);
    IconData activeIcon = isFinished
        ? CupertinoIcons.check_mark_circled_solid
        : CupertinoIcons.radiowaves_left;

    return CupertinoActionSheet(
      title: Text(
        isFinished ? "Success!" : "Ready to Sync",
        style: TextStyle(color: ZincColors.text(context)),
      ),
      message: Column(
        children: [
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              double scale = isFinished
                  ? (1.0 + (_c.value * 0.4))
                  : (1.0 + (_c.value * 0.25));
              return Transform.scale(
                scale: scale,
                child: Icon(activeIcon, size: 50, color: activeColor),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            isFinished
                ? "UID Captured: ${scanSignal.value}"
                : "Tap the student card on the RFID reader.",
            style: TextStyle(color: ZincColors.mutedText(context)),
          ),
        ],
      ),
      cancelButton: CupertinoActionSheetAction(
        child: Text(
          "Cancel",
          style: TextStyle(color: ZincColors.text(context)),
        ),
        isDestructiveAction: true,
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}
