import 'assistant_engine.dart';

class AssistantAnswerStyle {
  final _lastTemplate = <AssistantIntent, int>{};
  final _lastAnswer = <String, (String, DateTime)>{};
  int _insightIndex = 0;

  AssistantReply apply(
    AssistantIntent intent,
    String question,
    AssistantReply reply,
    DateTime now, {
    List<String> insights = const [],
  }) {
    const openings = <String>[
      'Here is the current picture.',
      'Looking at your records now.',
      'From the figures saved on this phone.',
      'Here is what FinKeep has tracked.',
    ];
    final last = _lastTemplate[intent] ?? -1;
    final index =
        (last + 1 + now.microsecondsSinceEpoch % (openings.length - 1)) %
        openings.length;
    _lastTemplate[intent] = index;
    final key = '${intent.name}:${normalizeQuestion(question)}';
    final signature =
        '${reply.text}|${reply.rows.map((row) => '${row.label}:${row.value}').join('|')}|${reply.visuals.map((part) => '${part.title}:${part.bigValue}:${part.data.map((d) => d.value).join(',')}').join('|')}';
    final previous = _lastAnswer[key];
    final repeated =
        previous != null &&
        previous.$1 == signature &&
        now.difference(previous.$2).inMinutes < 2;
    _lastAnswer[key] = (signature, now);
    final insight = insights.isEmpty
        ? null
        : insights[_insightIndex++ % insights.length];
    return AssistantReply(
      '${repeated ? 'Still the same as a minute ago. ' : '${openings[index]} '}${reply.text}${insight == null ? '' : '\nAnother angle: $insight'}',
      rows: reply.rows,
      chart: reply.chart,
      actions: reply.actions,
      suggestions: reply.suggestions,
      openForm: reply.openForm,
      visuals: reply.visuals,
      confirmation: reply.confirmation,
      undoMutation: reply.undoMutation,
    );
  }
}
