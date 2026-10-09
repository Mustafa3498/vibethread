import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// A one-shot message carried inside a bloc state. Each toast has a unique id,
/// so a listener fires once per message even if the text repeats.
class Toast extends Equatable {
  const Toast._(this.message, this.isError, this.id);

  factory Toast.info(String message) =>
      Toast._(message, false, DateTime.now().microsecondsSinceEpoch);

  factory Toast.error(String message) =>
      Toast._(message, true, DateTime.now().microsecondsSinceEpoch);

  final String message;
  final bool isError;
  final int id;

  @override
  List<Object?> get props => [message, isError, id];
}

/// Shows [toast] as a snackbar, but only on the screen that is currently on top
/// (several screens listen to the same bloc, so without this it would appear twice).
void showToast(BuildContext context, Toast toast, {SnackBarAction? action}) {
  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(toast.message),
        backgroundColor: toast.isError ? const Color(0xFF5A2A24) : null,
        action: action,
      ),
    );
}
