import 'dart:math';

import 'proxy_config.dart';

class NoProxyAvailableException implements Exception {
  const NoProxyAvailableException();

  @override
  String toString() {
    return 'no proxy available';
  }
}

const errNoProxyAvailable = NoProxyAvailableException();

abstract interface class ProxyPicker {
  ProxyConfig pick();
}

class RoundRobinProxyPicker implements ProxyPicker {
  final List<ProxyConfig> _proxies;
  int _index = 0;

  RoundRobinProxyPicker(List<ProxyConfig> proxies)
    : _proxies = List<ProxyConfig>.unmodifiable(proxies);

  @override
  ProxyConfig pick() {
    if (_proxies.isEmpty) {
      throw errNoProxyAvailable;
    }

    final proxy = _proxies[_index % _proxies.length];
    _index++;

    return proxy;
  }
}

class RandomProxyPicker implements ProxyPicker {
  final List<ProxyConfig> _proxies;
  final Random _rng;

  RandomProxyPicker(List<ProxyConfig> proxies, {Random? rng})
    : _proxies = List<ProxyConfig>.unmodifiable(proxies),
      _rng = rng ?? Random();

  @override
  ProxyConfig pick() {
    if (_proxies.isEmpty) {
      throw errNoProxyAvailable;
    }

    return _proxies[_rng.nextInt(_proxies.length)];
  }
}

class SingleProxyPicker implements ProxyPicker {
  final ProxyConfig? _proxy;

  const SingleProxyPicker(this._proxy);

  @override
  ProxyConfig pick() {
    if (_proxy == null) {
      throw errNoProxyAvailable;
    }

    return _proxy;
  }
}
