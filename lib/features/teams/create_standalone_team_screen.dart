import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// Raising a team that belongs to no club.
///
/// Deliberately shorter than `CreateTeamScreen`, and not a variant of it. That
/// screen's real work is the roster picker — ticking eleven names off a club's
/// hundred-member list — and it needs an org and an admin capability to have
/// a list at all. There is no list here: the people who will play for this
/// team are in five different clubs, and the product cannot enumerate them.
///
/// So this form asks for the three things a squad genuinely needs, creates it
/// with the person making it as captain and sole member, and hands them a
/// code to pass round. Everybody else arrives by asking — see
/// `TeamJoinRequest` for why a code cannot be the thing that lets them in.
class CreateStandaloneTeamScreen extends ConsumerStatefulWidget {
  const CreateStandaloneTeamScreen({super.key});

  @override
  ConsumerState<CreateStandaloneTeamScreen> createState() =>
      _CreateStandaloneTeamScreenState();
}

class _CreateStandaloneTeamScreenState
    extends ConsumerState<CreateStandaloneTeamScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _area = TextEditingController();
  String? _sportId;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    final uid = ref.read(currentUidProvider);
    final sportId = _sportId;
    if (uid == null) return;
    if (sportId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick the sport this team plays')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final teamId =
          await ref.read(teamRepositoryProvider).createIndependentTeam(
                name: _name.text,
                sportId: sportId,
                createdByUid: uid,
                homeArea:
                    _area.text.trim().isEmpty ? null : _area.text.trim(),
              );
      if (!mounted) return;
      // Replace rather than push: coming back to a form that has already
      // created the team would let a second tap create a second one.
      context.pushReplacement(Routes.team(teamId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(currentUidProvider) != null;

    if (!signedIn) {
      return const AppScaffold(
        title: 'New team',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sign in first',
          message: 'A team needs somebody to captain it, so creating one '
              'needs an account.',
        ),
      );
    }

    return AppScaffold(
      title: 'New independent team',
      subtitle: 'No club needed',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          ContentBounds(
            maxWidth: 640,
            child: Form(
              key: _form,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Team name',
                        hintText: 'Gachibowli Strikers',
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'A team needs a name.'
                          : null,
                    ),

                    const SizedBox(height: 6),
                    const Text(
                      'SPORT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        color: Ps.faint,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final sport in SportCatalog.all)
                          ChoiceChip(
                            label: Text(sport.name),
                            selected: _sportId == sport.id,
                            // One sport, not several. A squad is picked for a
                            // game — the same eleven people playing volleyball
                            // on Sunday are a different team, and giving them
                            // one document would put two sports' records on
                            // one name.
                            onSelected: (on) => setState(
                              () => _sportId = on ? sport.id : null,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _area,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Where you play (optional)',
                        hintText: 'Gachibowli',
                        helperText: 'Helps players nearby find you',
                      ),
                    ),

                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _busy ? null : _create,
                      child: Text(_busy ? 'Creating…' : 'Create team'),
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'You will be the captain, and the only player on it to '
                      'start with. The team gets a code you can pass round — '
                      'anyone who has it can ask to join, and you decide who '
                      'gets on.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: Ps.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
