import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models.dart';
import 'common_widgets.dart';

/// Opens the film's detail modal: everything the card says, at nearly the
/// full viewport, so nothing has to be truncated — plus its lineage (the
/// film it was rewritten from and the films rewritten from it).
///
/// Implementation pending: this shell shows the provider details dialog so
/// every entry point already compiles and behaves.
Future<void> showGenerationDetailModal(
  BuildContext context, {
  required AppController controller,
  required Generation item,
}) => showGenerationDetails(
  context,
  item,
  progressEstimate: controller.generationProgress(item),
);
