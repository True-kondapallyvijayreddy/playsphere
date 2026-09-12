import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/club_thread.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/club_network_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import 'club_network_providers.dart';
import 'widgets/club_plan_gate.dart';
import 'widgets/share_to_club_sheet.dart';

/// One conversation between two clubs.
///
/// ## Reached two ways, and it has to work before it exists
///
/// The inbox opens a thread that already has messages in it. The directory
/// opens one that does not — `Routes.clubThreadWith` derives the id from the
/// pair (see [ClubThread.idFor]) and pushes straight here, because making
/// somebody tap "start a conversation" before they can type one is a step
/// that exists only to serve the database. So this screen renders a complete,
/// usable composer against a thread document that does not exist yet; the
/// first send creates it.
///
/// That is also why the two clubs come from the URL rather than from the
/// thread document. There is no document to read them off on the first visit.
class ClubThreadScreen extends ConsumerStatefulWidget {
  const ClubThreadScreen({super.key, required this.threadId});

  final String threadId;

  @override
  ConsumerState<ClubThreadScreen> createState() => _ClubThreadScreenState();
}

class _ClubThreadScreenState extends ConsumerState<ClubThreadScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _markedRead;

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The two club ids this thread is between, straight off the id.
  List<String> get _pair {
    final parts = widget.threadId.split('__');
    return parts.length == 2 ? parts : const [];
  }

  /// Which side of the conversation this person is on.
  ///
  /// Prefers the club they picked on the network screen, so somebody who owns
  /// both ends of a thread — rare, but it happens when an association absorbs
  /// a club — still speaks as the club they chose. Falls back to whichever
  /// side they own.
  String? _myOrgId(List<String> owned) {
    final pair = _pair;
    if (pair.isEmpty) return null;
    final acting = ref.read(actingClubIdProvider);
    if (acting != null && pair.contains(acting)) return acting;
    for (final id in pair) {
      if (owned.contains(id)) return id;
    }
    return null;
  }

  /// Marks the thread read for this club, once per thread per visit.
  ///
  /// Fire-and-forget: this is housekeeping behind a screen somebody opened to
  /// read, and a failed read marker must never surface as an error over the
  /// conversation they came for.
  void _markRead(String myOrgId, ClubThread? thread) {
    if (thread == null) return;
    if (!thread.isUnread) return;
    if (_markedRead == thread.id) return;
    _markedRead = thread.id;
    ref
        .read(clubNetworkRepositoryProvider)
        .markRead(threadId: thread.id, orgId: myOrgId)
        .ignore();
  }

  Future<void> _send({
    required Organization from,
    required Organization to,
    ThreadShare? share,
  }) async {
    final text = _composer.text.trim();
    if (text.isEmpty && share == null) return;
    setState(() => _sending = true);
    try {
      final me = ref.read(currentUserProvider).valueOrNull;
      final uid = ref.read(currentUidProvider);
      if (uid == null) return;
      await ref.read(clubNetworkRepositoryProvider).sendMessage(
            from: from,
            to: to,
            senderUid: uid,
            senderName: me?.displayName ?? 'A club owner',
            text: text,
            share: share,
          );
      if (!mounted) return;
      _composer.clear();
      // The list is newest-at-the-bottom, and the send that just landed is
      // the thing the sender wants to see.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owned = ref.watch(myOwnedOrgIdsProvider);
    final pair = _pair;
    final myOrgId = _myOrgId(owned);

    if (pair.isEmpty || myOrgId == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'This conversation is not yours',
          message: 'A club conversation is readable only by the owners of '
              'the two clubs in it.',
        ),
      );
    }

    final otherOrgId = pair.firstWhere((id) => id != myOrgId, orElse: () => '');
    final mine = ref.watch(organizationProvider(myOrgId)).valueOrNull;
    final them = ref.watch(organizationProvider(otherOrgId)).valueOrNull;
    final threadAsync = ref.watch(clubThreadProvider(
      (orgId: myOrgId, threadId: widget.threadId),
    ));
    final thread = threadAsync.valueOrNull;
    final messages =
        ref.watch(clubThreadMessagesProvider(widget.threadId)).valueOrNull ??
            const <ClubMessage>[];

    _markRead(myOrgId, thread);

    // The plan gate, and only where it belongs: on the FIRST message to a
    // club this one has never spoken to. A thread that already exists is
    // answerable whatever the plan says — see `ClubNetworkRepository`.
    final isNewConversation = thread == null && messages.isEmpty;
    final canOpen = ref.watch(canOpenNewClubThreadsProvider);
    final blocked = isNewConversation && !canOpen;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(them?.name ?? 'A club'),
            if (mine != null)
              Text(
                'as ${mine.name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          if (otherOrgId.isNotEmpty)
            IconButton(
              tooltip: 'Open their club page',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => context.push(Routes.org(otherOrgId)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _EmptyThread(them: them, blocked: blocked)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) => ContentBounds(
                      maxWidth: 820,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _MessageBubble(
                        message: messages[i],
                        isMine: messages[i].senderOrgId == myOrgId,
                        // The sender's name only when it changes, the way a
                        // chat reads — a run of five messages from the same
                        // club does not need the name five times.
                        showSender: i == 0 ||
                            messages[i - 1].senderUid != messages[i].senderUid,
                      ),
                    ),
                  ),
          ),
          if (blocked)
            ClubPlanGate(club: mine)
          else
            _Composer(
              controller: _composer,
              sending: _sending,
              onSend: mine == null || them == null
                  ? null
                  : () => _send(from: mine, to: them),
              onAttach: mine == null || them == null
                  ? null
                  : () async {
                      final share = await showShareToClubSheet(context, ref);
                      if (share == null || !mounted) return;
                      await _send(from: mine, to: them, share: share);
                    },
            ),
        ],
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.them, required this.blocked});

  final Organization? them;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      children: [
        ContentBounds(
          maxWidth: 640,
          child: Column(
            children: [
              if (them != null)
                PsCrest(
                  name: them!.name,
                  logoUrl: them!.logoUrl,
                  seed: them!.id,
                  size: 72,
                ),
              const SizedBox(height: 16),
              Text(
                them == null
                    ? 'Say hello'
                    : 'Nothing said to ${them!.name} yet',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                blocked
                    ? 'Opening a new conversation is part of the club plan.'
                    : 'Propose a fixture, invite them into a season, or ask '
                        'what they are running this term. Attach a season '
                        'with the paperclip and they can open it in one tap.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback? onSend;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: ContentBounds(
          maxWidth: 820,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Share a season',
                icon: const Icon(Icons.attach_file),
                onPressed: sending ? null : onAttach,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: 5,
                  minLines: 1,
                  maxLength: ClubNetworkRepository.maxMessageLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Write to this club',
                    border: OutlineInputBorder(),
                    isDense: true,
                    // The counter is noise until somebody is near the limit,
                    // and a permanent "0/2000" under a chat box reads as a
                    // form to fill in rather than a message to send.
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                // Announced even while it is a spinner, because that is when
                // somebody most needs to know what they pressed.
                tooltip: sending ? 'Sending' : 'Send',
                onPressed: sending ? null : onSend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showSender,
  });

  final ClubMessage message;
  final bool isMine;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = message.createdAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSender)
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6, bottom: 3),
              child: Text(
                message.senderName,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: isMine
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMine ? 14 : 2),
                  bottomRight: Radius.circular(isMine ? 2 : 14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.share case final share?) ...[
                    _ShareCard(share: share),
                    if (message.text.trim().isNotEmpty)
                      const SizedBox(height: 8),
                  ],
                  if (message.text.trim().isNotEmpty)
                    Text(
                      message.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isMine
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    // Null while the server timestamp is still in flight —
                    // the message is already on screen from the local cache,
                    // and an empty time is better than a wrong one.
                    at == null ? 'Sending…' : DateFormat('d MMM, h:mm a').format(at),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The season or event pinned to a message.
///
/// Rendered from the copy stored on the message rather than from a live read —
/// see [ThreadShare]. The tap is the live part.
class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.share});

  final ThreadShare share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = share.route;
    final when = share.startsAt;
    final sportId = share.sportId;

    return InkWell(
      onTap: route == null ? null : () => context.push(route),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (share.kind) {
                ThreadShareKind.season => Icons.emoji_events_outlined,
                ThreadShareKind.event => Icons.event_outlined,
                ThreadShareKind.club => Icons.shield_outlined,
              },
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    share.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (sportId != null) SportCatalog.byId(sportId).name,
                      if (share.subtitle case final s? when s.isNotEmpty) s,
                      if (when != null) DateFormat('d MMM yyyy').format(when),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
            if (route != null)
              const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
