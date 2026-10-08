import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'local_store.dart';

bool hasHangul(String value) => RegExp(r'[가-힣]').hasMatch(value);

/// Only use a Korean name verified against the same NSUID. Never translate a
/// title heuristically: English-only official names remain English.
class KoreanTitleResolver {
  KoreanTitleResolver(this.dio, this.store);
  final Dio dio;
  final LocalStore store;

  static String? parseOfficialTitle(String body, String id) {
    final document = html.parse(body);
    final canonical = document
        .querySelector('link[rel="canonical"]')
        ?.attributes['href'];
    final uri = canonical == null ? null : Uri.tryParse(canonical);
    if (uri == null ||
        uri.host != 'store.nintendo.co.kr' ||
        !uri.pathSegments.contains(id)) {
      return null;
    }
    final title =
        document.querySelector('h1.page-title .base')?.text.trim() ??
        document
            .querySelector('meta[property="og:title"]')
            ?.attributes['content']
            ?.trim();
    return title != null && hasHangul(title) && title.length <= 200
        ? title
        : null;
  }

  Future<String> resolve(String id, String fallback) async {
    if (hasHangul(fallback)) return fallback;
    final saved = store.readKoreanTitle(id);
    if (saved != null && hasHangul(saved)) return saved;
    try {
      final response = await dio.get<String>(
        'https://store.nintendo.co.kr/$id',
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );
      final title = parseOfficialTitle(response.data ?? '', id);
      if (title != null) {
        await store.saveKoreanTitle(id, title);
        return title;
      }
    } on Object {
      // An optional title lookup cannot take down the sales/price workflow.
    }
    return fallback;
  }
}
