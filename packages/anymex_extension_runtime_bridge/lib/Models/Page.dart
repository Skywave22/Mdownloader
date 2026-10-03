import 'JsonX.dart';

class PageUrl {
  String url;
  Map<String, String>? headers;

  PageUrl(this.url, {this.headers});

  factory PageUrl.fromJson(Map<String, dynamic> json) {
    return PageUrl(
      strOr(json['url']).trim(),
      headers: json['headers'] == null ? null : strMapOf(json['headers']),
    );
  }

  Map<String, dynamic> toJson() => {'url': url, 'headers': headers};
}
