/// Blueprint §13 - Score Engine.
///
/// Every sport "owns" its scoring plugin. Concrete plugins (Cricket,
/// Football, Chess, ...) implement this contract, each defining its
/// own data model, validation rules, UI, reports and APIs, while the
/// engine only depends on this shared interface.
abstract class ScorePlugin<TState> {
  String get sportKey; // e.g. 'cricket', 'football', 'chess'

  TState initialState(String fixtureId);

  TState applyEvent(TState currentState, Map<String, dynamic> event);

  Map<String, dynamic> toReport(TState state);
}
