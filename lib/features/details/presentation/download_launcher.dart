import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../core/extensions/base_provider.dart';
import '../../../core/logger/app_logger.dart';
import '../../../core/services/download_service.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/loading_dialog.dart';
import '../../../shared/widgets/custom_widgets.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../core/services/notification_service.dart';

import 'package:skystream/l10n/generated/app_localizations.dart';

part 'download_launcher.g.dart';

@Riverpod(keepAlive: true)
DownloadLauncher downloadLauncher(Ref ref) {
  return DownloadLauncher(ref);
}

class DownloadLauncher {
  // TODO(l10n): 'Download Error' has no ARB key yet. It was already hardcoded
  // at both toast sites in this file; hoisting it keeps the third one from
  // adding a fourth copy of an untranslated literal.
  static const String _downloadErrorTitle = 'Download Error';

  final Ref _ref;

  DownloadLauncher(this._ref);

  /// Starts the download flow for [item].
  ///
  /// Plugin-based items resolve their streams here via the active
  /// SkyStreamProvider. Extension-based items (MStream) pass their already
  /// resolved [preloadedStreams] instead — there is no SkyStream provider
  /// behind those, and routing them through `activeProvider` used to download
  /// the wrong URL entirely.
  Future<void> launch(
    BuildContext context,
    MultimediaItem item, {
    String? episodeUrl,
    List<StreamResult>? preloadedStreams,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final resolveUrl = episodeUrl ?? item.url;
    if (resolveUrl.isEmpty) return;

    if (preloadedStreams != null) {
      if (preloadedStreams.isEmpty) {
        _ref
            .read(notificationServiceProvider)
            .showError(
              l10n.noDownloadSourcesFound,
              title: _downloadErrorTitle,
              icon: Icons.error_outline_rounded,
            );
        return;
      }
      // Streams are already resolved (and carry the extension's headers).
      _showSourcePicker(
        context,
        preloadedStreams,
        item,
        resolveUrl,
        preloadedStreams: preloadedStreams,
      );
      return;
    }

    bool isCanceled = false;
    unawaited(
      LoadingDialog.show(
        context,
        message: l10n.resolving,
        onCancel: () => isCanceled = true,
      ),
    );

    try {
      // 2. Resolve streams
      final manager = _ref.read(extensionManagerProvider.notifier);
      SkyStreamProvider? provider;
      if (item.provider != null) {
        try {
          final val = item.provider!;
          provider = manager.getAllProviders().firstWhere(
            (p) => p.packageName == val || p.name == val,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('DownloadLauncher.launch: $e');
        }
      }
      provider ??= _ref.read(activeProviderProvider);
      if (provider == null) throw Exception('No active provider');

      final streams = await provider.loadStreams(resolveUrl);
      if (isCanceled || !context.mounted) return;

      Navigator.of(context).pop(); // Dismiss loading dialog

      if (streams.isEmpty) {
        throw Exception(l10n.noDownloadSourcesFound);
      }

      // 3. Show Source Picker
      _showSourcePicker(
        context,
        streams,
        item,
        resolveUrl,
        preloadedStreams: streams,
      );
    } catch (e) {
      if (!context.mounted) return;
      if (!isCanceled) Navigator.of(context).pop(); // Dismiss if still there
      _ref
          .read(notificationServiceProvider)
          .showError(
            l10n.errorPrefix(e.toString()),
            title: _downloadErrorTitle,
            icon: Icons.error_outline_rounded,
          );
    }
  }

  void _showSourcePicker(
    BuildContext context,
    List<StreamResult> streams,
    MultimediaItem item,
    String resolveUrl, {
    List<StreamResult>? preloadedStreams,
  }) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  l10n.selectSource,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: streams.length,
                  itemBuilder: (context, index) {
                    final stream = streams[index];
                    final label = stream.source != 'Auto'
                        ? stream.source
                        : 'Source ${index + 1}';
                    final host = Uri.tryParse(stream.url)?.host ?? '';

                    return ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: Text(label),
                      subtitle: host.isNotEmpty ? Text(host) : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        verifyAndDownload(
                          context,
                          stream,
                          item,
                          resolveUrl,
                          preloadedStreams: preloadedStreams,
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Verifies the source, then shows the confirmation dialog whose
  /// "Download Now" button starts the download.
  ///
  /// Reachable from a test so the confirm button's failure path can be driven
  /// end to end; production only calls it from the source picker.
  @visibleForTesting
  Future<void> verifyAndDownload(
    BuildContext context,
    StreamResult stream,
    MultimediaItem item,
    String resolveUrl, {
    List<StreamResult>? preloadedStreams,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final downloadService = _ref.read(downloadServiceProvider);

    // 1. Show verification dialog
    // Use root navigator context if current context is unmounted
    final navContext = rootNavigatorKey.currentContext ?? context;

    bool isCanceled = false;
    unawaited(
      showDialog<void>(
        context: navContext,
        barrierDismissible: false, // Block UI interaction
        builder: (ctx) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLoadingIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.verifyingSourceSize),
                ],
              ),
              actions: [
                CustomButton(
                  isPrimary: false,
                  onPressed: () {
                    isCanceled = true;
                    Navigator.of(ctx).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(l10n.cancel),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final metadata = await downloadService
        .getMetadata(stream.url, headers: stream.headers)
        .timeout(const Duration(seconds: 15), onTimeout: () => null);

    if (!navContext.mounted) return;
    if (!isCanceled) {
      Navigator.of(navContext, rootNavigator: true).pop();
    } else {
      return; // Canceled, don't proceed
    }

    final finalContext = rootNavigatorKey.currentContext ?? navContext;

    // HLS playlists cannot be saved as one file by the byte-stream downloader;
    // refuse those explicitly. Every other URL can download with an unknown
    // size — many extension hosts never answer with a Content-Length, and
    // refusing those was blocking perfectly valid sources.
    if (_looksLikeHls(stream.url, metadata?.mimeType)) {
      if (finalContext.mounted) {
        _showErrorDialog(
          finalContext,
          l10n.downloadUnsupportedSource,
          stream,
          item,
          resolveUrl,
          preloadedStreams: preloadedStreams,
        );
      }
      return;
    }

    // `metadata == null` only means the size probe failed (HEAD blocked,
    // Range ignored, timeout); the URL itself may still download fine.
    final effectiveMetadata = metadata ?? DownloadMetadata();

    // 2. Show Confirmation Dialog
    if (finalContext.mounted) {
      unawaited(
        showDialog<void>(
          context: finalContext,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.confirmDownload),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.titleWithParam(item.title)),
                const SizedBox(height: 8),
                Text(l10n.sourceWithParam(stream.source)),
                const SizedBox(height: 8),
                Text(
                  l10n.sizeWithParam(
                    effectiveMetadata.size == null
                        ? l10n.unknown
                        : effectiveMetadata.sizeString,
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.fileSaveLocationNotification),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _startConfirmedDownload(
                    l10n: l10n,
                    stream: stream,
                    item: item,
                    resolveUrl: resolveUrl,
                    metadata: effectiveMetadata,
                  );
                },
                child: Text(l10n.downloadNow),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Runs the actual start after the confirm dialog has already popped.
  ///
  /// Everything in here has to report its own failure. The dialog is gone by
  /// the time this runs, so an escaping exception leaves the user staring at
  /// the details screen with no progress row, no toast and no way to tell that
  /// anything went wrong - `startDownload` throws a FileSystemException on
  /// every Android 11+ device where All-files-access was declined.
  Future<void> _startConfirmedDownload({
    required AppLocalizations l10n,
    required StreamResult stream,
    required MultimediaItem item,
    required String resolveUrl,
    required DownloadMetadata metadata,
  }) async {
    final downloadService = _ref.read(downloadServiceProvider);
    try {
      // Finalize path and filename
      final episodeData = item.episodes?.firstWhereOrNull(
        (e) => e.url == resolveUrl,
      );
      final saveDir = await downloadService.getDownloadPath(
        item,
        episode: episodeData,
      );

      final extension = _getFileExtension(stream.url, metadata.mimeType);
      String filename;
      if (episodeData != null &&
          item.contentType != MultimediaContentType.movie) {
        final sanitizedEpName = episodeData.name
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .trim();
        // Extension episodes carry no season (defaults to 0) — "S0-E3" is
        // noise, so only emit the season segment when there is one.
        final seasonPrefix =
            episodeData.season > 0 ? 'S${episodeData.season}-' : '';
        final epSegment = episodeData.episode > 0
            ? 'E${episodeData.episode}'
            : l10n.episodes;
        filename = sanitizedEpName.isEmpty
            ? '$seasonPrefix$epSegment$extension'
            : '$seasonPrefix$epSegment $sanitizedEpName$extension';
      } else {
        final sanitizedTitle = item.title
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .trim();
        filename = "$sanitizedTitle$extension";
      }

      if (kDebugMode) {
        debugPrint('[DownloadLauncher] Final Path: $saveDir/$filename');
      }

      final started = await downloadService.startDownload(
        url: stream.url,
        filename: filename,
        directory: saveDir,
        item: item,
        episode: episodeData,
        trackingUrl: resolveUrl,
        headers: stream.headers,
      );

      if (!started) {
        _ref
            .read(notificationServiceProvider)
            .showError(
              l10n.downloadStartFailed,
              title: _downloadErrorTitle,
              icon: Icons.folder_off_rounded,
            );
      }
    } catch (error, stackTrace) {
      talker.error(
        'DownloadLauncher: "Download Now" failed for "${item.title}"',
        error,
        stackTrace,
      );
      _ref
          .read(notificationServiceProvider)
          .showError(
            l10n.errorPrefix(error.toString()),
            title: _downloadErrorTitle,
            icon: Icons.error_outline_rounded,
          );
    }
  }

  void _showErrorDialog(
    BuildContext context,
    String message,
    StreamResult stream,
    MultimediaItem item,
    String resolveUrl, {
    List<StreamResult>? preloadedStreams,
  }) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.downloadUnavailable),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Go back to the source picker, without re-resolving streams
              // that are already in hand.
              launch(
                context,
                item,
                episodeUrl: resolveUrl,
                preloadedStreams: preloadedStreams,
              );
            },
            child: Text(l10n.selectAnotherSource),
          ),
        ],
      ),
    );
  }

  /// True for HLS playlist URLs, which the byte-stream downloader cannot save
  /// as a single file. Checked on the URL and the probed MIME type.
  bool _looksLikeHls(String url, String? mimeType) {
    if (mimeType != null &&
        (mimeType.contains('mpegurl') || mimeType.contains('m3u8'))) {
      return true;
    }
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.m3u8') || path.contains('.m3u8?');
  }

  String _getFileExtension(String url, String? mimeType) {
    if (mimeType != null) {
      if (mimeType.contains('video/mp4')) return '.mp4';
      if (mimeType.contains('video/x-matroska')) return '.mkv';
      if (mimeType.contains('video/webm')) return '.webm';
    }

    final uri = Uri.tryParse(url);
    if (uri != null) {
      final path = uri.path.toLowerCase();
      if (path.endsWith('.mp4')) return '.mp4';
      if (path.endsWith('.mkv')) return '.mkv';
      if (path.endsWith('.webm')) return '.webm';
      if (path.endsWith('.avi')) return '.avi';
    }

    return '.mp4'; // Default
  }
}
