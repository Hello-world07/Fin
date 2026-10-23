import 'dart:async';

import 'package:flutter/material.dart';

void showTimedSnackBar(ScaffoldMessengerState messenger, SnackBar snackBar) {
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(snackBar);
  final timer = Timer(snackBar.duration, controller.close);
  unawaited(controller.closed.whenComplete(timer.cancel));
}
