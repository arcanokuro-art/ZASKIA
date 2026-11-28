import 'package:flutter/material.dart';
import '../localization/strings.dart';
import 'download_manager.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  String _size(num n) => '${(n/1048576).toStringAsFixed(1)} MiB';
  @override
  Widget build(BuildContext context) {
    final manager=DownloadManager.instance;
    return Scaffold(appBar:AppBar(title:Text(S.t('Descargas')),actions:[
      IconButton(tooltip:S.t('Pausar todas'),onPressed:manager.pauseAll,icon:const Icon(Icons.pause))]),
      body:AnimatedBuilder(animation:manager,builder:(context,_)=>ListView(padding:const EdgeInsets.all(20),children:[
        Text(S.t('Las descargas se conservan al cerrar. Reanúdalas desde aquí. Los motores externos administran sus propios modelos.')),
        if(manager.tasks.isEmpty)Padding(padding:const EdgeInsets.all(24),child:Text(S.t('Sin descargas'))),
        for(final t in manager.tasks.reversed)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(t.name,style:Theme.of(context).textTheme.titleMedium),Text(t.repo),Text(S.t(t.status)),
          if(!t.finished)LinearProgressIndicator(value:t.progress),
          Text('${_size(t.received)}${t.total==null?'':' / ${_size(t.total!)}'} · ${_size(t.bytesPerSecond)}/s'),
          if(t.error.isNotEmpty)SelectableText(t.error),
          if(t.status=='Guardado')SelectableText(t.destination),
          Wrap(spacing:8,children:[
            if(!t.finished && !t.paused)TextButton.icon(onPressed:()=>manager.pause(t),icon:const Icon(Icons.pause),label:Text(S.t('Pausar'))),
            if(t.paused || t.status=='Error' || t.cancelled)TextButton.icon(onPressed:t.running?null:()=>manager.resume(t),icon:const Icon(Icons.play_arrow),label:Text(S.t('Reanudar'))),
            if(!t.finished)TextButton(onPressed:()=>manager.cancel(t),child:Text(S.t('Cancelar'))),
            if(t.finished)TextButton(onPressed:()=>manager.remove(t),child:Text(S.t('Quitar del historial'))),
          ]),
        ]))),
      ])));
  }
}
