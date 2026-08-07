import 'package:flutter/widgets.dart';

/// Pops [context]'s route (dialog or bottom sheet), releasing keyboard focus
/// first.
///
/// Popping a modal while a [TextField] inside it still holds focus deactivates
/// the modal's FocusScope inherited element while a dependent still references
/// it, tripping the framework's `InheritedElement.debugDeactivated` assert
/// (`_dependents.isEmpty`, reported as "depends is empty is not true") in
/// debug builds. Use this instead of `Navigator.of(context).pop()` anywhere a
/// focused text field can be present.
void popDialog(BuildContext context, [Object? result]) {
  FocusManager.instance.primaryFocus?.unfocus();
  Navigator.of(context).pop(result);
}
