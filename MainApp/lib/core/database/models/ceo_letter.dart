import 'package:equatable/equatable.dart';

/// Data model representing a CEO letter to shareholders extracted from a 10-K filing.
class CeoLetter extends Equatable {
  final String ticker;
  final int fiscalYear;
  final String? filingDate;
  final String? rawExcerpt;
  final String? summary;
  final String fetchedAt;

  const CeoLetter({
    required this.ticker,
    required this.fiscalYear,
    this.filingDate,
    this.rawExcerpt,
    this.summary,
    required this.fetchedAt,
  });

  /// Whether this letter has a Gemini-generated summary.
  bool get hasSummary => summary != null && summary!.isNotEmpty;

  /// Creates a CeoLetter from a database row map.
  factory CeoLetter.fromMap(Map<String, dynamic> map) {
    return CeoLetter(
      ticker: map['ticker'] as String,
      fiscalYear: map['fiscal_year'] as int,
      filingDate: map['filing_date'] as String?,
      rawExcerpt: map['raw_excerpt'] as String?,
      summary: map['summary'] as String?,
      fetchedAt: map['fetched_at'] as String,
    );
  }

  @override
  List<Object?> get props => [
    ticker,
    fiscalYear,
    filingDate,
    rawExcerpt,
    summary,
    fetchedAt,
  ];
}
