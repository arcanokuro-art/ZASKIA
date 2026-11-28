import 'package:flutter/material.dart';
import '../localization/strings.dart';
import '../settings/app_settings.dart';
import '../runtime/model_runtime.dart';

class ExecutionScreen extends StatefulWidget {
  const ExecutionScreen({super.key,required this.runtime});
  final ModelRuntime runtime;
  @override
  State<ExecutionScreen> createState()=>_ExecutionScreenState();
}
class _ExecutionScreenState extends State<ExecutionScreen> {
  final s=AppSettings.instance;
  bool _busy=false;
  String _status='';
  Future<void> _set(String key,Object value)async{
    setState(()=>_busy=true);
    try {await s.set(key,value);if(mounted)setState(()=>_status='Guardado');}
    catch(_){if(mounted)setState(()=>_status='No se pudo guardar.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Widget _number(String key,String label,int min,int max)=>Padding(padding:const EdgeInsets.symmetric(vertical:8),child:TextFormField(
    key:ValueKey('$key-${s.snapshot[key]}'),initialValue:'${s.snapshot[key]}',enabled:!_busy,keyboardType:TextInputType.number,
    decoration:InputDecoration(labelText:S.t(label),helperText:'$min – $max',border:const OutlineInputBorder()),
    onFieldSubmitted:(value){final n=int.tryParse(value);if(n!=null&&n>=min&&n<=max)_set(key,n);},
  ));
  @override
  Widget build(BuildContext context)=>AnimatedBuilder(animation:s,builder:(context,_)=>Scaffold(
    appBar:AppBar(title:Text(S.t('Configuración de ejecución'))),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(padding:const EdgeInsets.all(24),children:[
      Text('${S.t('Motor')}: ${widget.runtime.engineStatus['engine']} · ${widget.runtime.selectedName}'),
      Text(S.t('CPU integrada. La aceleración y memoria de un motor externo se configuran en ese motor.')),
      for(final e in {'balanced':'Equilibrado','economy':'Ahorro','creative':'Escritura creativa','code':'Programación'}.entries)
        TextButton(onPressed:_busy?null:()async{await s.profile(e.key);},child:Text(S.t(e.value))),
      _number('threads','Hilos de CPU',1,64),_number('context','Tamaño del contexto',512,32768),_number('maxTokens','Longitud máxima de respuesta',32,8192),
      ListTile(title:Text(S.t('Temperatura')),trailing:Text('${s.get<double>('temperature')}')),
      Slider(value:s.get<double>('temperature'),min:0,max:2,divisions:20,onChanged:_busy?null:(v)=>_set('temperature',v)),
      _number('historyTurns','Turnos máximos en contexto',1,100),
      _number('requestTimeoutSeconds','Tiempo límite de respuesta (segundos)',30,1800),
      SwitchListTile(title:Text(S.t('Mostrar estadísticas de respuesta')),value:s.get<bool>('showGenerationStats'),onChanged:_busy?null:(v)=>_set('showGenerationStats',v)),
      Text(S.t('El historial se recorta por presupuesto de contexto. Es una estimación conservadora; el tokenizador depende del modelo.')),
      FilledButton(onPressed:_busy||widget.runtime.isBusy?null:()async{
        setState(()=>_busy=true);try{await widget.runtime.releaseMemory();if(mounted)setState(()=>_status='Configuración aplicada. El modelo se cargará al enviar.');}
        catch(_){if(mounted)setState(()=>_status='No se pudo completar la operación.');}finally{if(mounted)setState(()=>_busy=false);}
      },child:Text(S.t('Aplicar y liberar modelo'))),
      Text(S.t(_status)),
    ])))));
}
