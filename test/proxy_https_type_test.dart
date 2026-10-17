import 'package:deskaone_sdk/deskaone_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('proxy schemes match Go types including distinct HTTPS', () {
    for (final value in ['http', 'https', 'socks4', 'socks5']) {
      final config = ProxyConfig.fromUrlString('$value://localhost:8080');
      expect(config.type.value, value);
    }
    expect(ProxyType.fromString('HTTPS'), ProxyType.https);
    expect(ProxyType.fromString('s4'), ProxyType.socks4);
    expect(ProxyType.fromString('s5'), ProxyType.socks5);
  });

  test('proxy URLs must have explicit ports', () {
    expect(
      () => ProxyConfig.fromUrlString('https://proxy.example.com'),
      throwsFormatException,
    );
  });

  test('proxy passwords are masked in display strings', () {
    final config = ProxyConfig.fromUrlString(
      'https://user:secret@proxy.example.com:8443',
    );
    expect(config.toString(), contains('user:***@'));
    expect(config.toString(), isNot(contains('secret')));
    expect(config.toUrlString(), contains('secret'));
  });

  test('proxy pickers support HTTPS without changing picker contracts', () {
    final config = ProxyConfig.fromUrlString('https://localhost:8443');
    expect(SingleProxyPicker(config).pick().type, ProxyType.https);
    expect(RoundRobinProxyPicker([config]).pick().type, ProxyType.https);
  });
}
