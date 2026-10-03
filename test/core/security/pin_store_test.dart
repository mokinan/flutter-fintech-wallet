import 'package:fintech_wallet/core/security/pin_store.dart';
import 'package:fintech_wallet/core/security/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemorySecureStore store;
  late PinStore pin;

  setUp(() {
    store = InMemorySecureStore();
    pin = PinStore(store, iterations: 10, maxAttempts: 3);
  });

  test('never stores the PIN in plain text', () async {
    await pin.setPin('482915');
    expect(store.values.values, isNot(contains('482915')));
    expect(await pin.hasPin(), isTrue);
  });

  test('uses a random salt, so equal PINs hash differently', () async {
    await pin.setPin('111111');
    final first = store.values['pin_hash'];
    await pin.setPin('111111');
    expect(store.values['pin_hash'], isNot(first));
  });

  test('accepts the correct PIN and resets the failure counter', () async {
    await pin.setPin('123456');
    expect(await pin.verify('000000'), isA<PinRejected>());
    expect(await pin.verify('123456'), isA<PinAccepted>());
    expect(await pin.verify('000000'), const TypeMatcher<PinRejected>().having((r) => r.attemptsLeft, 'left', 2));
  });

  test('locks out and wipes the PIN after too many failures', () async {
    await pin.setPin('123456');
    expect(await pin.verify('1'), const TypeMatcher<PinRejected>().having((r) => r.attemptsLeft, 'left', 2));
    expect(await pin.verify('2'), const TypeMatcher<PinRejected>().having((r) => r.attemptsLeft, 'left', 1));
    expect(await pin.verify('3'), isA<PinLockedOut>());
    expect(await pin.hasPin(), isFalse);
  });

  test('the failure counter survives a restart', () async {
    await pin.setPin('123456');
    await pin.verify('1');
    await pin.verify('2');
    final restarted = PinStore(store, iterations: 10, maxAttempts: 3);
    expect(await restarted.verify('3'), isA<PinLockedOut>());
  });
}
