import 'dart:io';
import '../hardware/hardware_snapshot.dart';

class DeviceInfo {
  static Future<Map<String,String>> read() async {
    final data = <String,String>{'Sistema':'${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Procesadores lógicos':'${Platform.numberOfProcessors}'};
    final hardware=await HardwareProbe.read();
    data['Arquitectura del proceso']=hardware.architecture;
    data['ABI']=hardware.abi;
    data['Procesadores utilizables']='${hardware.usableCores}';
    if(hardware.processor!=null)data['Procesador']=hardware.processor!;
    if(hardware.totalMemory!=null)data['RAM total']='${(hardware.totalMemory!/1073741824).toStringAsFixed(1)} GiB';
    if(hardware.availableMemory!=null)data['RAM disponible']='${(hardware.availableMemory!/1073741824).toStringAsFixed(1)} GiB';
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
