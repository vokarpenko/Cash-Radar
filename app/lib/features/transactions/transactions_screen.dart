import 'package:flutter/material.dart';
import '../../shared/section_state.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Операции', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6),
      Text('Доходы и расходы', style: Theme.of(context).textTheme.bodyLarge),
      const Expanded(
        child: SectionState(
          icon: Icons.receipt_long_outlined,
          title: 'История операций',
          message: 'Учёт операций станет доступен позже.',
        ),
      ),
    ],
  );
}
