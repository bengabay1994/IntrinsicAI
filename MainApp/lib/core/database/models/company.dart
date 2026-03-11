import 'package:equatable/equatable.dart';

/// Represents a company in the database.
class Company extends Equatable {
  final String ticker;
  final String? name;
  final String? sector;
  final DateTime? lastUpdated;

  const Company({
    required this.ticker,
    this.name,
    this.sector,
    this.lastUpdated,
  });

  factory Company.fromMap(Map<String, dynamic> map) {
    return Company(
      ticker: map['ticker'] as String,
      name: map['name'] as String?,
      sector: map['sector'] as String?,
      lastUpdated: map['last_updated'] != null
          ? DateTime.tryParse(map['last_updated'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [ticker, name, sector, lastUpdated];
}
