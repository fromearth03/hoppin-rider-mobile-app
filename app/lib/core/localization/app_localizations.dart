import 'package:flutter/material.dart';
import 'catalog.dart';

/// Only app-authored copy goes through this catalogue. User content, places,
/// support replies and legal documents keep their original language.
String tr(BuildContext context, String source) {
  final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  if (code != 'ur' && code != 'hi') return source;
  final pair = translations[source];
  if (pair != null) return pair[code == 'ur' ? 0 : 1];
  for (final template in _templates) {
    final match = template.pattern.firstMatch(source);
    if (match == null) continue;
    var result = translations[template.key]![code == 'ur' ? 0 : 1];
    result = result.replaceAllMapped(RegExp(r'\{(\d+)\}'), (placeholder) {
      final index = int.parse(placeholder[1]!);
      final value = match.group(index + 1) ?? '';
      // Only the known app-authored waiting-time suffix is nested copy.
      if (template.key.startsWith('Cancelling is free') && index == 0) {
        return tr(context, value);
      }
      return value;
    });
    return result;
  }
  return source;
}

final _templates = [
  for (final key in translations.keys.where((key) => key.contains('{0}')))
    (
      key: key,
      pattern: RegExp(
        '^${key.split(RegExp(r'\{\d+\}')).map(RegExp.escape).join('(.*?)')}\$',
        dotAll: true,
      ),
    ),
];

String? trOptional(BuildContext context, String? source) =>
    source == null ? null : tr(context, source);

class AppText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final double? textScaleFactor;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });
  @override
  Widget build(BuildContext context) => Text(
    tr(context, data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler:
        textScaler ??
        (textScaleFactor == null ? null : TextScaler.linear(textScaleFactor!)),
    maxLines: maxLines,
    semanticsLabel: trOptional(context, semanticsLabel),
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}
