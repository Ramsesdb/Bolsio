import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/services/auto_import/binance/binance_api_client.dart';

void main() {
  group('BinanceApiClient.sign (HMAC-SHA256)', () {
    test('produces a 64-char lowercase hex string', () {
      const secret = 'fake_secret_for_tests';
      const queryString = 'symbol=BTCUSDT&timestamp=1499827319559';

      final signature = BinanceApiClient.sign(queryString, secret);

      expect(signature.length, 64);
      expect(signature, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('produces deterministic output for same input', () {
      const secret = 'test_secret_deterministic';
      const queryString = 'recvWindow=5000&timestamp=1712000000000';

      final sig1 = BinanceApiClient.sign(queryString, secret);
      final sig2 = BinanceApiClient.sign(queryString, secret);

      expect(sig1, sig2);
    });

    test('different secrets produce different signatures', () {
      const queryString = 'symbol=ETHUSDT&timestamp=1712000000000';

      final sig1 =
          BinanceApiClient.sign(queryString, 'fake_secret_a_for_tests');
      final sig2 =
          BinanceApiClient.sign(queryString, 'fake_secret_b_for_tests');

      expect(sig1, isNot(sig2));
    });

    test('different query strings produce different signatures', () {
      const secret = 'fake_shared_secret_for_tests';

      final sig1 =
          BinanceApiClient.sign('timestamp=1000000000000', secret);
      final sig2 =
          BinanceApiClient.sign('timestamp=2000000000000', secret);

      expect(sig1, isNot(sig2));
    });

    test('known test vector matches expected HMAC-SHA256', () {
      // Pre-computed vector:
      // secret = 'NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j'
      // queryString = 'symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559'
      // (from Binance API docs example)
      const secret =
          'NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j';
      const queryString =
          'symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559';

      final signature = BinanceApiClient.sign(queryString, secret);

      // Expected value from Binance official documentation:
      expect(
        signature,
        'c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71',
      );
    });
  });
}
