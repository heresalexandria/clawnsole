import 'google_drive_asset_presenter_stub.dart'
    if (dart.library.io) 'google_drive_asset_presenter_io.dart'
    if (dart.library.js_interop) 'google_drive_asset_presenter_web.dart';
import 'google_drive_asset_presenter_base.dart';

export 'google_drive_asset_presenter_base.dart';

GoogleDriveAssetPresenter createGoogleDriveAssetPresenter() =>
    createPlatformGoogleDriveAssetPresenter();
