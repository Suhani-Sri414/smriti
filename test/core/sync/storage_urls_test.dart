import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/sync/storage_urls.dart';

void main() {
  group('StorageUrls.resolvePublicUrl', () {
    test('returns empty string for null, empty, or whitespace-only paths', () {
      expect(StorageUrls.resolvePublicUrl(null), '');
      expect(StorageUrls.resolvePublicUrl(''), '');
      expect(StorageUrls.resolvePublicUrl('   '), '');
    });

    test('returns unmodified URL when already http or https', () {
      expect(
        StorageUrls.resolvePublicUrl('https://example.com/photo.jpg'),
        'https://example.com/photo.jpg',
      );
      expect(
        StorageUrls.resolvePublicUrl('http://example.com/avatar.png'),
        'http://example.com/avatar.png',
      );
    });

    test('resolves relative storage path using patient-media bucket fallback', () {
      expect(
        StorageUrls.resolvePublicUrl('people/per1.jpg'),
        'https://yzhtgpaekoqaszxgbeyn.supabase.co/storage/v1/object/public/patient-media/people/per1.jpg',
      );
    });

    test('strips redundant bucket prefix if provided in storage path', () {
      expect(
        StorageUrls.resolvePublicUrl('patient-media/people/per1.jpg'),
        'https://yzhtgpaekoqaszxgbeyn.supabase.co/storage/v1/object/public/patient-media/people/per1.jpg',
      );
    });

    test('strips leading slashes from storage path', () {
      expect(
        StorageUrls.resolvePublicUrl('/patients/p1/people/per1.jpg'),
        'https://yzhtgpaekoqaszxgbeyn.supabase.co/storage/v1/object/public/patient-media/patients/p1/people/per1.jpg',
      );
    });

    test('supports custom bucket parameter', () {
      expect(
        StorageUrls.resolvePublicUrl('icons/apple.png', bucket: 'lang-packs'),
        'https://yzhtgpaekoqaszxgbeyn.supabase.co/storage/v1/object/public/lang-packs/icons/apple.png',
      );
    });
  });

  group('StorageUrls.resolveAuthenticatedUrl and resolvePhotoUrl', () {
    test('returns empty string for null, empty, or whitespace-only paths', () {
      expect(StorageUrls.resolveAuthenticatedUrl(null), '');
      expect(StorageUrls.resolveAuthenticatedUrl(''), '');
      expect(StorageUrls.resolveAuthenticatedUrl('   '), '');
      expect(StorageUrls.resolvePhotoUrl(null), '');
      expect(StorageUrls.resolvePhotoUrl(''), '');
    });

    test('returns unmodified URL when already http or https (non-public Supabase)', () {
      expect(
        StorageUrls.resolvePhotoUrl('https://example.com/photo.jpg'),
        'https://example.com/photo.jpg',
      );
    });

    test('rewrites public Supabase storage URLs to authenticated segment', () {
      expect(
        StorageUrls.resolvePhotoUrl(
          'https://yzhtgpaekoqaszxgbeyn.supabase.co/storage/v1/object/public/patient-media/family/mom.jpg',
        ),
        'https://yzhtgpaekoqaszxgbeyn.supabase.co/storage/v1/object/authenticated/patient-media/family/mom.jpg',
      );
    });

    test('constructs authenticated URL with patient-media bucket', () {
      expect(
        StorageUrls.resolvePhotoUrl('people/per1.jpg'),
        'https://yzhtgpaekoqaszxgbeyn.supabase.co/storage/v1/object/authenticated/patient-media/people/per1.jpg',
      );
    });

    test('strips redundant patient-media prefix', () {
      expect(
        StorageUrls.resolvePhotoUrl('patient-media/people/per1.jpg'),
        'https://yzhtgpaekoqaszxgbeyn.supabase.co/storage/v1/object/authenticated/patient-media/people/per1.jpg',
      );
    });

    test('strips leading slashes', () {
      expect(
        StorageUrls.resolvePhotoUrl('/patients/p1/people/per1.jpg'),
        'https://yzhtgpaekoqaszxgbeyn.supabase.co/storage/v1/object/authenticated/patient-media/patients/p1/people/per1.jpg',
      );
    });
  });
}
