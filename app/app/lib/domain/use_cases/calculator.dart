/// Safe arithmetic evaluator for the model's `calculate` tool.
/// Supports + - * / ( ) and decimal numbers. No identifiers, no eval.
class Calculator {
  static double evaluate(String expression) {
    // "12,500" style thousands separators.
    final tokens = _tokenize(expression.replaceAll(',', ''));
    final rpn = _toRpn(tokens);
    return _evalRpn(rpn);
  }

  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    var i = 0;
    while (i < input.length) {
      final ch = input[i];
      if (ch == ' ') {
        i++;
      } else if ('+-*/()'.contains(ch)) {
        // Unary minus: fold into the number that follows.
        final isUnaryMinus = ch == '-' &&
            (tokens.isEmpty ||
                tokens.last == '(' ||
                '+-*/'.contains(tokens.last));
        if (isUnaryMinus) {
          final start = i;
          i++;
          while (i < input.length &&
              (_isDigit(input[i]) || input[i] == '.')) {
            i++;
          }
          if (i == start + 1) {
            throw FormatException('Dangling minus in "$input"');
          }
          tokens.add(input.substring(start, i));
        } else {
          tokens.add(ch);
          i++;
        }
      } else if (_isDigit(ch) || ch == '.') {
        final start = i;
        while (
            i < input.length && (_isDigit(input[i]) || input[i] == '.')) {
          i++;
        }
        tokens.add(input.substring(start, i));
      } else {
        throw FormatException('Unexpected character "$ch" in "$input"');
      }
    }
    return tokens;
  }

  static bool _isDigit(String ch) =>
      ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

  static const _precedence = {'+': 1, '-': 1, '*': 2, '/': 2};

  static List<String> _toRpn(List<String> tokens) {
    final output = <String>[];
    final ops = <String>[];
    for (final token in tokens) {
      if (_precedence.containsKey(token)) {
        while (ops.isNotEmpty &&
            _precedence.containsKey(ops.last) &&
            _precedence[ops.last]! >= _precedence[token]!) {
          output.add(ops.removeLast());
        }
        ops.add(token);
      } else if (token == '(') {
        ops.add(token);
      } else if (token == ')') {
        while (ops.isNotEmpty && ops.last != '(') {
          output.add(ops.removeLast());
        }
        if (ops.isEmpty) throw const FormatException('Unbalanced parentheses');
        ops.removeLast();
      } else {
        output.add(token);
      }
    }
    while (ops.isNotEmpty) {
      final op = ops.removeLast();
      if (op == '(') throw const FormatException('Unbalanced parentheses');
      output.add(op);
    }
    return output;
  }

  static double _evalRpn(List<String> rpn) {
    final stack = <double>[];
    for (final token in rpn) {
      if (_precedence.containsKey(token)) {
        if (stack.length < 2) {
          throw const FormatException('Malformed expression');
        }
        final b = stack.removeLast();
        final a = stack.removeLast();
        switch (token) {
          case '+':
            stack.add(a + b);
          case '-':
            stack.add(a - b);
          case '*':
            stack.add(a * b);
          case '/':
            if (b == 0) throw const FormatException('Division by zero');
            stack.add(a / b);
        }
      } else {
        final value = double.tryParse(token);
        if (value == null) {
          throw FormatException('Bad number "$token"');
        }
        stack.add(value);
      }
    }
    if (stack.length != 1) throw const FormatException('Malformed expression');
    return stack.single;
  }
}
