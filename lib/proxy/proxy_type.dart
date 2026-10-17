enum ProxyType {
  http("http"),
  https("https"),
  socks4("socks4"),
  socks5("socks5");

  final String value;

  const ProxyType(this.value);

  factory ProxyType.fromString(String s) {
    final value = s.toLowerCase().trim();

    switch (value) {
      case 'http':
        return ProxyType.http;

      case 'https':
        return ProxyType.https;

      case 's4':
      case 'sock4':
      case 'socks4':
        return ProxyType.socks4;

      case 's5':
      case 'sock5':
      case 'socks5':
        return ProxyType.socks5;

      default:
        throw FormatException('invalid proxy type: $s');
    }
  }

  @override
  String toString() {
    return value;
  }
}
