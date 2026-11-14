import 'package:flutter/material.dart';

void main() => runApp(const ZaskiaApp());

class ZaskiaApp extends StatelessWidget {
  const ZaskiaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ZASKIA',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7655E8)),
      scaffoldBackgroundColor: const Color(0xFFF8F8FC),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9C8AFF),
        brightness: Brightness.dark,
      ),
    ),
    home: const ZaskiaHome(),
  );
}

class ZaskiaHome extends StatefulWidget {
  const ZaskiaHome({super.key});
  @override
  State<ZaskiaHome> createState() => _ZaskiaHomeState();
}

class _ZaskiaHomeState extends State<ZaskiaHome> {
  int selected = 0;
  static const titles = ['Inicio', 'Chat', 'Crear imágenes', 'Editar imágenes', 'Ajustes'];
  static const icons = [
    Icons.home_rounded, Icons.chat_bubble_outline_rounded,
    Icons.auto_awesome_rounded, Icons.tune_rounded, Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 650;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZASKIA', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.3)),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Información',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'ZASKIA',
              applicationVersion: '0.1.0',
              children: [const Text('Powered by Zaskar Startup. Prototipo de interfaz: modelos de IA pendientes.')],
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: Row(children: [
        if (!narrow)
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: (value) => setState(() => selected = value),
            labelType: NavigationRailLabelType.all,
            destinations: List.generate(titles.length, (i) => NavigationRailDestination(
              icon: Icon(icons[i]), label: Text(titles[i]),
            )),
          ),
        Expanded(child: SafeArea(child: IndexedStack(index: selected, children: [
          _home(),
          const _ChatPreview(),
          const _FeaturePreview(
            icon: Icons.auto_awesome_rounded,
            title: 'Crear imágenes',
            description: 'Escribe una idea y conviértela en una imagen. El motor local de generación se integrará próximamente.',
          ),
          const _FeaturePreview(
            icon: Icons.image_outlined,
            title: 'Editar imágenes',
            description: 'Importa imágenes, describe cambios y conserva detalles. La edición por IA aún no está disponible.',
          ),
          const _SettingsPreview(),
        ]))),
      ]),
      bottomNavigationBar: narrow ? NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (value) => setState(() => selected = value),
        destinations: List.generate(titles.length, (i) => NavigationDestination(
          icon: Icon(icons[i]), label: titles[i],
        )),
      ) : null,
    );
  }

  Widget _home() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const SizedBox(height: 16),
      const Icon(Icons.blur_on_rounded, size: 66, color: Color(0xFF7655E8)),
      const SizedBox(height: 12),
      const Text('Tu creatividad, tu inteligencia.', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Bienvenido a ZASKIA', textAlign: TextAlign.center),
      const SizedBox(height: 26),
      ...List.generate(3, (i) {
        const labels = ['Conversar con ZASKIA', 'Generar una imagen', 'Editar una imagen'];
        const descriptions = ['Chat local (próximamente)', 'Convierte ideas en imágenes', 'Transforma tus imágenes'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              leading: Icon(icons[i + 1], size: 30),
              title: Text(labels[i], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(descriptions[i]),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => setState(() => selected = i + 1),
            ),
          ),
        );
      }),
      const SizedBox(height: 20),
      const Text('ZASKIA 0.1.0 · Powered by Zaskar Startup',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
    ],
  );
}

class _ChatPreview extends StatefulWidget {
  const _ChatPreview();
  @override
  State<_ChatPreview> createState() => _ChatPreviewState();
}

class _ChatPreviewState extends State<_ChatPreview> {
  final controller = TextEditingController();
  final messages = <String>[];
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(children: [
    const Padding(
      padding: EdgeInsets.all(18),
      child: Text('Vista previa del chat · Modelo de IA aún no instalado'),
    ),
    Expanded(child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, i) => Align(
        alignment: Alignment.centerRight,
        child: Card(child: Padding(
          padding: const EdgeInsets.all(14), child: Text(messages[i]),
        )),
      ),
    )),
    Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(child: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Escribe un mensaje…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => send(),
        )),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: send,
          icon: const Icon(Icons.arrow_upward_rounded),
        ),
      ]),
    ),
  ]);
  void send() {
    final value = controller.text.trim();
    if (value.isEmpty) return;
    setState(() => messages.add(value));
    controller.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('El motor de conversación local se integrará en una próxima versión.'),
    ));
  }
}

class _FeaturePreview extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _FeaturePreview({required this.icon, required this.title, required this.description});
  @override
  Widget build(BuildContext context) => Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 76, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 20),
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      Text(description, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      const Chip(label: Text('Próximamente · IA local')),
    ]),
  ));
}

class _SettingsPreview extends StatelessWidget {
  const _SettingsPreview();
  @override
  Widget build(BuildContext context) => ListView(children: const [
    ListTile(
      leading: Icon(Icons.memory_rounded),
      title: Text('Modelos locales'),
      subtitle: Text('Gestión de modelos disponible próximamente'),
    ),
    ListTile(
      leading: Icon(Icons.offline_bolt_outlined),
      title: Text('Modo sin conexión'),
      subtitle: Text('Se activará al integrar los motores de IA'),
    ),
    ListTile(
      leading: Icon(Icons.system_update_alt_rounded),
      title: Text('Actualizaciones'),
      subtitle: Text('Versión 0.1.0 · Actualización mediante APK firmada'),
    ),
    ListTile(
      leading: Icon(Icons.info_outline_rounded),
      title: Text('ZASKIA · Zaskar Startup'),
      subtitle: Text('Interfaz inicial de desarrollo'),
    ),
  ]);
}
