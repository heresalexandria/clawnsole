import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/anthropic_rewrite_api.dart';
import 'package:clawnsole/core/openai_rewrite_api.dart';
import 'package:clawnsole/core/prompt_rewrite.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 32×32 red JPEG standing in for a sampled film frame.
const String _frameJpeg =
    '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGg'
    'AAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAIKADAAQAAAABAAAAIAAAAAD/7QA4UGhv'
    'dG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8'
    'AAEQgAIAAgAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//E'
    'ALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJD'
    'NicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3'
    'eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1t'
    'fY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYH'
    'CAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQ'
    'kjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdo'
    'aWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8'
    'jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUF'
    'BQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAg'
    'ICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ'
    'EBAQEBAQEBAQEP/dAAQAAv/aAAwDAQACEQMRAD8A+X6KKK/Ez/UAKKKKAP/Q+X6KKK/Ez/'
    'UAKKKKAP/Z';

PromptRewriteRequest _request(RewriteProvider provider) {
  final frame = base64Decode(_frameJpeg);
  return PromptRewriteRequest(
    providerId: provider.id,
    modelId: provider.defaultModelId,
    effort: 'low',
    originalPrompt:
        'A red kite gliding over rolling sand dunes at golden hour. Slow '
        'cinematic pan from left to right, warm low sunlight, gentle wind '
        'lifting fine sand off the crests.',
    direction: 'Make the kite blue and move the camera much slower.',
    frames: <RewriteFrame>[
      RewriteFrame(bytes: frame, seconds: 0),
      RewriteFrame(bytes: frame, seconds: 3),
    ],
    targetProviderName: 'BFL',
    targetModelName: 'FLUX 3 Video',
    maxPromptCharacters: 10000,
    durationSeconds: 6,
    aspectRatio: '16:9',
    mode: 't2v',
  );
}

void main() {
  final openAiKey = Platform.environment['OPENAI_API_KEY']?.trim() ?? '';
  final anthropicKey = Platform.environment['ANTHROPIC_API_KEY']?.trim() ?? '';

  test(
    'live OpenAI model listing and prompt rewrite',
    () async {
      final api = OpenAiRewriteApi();
      final models = await api.listModels(openAiKey);
      expect(models, isNotEmpty);
      expect(
        models.map((model) => model.id),
        contains(RewriteProvider.openai.defaultModelId),
      );
      final result = await api.rewrite(
        _request(RewriteProvider.openai),
        openAiKey,
      );
      expect(result.providerId, 'openai');
      expect(result.prompt.toLowerCase(), contains('blue'));
      expect(result.summary, isNotEmpty);
      stdout.writeln('OpenAI ${result.modelId}: ${result.summary}');
      stdout.writeln(result.prompt);
    },
    skip: openAiKey.isEmpty
        ? 'Set OPENAI_API_KEY to run the paid live rewrite smoke test.'
        : false,
  );

  test(
    'live Anthropic model listing and prompt rewrite',
    () async {
      final api = AnthropicRewriteApi();
      final models = await api.listModels(anthropicKey);
      expect(models, isNotEmpty);
      expect(
        models.map((model) => model.id),
        contains(RewriteProvider.anthropic.defaultModelId),
      );
      final result = await api.rewrite(
        _request(RewriteProvider.anthropic),
        anthropicKey,
      );
      expect(result.providerId, 'anthropic');
      expect(result.prompt.toLowerCase(), contains('blue'));
      expect(result.summary, isNotEmpty);
      stdout.writeln('Anthropic ${result.modelId}: ${result.summary}');
      stdout.writeln(result.prompt);
    },
    skip: anthropicKey.isEmpty
        ? 'Set ANTHROPIC_API_KEY to run the paid live rewrite smoke test.'
        : false,
  );
}
