class CollectorConfig {
  const CollectorConfig({this.filePattern = '*.jsonl', this.format = 'jsonl'});

  final String filePattern;
  final String format;

  Map<String, dynamic> toJson() => {
    'filePattern': filePattern,
    'format': format,
  };

  factory CollectorConfig.fromJson(Map<String, dynamic> json) {
    return CollectorConfig(
      filePattern: json['filePattern'] as String? ?? '*.jsonl',
      format: json['format'] as String? ?? 'jsonl',
    );
  }

  CollectorConfig copyWith({String? filePattern, String? format}) {
    return CollectorConfig(
      filePattern: filePattern ?? this.filePattern,
      format: format ?? this.format,
    );
  }
}
