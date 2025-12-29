import 'dart:convert';
import 'package:http/http.dart' as http;

class GrammarService {
  final String apiUrl = 'http://localhost:8000/fix';

  Future<String?> fixGrammar(String text) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print(data);
        return data['output'] as String?;
      }
    } catch (e) {
      print('Error calling grammar service: $e');
    }
    return null;
  }
}
