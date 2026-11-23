import 'dart:io';

class DeviceInfo {
  static Future<Map<String,String>> read() async {
    final data = <String,String>{'Sistema':'${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Procesadores lógicos':'${Platform.numberOfProcessors}'};
    if (Platform.isLinux || Platform.isAndroid) {
      try {
        final mem = await File('/proc/meminfo').readAsString();
        for (final entry in {'MemTotal':'RAM total','MemAvailable':'RAM disponible'}.entries) {
          final match = RegExp('${entry.key}:\\s+(\\d+)').firstMatch(mem);
          if (match != null) data[entry.value] = '${(int.parse(match[1]!) / 1048576).toStringAsFixed(1)} GiB';
        }
        final cpu = await File('/proc/cpuinfo').readAsLines();
        final name = cpu.where((s)=>s.startsWith('model name')||s.startsWith('Hardware')).firstOrNull;
        if (name != null) data['Procesador'] = name.split(':').skip(1).join(':').trim();
      } catch (_) { /* Some Android devices restrict /proc. */ }
    }
    if (Platform.isLinux) {
      try {
        final r = await Process.run('df',['-Pk',Platform.environment['HOME'] ?? '/']);
        final line = r.stdout.toString().trim().split('\n').last.trim().split(RegExp(r'\s+'));
        if (r.exitCode == 0 && line.length>=4) data['Espacio libre'] = '${(int.parse(line[3])/1048576).toStringAsFixed(1)} GiB';
      } catch (_) {}
    }
    return data;
  }
}
