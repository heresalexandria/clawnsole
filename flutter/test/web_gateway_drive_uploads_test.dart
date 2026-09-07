import 'dart:convert';

import 'package:clawnsole/core/asset_extensions.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const empty = LocalSnapshot(
    generations: <Generation>[],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'companion', bytes: 0, records: 0),
  );

  String state([Map<String, Object?>? uploads]) => jsonEncode(<String, Object?>{
    ...empty.toJson(),
    if (uploads != null) 'driveUploads': uploads,
  });

  http.Response json(String body, [int status = 200]) => http.Response(
    body,
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );

  test('the renderer adopts the companion queue from /state', () async {
    var notifications = 0;
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:8787'),
      client: MockClient(
        (request) async => json(
          state(<String, Object?>{
            'queued': <String>['staged-mine'],
            'foreign': <String>['staged-theirs'],
            'stalledDetail': 'Google Drive is not connected on this device.',
            'reported': true,
          }),
        ),
      ),
    );
    gateway.onDriveUploadStatus = () => notifications += 1;

    expect(gateway.driveUploadStatus.reported, isFalse);
    await gateway.load();

    expect(notifications, 1);
    final status = gateway.driveUploadStatus;
    expect(status.reported, isTrue);
    expect(status.queued, <String>{'staged-mine'});
    expect(status.foreign, <String>{'staged-theirs'});
    // The companion is this renderer's pump, so its stall is the Mac's own.
    expect(status.stateOf('staged-mine'), DriveUploadState.stalled);
    expect(
      status.stateOf('staged-theirs'),
      DriveUploadState.awaitingOtherDevice,
    );

    // The same queue on the next poll is not news. /state arrives every few
    // seconds and each report treated as a change rebuilds the studio.
    await gateway.load();
    expect(notifications, 1);
  });

  test('a companion that reports nothing leaves the queue unknown', () async {
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:8787'),
      client: MockClient((request) async => json(state())),
    );

    await gateway.load();

    final status = gateway.driveUploadStatus;
    // Unknown, not empty: an older companion has said nothing about who owes
    // these uploads, and silence must not read as "everything is published".
    expect(status.reported, isFalse);
    expect(status.queued, isEmpty);
    expect(status.stateOf('staged-anything'), DriveUploadState.awaitingUpload);
  });

  test('flushing posts to the companion and adopts its report', () async {
    final requests = <http.Request>[];
    var notifications = 0;
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:8787'),
      client: MockClient((request) async {
        requests.add(request);
        return json(
          jsonEncode(<String, Object?>{
            'settled': false,
            'driveUploads': <String, Object?>{
              'queued': <String>['staged-mine'],
              'foreign': <String>[],
              'reported': true,
            },
          }),
        );
      }),
    );
    gateway.onDriveUploadStatus = () => notifications += 1;

    expect(await gateway.flushDriveUploads(), isFalse);

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/drive/uploads/flush');
    expect(notifications, 1);
    expect(
      gateway.driveUploadStatus.stateOf('staged-mine'),
      DriveUploadState.uploading,
    );
  });

  test('a companion without the flush route leaves the queue alone', () async {
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:8787'),
      client: MockClient(
        (request) async =>
            json(jsonEncode(<String, Object?>{'error': 'Not found.'}), 404),
      ),
    );

    // Nothing new was learned, so nothing is claimed: the chips keep saying
    // "Awaiting upload" rather than inventing a queue or an error.
    expect(await gateway.flushDriveUploads(), isFalse);
    expect(gateway.driveUploadStatus.reported, isFalse);
  });
}
