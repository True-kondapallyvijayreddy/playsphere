import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/errors/app_exception.dart';
import 'package:playsphere/data/image_composer.dart';

/// The content type an upload is labelled with is the whole difference
/// between a banner that appears and one that silently does not: the object
/// uploads either way, `storage.rules` accepts it either way, Firestore
/// stores the URL either way, and the app says "Picture updated" either way.
/// Only the browser disagrees, hours later, by drawing nothing.
Uint8List bytesOf(List<int> head, {int pad = 32}) =>
    Uint8List.fromList([...head, ...List.filled(pad, 0)]);

void main() {
  group('sniff', () {
    test('recognises the three formats a browser can draw', () {
      expect(
        ImageComposer.sniff(bytesOf([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        'image/png',
      );
      expect(ImageComposer.sniff(bytesOf([0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
      expect(
        ImageComposer.sniff(bytesOf([
          0x52, 0x49, 0x46, 0x46, // RIFF
          0x00, 0x00, 0x00, 0x00, // size
          0x57, 0x45, 0x42, 0x50, // WEBP
        ])),
        'image/webp',
      );
    });

    test('recognises the formats it must refuse rather than mislabel', () {
      expect(ImageComposer.sniff(bytesOf([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])),
          'image/gif');
      expect(ImageComposer.sniff(bytesOf([0x42, 0x4D])), 'image/bmp');
      expect(ImageComposer.sniff(bytesOf([0x49, 0x49, 0x2A, 0x00])), 'image/tiff');
      expect(ImageComposer.sniff(bytesOf([0x4D, 0x4D, 0x00, 0x2A])), 'image/tiff');
    });

    test('separates HEIC from AVIF by ISO brand', () {
      Uint8List iso(String brand) => bytesOf([
            0x00, 0x00, 0x00, 0x18,
            0x66, 0x74, 0x79, 0x70, // ftyp
            ...brand.codeUnits,
          ]);
      expect(ImageComposer.sniff(iso('heic')), 'image/heic');
      expect(ImageComposer.sniff(iso('heix')), 'image/heic');
      expect(ImageComposer.sniff(iso('mif1')), 'image/heic');
      expect(ImageComposer.sniff(iso('avif')), 'image/avif');
      // A plain MP4 shares the box but is not an image at all.
      expect(ImageComposer.sniff(iso('isom')), isNull);
    });

    test('a truncated file is not mistaken for anything', () {
      expect(ImageComposer.sniff(Uint8List.fromList([0xFF])), isNull);
      expect(ImageComposer.sniff(Uint8List(0)), isNull);
    });
  });

  group('contentTypeOf', () {
    test('passes web-safe formats through', () {
      expect(ImageComposer.contentTypeOf(bytesOf([0xFF, 0xD8, 0xFF])),
          'image/jpeg');
      expect(
        ImageComposer.contentTypeOf(
            bytesOf([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        'image/png',
      );
    });

    test('refuses an iPhone HEIC by name instead of calling it a JPEG', () {
      // The regression this whole test file exists for. `storage.rules`
      // accepts image/heic, so the old fall-through to 'image/jpeg' produced
      // an object that uploaded cleanly and that no browser will ever decode.
      expect(
        () => ImageComposer.contentTypeOf(bytesOf([
          0x00, 0x00, 0x00, 0x18,
          0x66, 0x74, 0x79, 0x70,
          ...'heic'.codeUnits,
        ])),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            allOf(contains('HEIC'), contains('JPG or PNG')),
          ),
        ),
      );
    });

    test('refuses GIF, BMP, TIFF and AVIF', () {
      for (final head in [
        [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
        [0x42, 0x4D],
        [0x49, 0x49, 0x2A, 0x00],
        [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66],
      ]) {
        expect(
          () => ImageComposer.contentTypeOf(bytesOf(head)),
          throwsA(isA<ValidationException>()),
          reason: 'head $head should be refused, not relabelled',
        );
      }
    });

    test('says "not an image" for something that is not one', () {
      expect(
        () => ImageComposer.contentTypeOf(
            Uint8List.fromList('%PDF-1.4 hello'.codeUnits)),
        throwsA(
          isA<ValidationException>()
              .having((e) => e.message, 'message', contains('does not look like an image')),
        ),
      );
    });

    test('every accepted type is one the web build can actually draw', () {
      expect(ImageComposer.webSafeTypes,
          {'image/jpeg', 'image/png', 'image/webp'});
    });
  });
}
