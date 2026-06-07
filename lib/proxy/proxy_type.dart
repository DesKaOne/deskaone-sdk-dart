enum ProxyType {
  http("http"),
  socks4("socks4"),
  socks5("socks5");

  final String value;

  const ProxyType(this.value);

  factory ProxyType.fromString(String s) {
    final value = s.toLowerCase().trim();
    if (value == "http" || value == "https") {
      return ProxyType.http;
    }
    if (value == "s4" || value == "sock4" || value == "socks4") {
      return ProxyType.socks4;
    }
    if (value == "s54" || value == "sock5" || value == "socks5") {
      return ProxyType.socks5;
    }
    throw Exception("invalid proxy type: $s");
  }

  @override
  String toString() {
    return value;
  }
}
