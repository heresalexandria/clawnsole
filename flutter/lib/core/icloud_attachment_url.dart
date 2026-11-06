import 'icloud_reference_transport.dart';

/// Apple's native publication API currently returns an attachment landing page.
/// This deliberately narrow resolver mirrors its observed template substitution,
/// not an authenticated Apple API. Fail closed if that undocumented shape changes.
Uri resolveICloudAttachmentUrl(
  String publication, {
  required int expectedBytes,
}) {
  Never invalid() => throw const ICloudReferenceException(
    'unsupportedPublication',
    'Apple returned a reference link Clawnsole cannot use. No generation was submitted. Try a public HTTPS media URL instead.',
  );
  try {
    final page = Uri.parse(publication);
    if (page.scheme != 'https' ||
        page.host != 'www.icloud.com' ||
        page.userInfo.isNotEmpty ||
        page.hasPort ||
        page.hasFragment ||
        !const {'/attachment', '/attachment/'}.contains(page.path)) {
      invalid();
    }
    // Do not use queryParameters: Apple's nested signed query is decoded as a
    // whole by its landing page, and includes its own ampersands and plus signs.
    final decoded = Uri.decodeComponent(publication);
    final start = decoded.indexOf('?u=');
    if (start < 0) invalid();
    final rest = decoded.substring(start + 3);
    final keyAt = rest.indexOf('&uk=');
    final fileAt = rest.indexOf('&f=', keyAt + 1);
    final sizeAt = rest.indexOf('&sz=', fileAt + 1);
    if (!(keyAt >= 0 && fileAt > keyAt && sizeAt > fileAt)) invalid();
    if (int.tryParse(rest.substring(sizeAt + 4)) != expectedBytes ||
        expectedBytes <= 0) {
      invalid();
    }
    final template = rest.substring(0, keyAt);
    final key = rest.substring(keyAt + 4, fileAt);
    final filename = rest.substring(fileAt + 3, sizeAt);
    if (key.isEmpty ||
        filename.isEmpty ||
        template.split(r'${f}').length != 2 ||
        template.split(r'${uk}').length != 2 ||
        filename.contains(RegExp(r'[\x00-\x1f\x7f/?#&]')) ||
        key.contains(RegExp(r'[\x00-\x20\x7f&#]'))) {
      invalid();
    }
    final expanded = template
        .replaceFirst(r'${f}', filename)
        .replaceFirst(r'${uk}', key);
    if (expanded.contains(r'${')) invalid();
    final target = Uri.parse(expanded);
    if (!isICloudAssetUrl(target)) {
      invalid();
    }
    return target;
  } on ICloudReferenceException {
    rethrow;
  } on Object {
    invalid();
  }
}

bool isICloudAssetUrl(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    !uri.hasPort &&
    !uri.hasFragment &&
    uri.host.endsWith('.icloud-content.com') &&
    uri.host != '.icloud-content.com' &&
    uri.path.isNotEmpty;
