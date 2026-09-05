import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';

/// One operator-written help entry (migration 133).
class Faq {
  final String question;
  final String answer;

  /// Optional grouping the operator chose. Null is normal — they are not made
  /// to invent a taxonomy before writing a single FAQ — and the screen renders
  /// one flat list when every entry is ungrouped.
  final String? category;

  const Faq({required this.question, required this.answer, this.category});

  static Faq? tryFromJson(Map<String, dynamic> json) {
    final q = (json['question'] as String?)?.trim();
    final a = (json['answer'] as String?)?.trim();
    // A half-written entry is worse than a missing one: an accordion that
    // opens onto nothing reads as a broken app, not an empty answer.
    if (q == null || q.isEmpty || a == null || a.isEmpty) return null;
    return Faq(
      question: q,
      answer: a,
      category: switch (json['category']) {
        String s when s.trim().isNotEmpty => s.trim(),
        _ => null,
      },
    );
  }
}

class FaqRepository {
  final ApiClient _api;
  const FaqRepository(this._api);

  Future<Result<List<Faq>>> list() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/faqs',
      query: {'audience': 'rider'},
    );
    return switch (res) {
      Ok(:final value) => Ok(switch (value['faqs']) {
          List raw => raw
              .whereType<Map>()
              .map((m) => Faq.tryFromJson(m.cast<String, dynamic>()))
              .whereType<Faq>()
              .toList(),
          _ => const <Faq>[],
        }),
      Err(:final error) => Err(error),
    };
  }
}

final faqRepositoryProvider =
    Provider<FaqRepository>((ref) => FaqRepository(ref.watch(apiClientProvider)));

/// The rider FAQs. Errors surface — unlike a decorative list, this is the whole
/// point of the screen the rider opened, and silently showing nothing would
/// read as "Hoppin has no answers" rather than "we could not load them".
final riderFaqsProvider = FutureProvider.autoDispose<List<Faq>>((ref) async {
  final result = await ref.watch(faqRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});
