import 'package:flutter/material.dart';

/// Pre-processes inline `$ ... $` and block `$$ ... $$` math delimiters
/// into `\( ... \)` and `\[ ... \]` which GptMarkdown natively understands.
/// It ignores match patterns inside backtick code blocks or inline code.
String formatMath(String text) {
  final StringBuffer buffer = StringBuffer();
  int i = 0;
  final int len = text.length;

  while (i < len) {
    // Check for fenced code block (```)
    if (i + 2 < len && text[i] == '`' && text[i+1] == '`' && text[i+2] == '`') {
      buffer.write('```');
      i += 3;
      int closingIndex = text.indexOf('```', i);
      if (closingIndex != -1) {
        buffer.write(text.substring(i, closingIndex + 3));
        i = closingIndex + 3;
      } else {
        buffer.write(text.substring(i));
        i = len;
      }
      continue;
    }
    // Check for inline code (`)
    if (text[i] == '`') {
      buffer.write('`');
      i += 1;
      int closingIndex = text.indexOf('`', i);
      if (closingIndex != -1) {
        buffer.write(text.substring(i, closingIndex + 1));
        i = closingIndex + 1;
      } else {
        buffer.write(text.substring(i));
        i = len;
      }
      continue;
    }

    // Check for math block $$
    if (i + 1 < len && text[i] == '\$' && text[i+1] == '\$' && (i == 0 || text[i-1] != '\\')) {
      int closingIndex = -1;
      for (int j = i + 2; j < len - 1; j++) {
        if (text[j] == '\$' && text[j+1] == '\$' && text[j-1] != '\\') {
          closingIndex = j;
          break;
        }
      }
      if (closingIndex != -1) {
        final mathContent = text.substring(i + 2, closingIndex);
        buffer.write('\\[');
        buffer.write(mathContent);
        buffer.write('\\]');
        i = closingIndex + 2;
      } else {
        buffer.write('\$\$');
        i += 2;
      }
      continue;
    }

    // Check for inline math $
    if (text[i] == '\$' && (i == 0 || text[i-1] != '\\')) {
      int closingIndex = -1;
      for (int j = i + 1; j < len; j++) {
        if (text[j] == '\$') {
          if (text[j-1] == '\\') {
            continue;
          }
          closingIndex = j;
          break;
        }
      }

      if (closingIndex != -1 && closingIndex > i + 1) {
        final content = text.substring(i + 1, closingIndex);
        // Ensure no leading or trailing space inside the dollar signs, typical of LaTeX notation
        if (content.trim().isNotEmpty && !content.startsWith(' ') && !content.endsWith(' ')) {
          buffer.write('\\(');
          buffer.write(content);
          buffer.write('\\)');
          i = closingIndex + 1;
          continue;
        }
      }
    }

    buffer.write(text[i]);
    i++;
  }

  return buffer.toString();
}

/// Applies simple RegExp-based token styles to support code syntax highlighting.
List<TextSpan> highlightCode(String code, String lang) {
  if (code.isEmpty) {
    return [
      const TextSpan(
        text: '// Empty code block... Double tap to edit.',
        style: TextStyle(color: Color(0xFF64748B), fontStyle: FontStyle.italic),
      )
    ];
  }
  
  final List<TextSpan> spans = [];
  final keywords = {
    'function', 'return', 'if', 'else', 'for', 'while', 'const', 'let', 'var',
    'import', 'class', 'void', 'final', 'def', 'package', 'func', 'interface',
    'fn', 'mut', 'match', 'impl', 'struct', 'enum', 'pub', 'use', 'mod', 'as', 'type'
  };
  
  final regex = RegExp(
    r'("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)|(\/\/[^\n]*)|(\b\w+\b)|([^\w\x22\x27\/]+|\/)',
    multiLine: true,
  );
  
  final matches = regex.allMatches(code);
  for (final match in matches) {
    final str = match.group(1);
    final comment = match.group(2);
    final word = match.group(3);
    final other = match.group(4);
    
    if (str != null) {
      spans.add(TextSpan(text: str, style: const TextStyle(color: Color(0xFF34D399))));
    } else if (comment != null) {
      spans.add(TextSpan(text: comment, style: const TextStyle(color: Color(0xFF94A3B8), fontStyle: FontStyle.italic)));
    } else if (word != null) {
      if (keywords.contains(word)) {
        spans.add(TextSpan(text: word, style: const TextStyle(color: Color(0xFFF472B6), fontWeight: FontWeight.bold)));
      } else {
        spans.add(TextSpan(text: word, style: const TextStyle(color: Color(0xFFE2E8F0))));
      }
    } else if (other != null) {
      spans.add(TextSpan(text: other, style: const TextStyle(color: Color(0xFFCBD5E1))));
    }
  }
  
  return spans;
}
