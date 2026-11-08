/// The text layer of RFC 5545 (§3.1): folded lines, content lines with their
/// parameters, escaped text. Nothing here knows what a VEVENT is.
library;

import 'dart:convert';

final class ContentLine {
  const ContentLine(this.name, this.params, this.value, this.line);

  /// Upper case.
  final String name;

  /// Parameter names upper case; each value list as written (quotes removed).
  final Map<String, List<String>> params;
  final String value;

  /// 1-based physical line where the content line starts.
  final int line;

  String? param(String name) {
    final v = params[name];
    return v == null || v.isEmpty ? null : v.first;
  }
}

final _breaks = RegExp(r'\r\n|\n|\r');

/// Unfolds the text: a line starting with a space or a tab continues the
/// previous one. CRLF, bare LF or bare CR.
List<({String text, int line})> unfold(String text) {
  final out = <({String text, int line})>[];
  final physical = (text.startsWith('﻿') ? text.substring(1) : text).split(_breaks);
  for (var i = 0; i < physical.length; i++) {
    final l = physical[i];
    if ((l.startsWith(' ') || l.startsWith('\t')) && out.isNotEmpty) {
      out.last = (text: out.last.text + l.substring(1), line: out.last.line);
    } else if (l.isNotEmpty) {
      out.add((text: l, line: i + 1));
    }
  }
  return out;
}

/// `NAME;P=a,"b,c";Q=x:value` → its parts, or null when there is no colon
/// after the name and parameters.
ContentLine? parseLine(String text, int line) {
  final nameEnd = text.indexOf(RegExp('[;:]'));
  if (nameEnd <= 0) return null;
  final name = text.substring(0, nameEnd).toUpperCase();
  final params = <String, List<String>>{};
  var i = nameEnd;
  String at(int k) => k < text.length ? text[k] : '';
  while (at(i) == ';') {
    final eq = text.indexOf('=', i);
    if (eq < 0) return null;
    final key = text.substring(i + 1, eq).toUpperCase();
    final values = <String>[];
    i = eq + 1;
    for (;;) {
      if (at(i) == '"') {
        final close = text.indexOf('"', i + 1);
        if (close < 0) return null;
        values.add(text.substring(i + 1, close));
        i = close + 1;
      } else {
        var j = i;
        while (j < text.length && text[j] != ',' && text[j] != ';' && text[j] != ':') {
          j++;
        }
        values.add(text.substring(i, j));
        i = j;
      }
      if (at(i) != ',') break;
      i++;
    }
    params[key] = values;
  }
  if (at(i) != ':') return null;
  return ContentLine(name, params, text.substring(i + 1), line);
}

final _escaped = RegExp(r'\\([\\;,nN])');

/// TEXT values (§3.3.11): `\n` `\N` `\,` `\;` `\\`.
String unescapeText(String v) => v.replaceAllMapped(_escaped, (m) => m[1] == 'n' || m[1] == 'N' ? '\n' : m[1]!);

String escapeText(String v) => v.replaceAllMapped(RegExp(r'[\\;,]'), (m) => '\\${m[0]}').replaceAll(_breaks, r'\n');

/// A list value split on its unescaped commas, each item unescaped.
List<String> splitText(String v) {
  final out = <String>[];
  final cur = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    final c = v[i];
    if (c == r'\' && i + 1 < v.length) {
      cur
        ..write(c)
        ..write(v[++i]);
    } else if (c == ',') {
      out.add(unescapeText(cur.toString()));
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(unescapeText(cur.toString()));
  return out;
}

/// A parameter value, quoted when it holds a character that would end it.
String paramValue(String v) => RegExp('[:;,]').hasMatch(v) ? '"${v.replaceAll('"', "'")}"' : v;

/// Folds a content line at 75 octets of UTF-8, never inside a character, with CRLF.
String fold(String line) {
  final out = StringBuffer();
  var width = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final n = utf8.encode(ch).length;
    if (width + n > 75) {
      out.write('\r\n ');
      width = 1;
    }
    out.write(ch);
    width += n;
  }
  out.write('\r\n');
  return out.toString();
}
