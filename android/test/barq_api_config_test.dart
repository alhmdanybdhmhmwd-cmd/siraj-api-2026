import 'package:flutter_test/flutter_test.dart';
import 'package:barq/barq_api_config.dart';

void main() {
  test('defaults BARQ API traffic to the public Vercel gateway', () {
    expect(resolveBarqApiBase(''), defaultBarqApiBase);
    expect(resolveBarqApiBase('   '), defaultBarqApiBase);
  });

  test('rejects direct workers.dev and insecure API overrides', () {
    expect(
      resolveBarqApiBase('https://siraj-api.alhmdanybdhmhmwd.workers.dev'),
      defaultBarqApiBase,
    );
    expect(
      resolveBarqApiBase('https://preview.workers.dev/api'),
      defaultBarqApiBase,
    );
    expect(resolveBarqApiBase('http://api.example.com'), defaultBarqApiBase);
  });

  test('accepts a separate public HTTPS gateway for isolated environments', () {
    expect(
      resolveBarqApiBase('https://preview-api.example.com'),
      'https://preview-api.example.com',
    );
  });

  test('rejects URLs containing credentials, query strings, or fragments', () {
    expect(
      resolveBarqApiBase('https://user:pass@api.example.com'),
      defaultBarqApiBase,
    );
    expect(
      resolveBarqApiBase('https://api.example.com?token=secret'),
      defaultBarqApiBase,
    );
    expect(
      resolveBarqApiBase('https://api.example.com#fragment'),
      defaultBarqApiBase,
    );
  });
}
