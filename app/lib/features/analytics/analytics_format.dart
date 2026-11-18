import '../accounts/money.dart';
import 'analytics_repository.dart';

/// Groups exact fixed-point values without converting them to floating point.
String analyticsAmount(BigInt amount) =>
    Money.groupDigits(ExchangeRates.display(amount));
