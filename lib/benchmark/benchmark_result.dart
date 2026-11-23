class BenchmarkResult {
  BenchmarkResult(this.data);
  final Map<String,dynamic> data;
  String get id=>data['id'] as String;
  double get totalSeconds=>(data['totalSeconds'] as num).toDouble();
  int get characters=>data['generatedCharacters'] as int;
  int? get tokens=>data['completionTokens'] as int?;
  Map<String,dynamic> toJson()=>data;
  static BenchmarkResult fromJson(Map<String,dynamic> data) {
    if(data['schema']!=1 || data['id'] is! String || data['generatedCharacters'] is! int ||
       data['totalSeconds'] is! num || (data['totalSeconds'] as num)<=0) {
      throw const FormatException('Invalid benchmark');
    }
    return BenchmarkResult(Map<String,dynamic>.from(data));
  }
}
