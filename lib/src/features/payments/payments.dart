import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets.dart';
import '../../core/app_theme.dart';
import '../auth/data/auth_repository.dart';
import '../catalog/application/catalog_providers.dart';
import 'review_photos.dart';
import 'checkout_widgets.dart';

part 'order_details.dart';

String pesos(num cents) => NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
).format(cents / 100);

String checkoutKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String paymentStatus(String status) => switch (status) {
  'creating' || 'creation_unknown' => 'Confirming checkout',
  'payment_pending' => 'Awaiting payment',
  'paid' => 'Paid',
  'cod_pending' => 'Unpaid',
  'expired' => 'Checkout expired',
  'cancelled' => 'Cancelled',
  'failed' => 'Checkout failed',
  'payment_review' => 'Payment needs review',
  'refund_pending' => 'Refund processing',
  'refunded' => 'Refunded',
  'refund_failed' => 'Refund needs review',
  _ => 'Checking payment',
};

String deliveryStatus(Map<String, dynamic> order) {
  if (['cancelled', 'expired', 'failed'].contains(order['status'])) {
    return paymentStatus(order['status'] as String);
  }
  if ([
    'refund_pending',
    'refunded',
    'refund_failed',
    'payment_review',
    'creating',
    'creation_unknown',
  ].contains(order['status'])) {
    return paymentStatus(order['status'] as String);
  }
  if (order['fulfillment'] == 'pickup_demo' && order['status'] == 'paid') {
    return 'Paid · Pickup order';
  }
  return switch (order['fulfillment_status']) {
    'delivered' => 'Completed',
    'shipped' => 'Out for delivery',
    _ => order['status'] == 'payment_pending' ? 'Awaiting payment' : 'To ship',
  };
}

String orderSummary(Map<String, dynamic> order) => {
  order['fulfillment'] == 'pickup_demo' && order['status'] == 'paid'
      ? 'Pickup order'
      : deliveryStatus(order),
  paymentStatus(order['status'] as String),
  order['payment_method'] == 'cod' ? 'Cash on delivery' : 'Online payment',
}.join(' · ');

class PaymentRepository {
  PaymentRepository(this.client);
  final SupabaseClient? client;
  SupabaseClient get _client =>
      client ?? (throw StateError('Connect Supabase first.'));
  Future<Map<String, dynamic>?> savedAddress() async {
    final row = await _client
        .from('delivery_addresses')
        .select('address')
        .eq('buyer_id', _client.auth.currentUser!.id)
        .maybeSingle();
    return row == null
        ? null
        : Map<String, dynamic>.from(row['address'] as Map);
  }

  Future<void> saveAddress(Map<String, dynamic> address) async {
    await _client.rpc('save_delivery_address', params: {'p_shipping': address});
  }

  Future<String> uploadReviewPhoto(
    String orderId,
    Uint8List bytes,
    String extension,
  ) async {
    final path = '$orderId/${checkoutKey()}.$extension';
    await _client.storage
        .from('review-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: extension == 'jpg' ? 'image/jpeg' : 'image/$extension',
          ),
        );
    return path;
  }

  Future<Map<String, dynamic>> call(
    String function,
    Map<String, dynamic> body,
  ) async {
    try {
      final result = await _client.functions.invoke(function, body: body);
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['error'] != null && data['order'] == null) {
        throw StateError(data['error'] as String);
      }
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      throw StateError(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'Could not reach checkout. Check Orders before trying again.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> orders() async =>
      List<Map<String, dynamic>>.from(
        await _client
            .from('orders')
            .select(
              'id,product_name,quantity,total_centavos,status,created_at,payment_method,fulfillment_status,fulfillment',
            )
            .eq('buyer_id', _client.auth.currentUser!.id)
            .order('created_at', ascending: false)
            .limit(50),
      );
  Future<Map<String, dynamic>?> sellerProfile() async => await _client
      .from('seller_profiles')
      .select('id,shop_name,status')
      .eq('id', _client.auth.currentUser!.id)
      .maybeSingle();
  Future<List<Map<String, dynamic>>> sellerOrders() async =>
      List<Map<String, dynamic>>.from(
        await _client
            .from('orders')
            .select(
              'id,product_name,quantity,total_centavos,status,created_at,payment_method,fulfillment_status,fulfillment',
            )
            .eq('seller_id', _client.auth.currentUser!.id)
            .order('created_at', ascending: false)
            .limit(100),
      );
  Future<Map<String, dynamic>> reviews(String productId) async =>
      Map<String, dynamic>.from(
        await _client.rpc(
          'product_review_summary',
          params: {'p_product': productId},
        ) as Map,
      );
  Future<List<Map<String, dynamic>>> cart() async =>
      List<Map<String, dynamic>>.from(
        await _client
            .from('cart_items')
            .select(
              'product_id,quantity,products(id,name,price_centavos,stock)',
            )
            .eq('buyer_id', _client.auth.currentUser!.id),
      );
  Future<void> addToCart(String id) => _client.from('cart_items').upsert({
    'buyer_id': _client.auth.currentUser!.id,
    'product_id': id,
    'quantity': 1,
  });
  Future<void> removeFromCart(String id) => _client
      .from('cart_items')
      .delete()
      .eq('buyer_id', _client.auth.currentUser!.id)
      .eq('product_id', id);
}

final paymentRepositoryProvider = Provider(
  (ref) => PaymentRepository(ref.watch(supabaseClientProvider)),
);
final savedAddressProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(currentUserProvider).asData?.value == null) return null;
  return ref.watch(paymentRepositoryProvider).savedAddress();
});
final ordersProvider = FutureProvider.autoDispose((ref) async {
  final account = ref.watch(currentUserProvider).asData?.value;
  if (account == null) return <Map<String, dynamic>>[];
  return ref.watch(paymentRepositoryProvider).orders();
});
final sellerProfileProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(currentUserProvider).asData?.value == null) return null;
  return ref.watch(paymentRepositoryProvider).sellerProfile();
});
final sellerOrdersProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(currentUserProvider).asData?.value == null) {
    return <Map<String, dynamic>>[];
  }
  return ref.watch(paymentRepositoryProvider).sellerOrders();
});
final productReviewsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      return ref.watch(paymentRepositoryProvider).reviews(id);
    });
final cartProvider = FutureProvider.autoDispose((ref) async {
  final account = ref.watch(currentUserProvider).asData?.value;
  if (account == null) return <Map<String, dynamic>>[];
  return ref.watch(paymentRepositoryProvider).cart();
});
final quoteProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, (String, int)>((ref, args) {
      ref.watch(currentUserProvider);
      return ref.watch(paymentRepositoryProvider).call('checkout-quote', {
        'product_id': args.$1,
        'quantity': args.$2,
      });
    });
final orderProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final account = ref.watch(currentUserProvider).asData?.value;
      if (account == null) throw StateError('Sign in to view this order.');
      return ref.watch(paymentRepositoryProvider).call('commerce-order', {
        'action': 'get',
        'order_id': id,
      });
    });

Future<void> openCheckout(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !(uri.host == 'xen.to' ||
          uri.host == 'dev.xen.to' ||
          uri.host.endsWith('.xendit.co')) ||
      uri.userInfo.isNotEmpty) {
    throw StateError('Unexpected checkout link.');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError(
      'Could not open the browser. Reopen checkout from Orders.',
    );
  }
}

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.productId});
  final String productId;
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutState();
}

class _CheckoutState extends ConsumerState<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  final _recipient = TextEditingController(),
      _phone = TextEditingController(),
      _address = TextEditingController(),
      _city = TextEditingController(),
      _postal = TextEditingController();
  String _method = 'cod';
  int _quantity = 1;
  bool _quantityValid = true;
  Map<String, dynamic>? _lastQuote;
  bool _busy = false;
  bool _editingAddress = true;
  bool _savingAddress = false;
  String? _addressAccount;
  Map<String, dynamic>? _savedAddress;
  String? _error;
  String _key = checkoutKey();
  @override
  void didUpdateWidget(covariant CheckoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      _lastQuote = null;
      _quantity = 1;
      _quantityValid = true;
      _key = checkoutKey();
    }
  }

  Map<String, dynamic> get _shipping => {
    'recipient': _recipient.text.trim(),
    'phone': _phone.text.trim(),
    'address': _address.text.trim(),
    'city': _city.text.trim(),
    'postal_code': _postal.text.trim(),
  };
  void _useAddress(Map<String, dynamic> address) {
    _recipient.text = address['recipient'] as String? ?? '';
    _phone.text = address['phone'] as String? ?? '';
    _address.text = address['address'] as String? ?? '';
    _city.text = address['city'] as String? ?? '';
    _postal.text = address['postal_code'] as String? ?? '';
    _key = checkoutKey();
  }

  Future<void> _saveAddress() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _savingAddress = true);
    try {
      final address = _shipping;
      await ref.read(paymentRepositoryProvider).saveAddress(address);
      if (!mounted) return;
      setState(() {
        _savedAddress = address;
        _editingAddress = false;
        _key = checkoutKey();
      });
      ref.invalidate(savedAddressProvider);
      showNotice(context, 'Delivery address saved.');
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Could not save your address. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingAddress = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [_recipient, _phone, _address, _city, _postal]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pay(Map<String, dynamic> quote) async {
    if (!_quantityValid || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(paymentRepositoryProvider).call(
        _method == 'cod' ? 'commerce-order' : 'checkout-create',
        {
          if (_method == 'cod') 'action': 'create_cod',
          'product_id': widget.productId,
          'quantity': _quantity,
          'idempotency_key': _key,
          'expected_unit_price_centavos': quote['unit_price_centavos'],
          'shipping_address': _shipping,
        },
      );
      if (!mounted) return;
      final order = Map<String, dynamic>.from(result['order'] as Map);
      ref.invalidate(ordersProvider);
      ref.invalidate(cartProvider);
      ref.invalidate(productProvider(widget.productId));
      context.go('/orders/${order['id']}');
      final link = order['payment_link_url'];
      if (link is String && order['status'] == 'payment_pending') {
        try {
          await openCheckout(link);
        } catch (_) {
          /* The order screen can reopen checkout. */
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Bad state: ', '');
        });
        ref.invalidate(ordersProvider);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).asData?.value;
    // Establish identity before the address request completes so a slow
    // response cannot erase a draft the buyer has already started typing.
    _addressAccount ??= user?.id;
    ref.listen(savedAddressProvider, (previous, next) {
      final account = ref.read(currentUserProvider).asData?.value?.id;
      if (account != _addressAccount) {
        _addressAccount = account;
        _savedAddress = null;
        _useAddress({});
        _editingAddress = true;
      }
      if (next.hasValue && next.value != null && _savedAddress == null) {
        setState(() {
          _savedAddress = next.value;
          // Do not overwrite an address the buyer has already started typing.
          if ([
            _recipient,
            _phone,
            _address,
            _city,
            _postal,
          ].every((c) => c.text.isEmpty)) {
            _useAddress(next.value!);
            _editingAddress = false;
          }
        });
      }
    });
    final savedAddress = ref.watch(savedAddressProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/cart'),
        title: const Text('Review your order'),
      ),
      body: user == null
          ? AuthPrompt(
              title: 'Sign in to checkout',
              next: '/checkout/${widget.productId}',
              icon: Icons.lock_outline,
            )
          : _checkoutBody(
              ref.watch(quoteProvider((widget.productId, _quantity))),
              savedAddress,
            ),
    );
  }

  Widget _checkoutBody(
    AsyncValue<Map<String, dynamic>> quoteState,
    AsyncValue<Map<String, dynamic>?> savedAddress,
  ) {
    final latest = quoteState.asData?.value;
    if (latest != null) _lastQuote = latest;
    final quote = latest ?? _lastQuote;
    if (quote == null) {
      return quoteState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => InfoPanel(
          icon: Icons.shopping_bag_outlined,
          title: 'Checkout unavailable',
          message: error.toString().replaceFirst('Bad state: ', ''),
          action: OutlinedButton(
            onPressed: () =>
                ref.invalidate(quoteProvider((widget.productId, _quantity))),
            child: const Text('Try again'),
          ),
        ),
        data: (_) => const SizedBox.shrink(),
      );
    }
    final locked = _busy || _savingAddress;
    final quoteReady =
        latest != null && !quoteState.isLoading && !quoteState.hasError;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF1FF), Color(0xFFF3F6FB)],
        ),
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF163D91), Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.shopping_bag_outlined,
                          color: Color(0xFFBFD5FF),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'YOUR ORDER',
                          style: TextStyle(
                            color: Color(0xFFD8E6FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      quote['product_name'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${pesos(quote['unit_price_centavos'] as num)} each',
                      style: const TextStyle(
                        color: Color(0xFFD8E6FF),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE0E8F3)),
                ),
                child: QuantityInput(
                  key: ValueKey('quantity-${widget.productId}'),
                  value: _quantity,
                  enabled: !locked,
                  onValidityChanged: (valid) {
                    if (valid != _quantityValid) {
                      setState(() => _quantityValid = valid);
                    }
                  },
                  onChanged: (value) {
                    if (value == _quantity) return;
                    setState(() {
                      _quantity = value;
                      _key = checkoutKey();
                      _error = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              CheckoutSection(
                title: 'Deliver to',
                icon: Icons.location_on_outlined,
                children: [
                  if (savedAddress.isLoading) const LinearProgressIndicator(),
                  if (savedAddress.hasError)
                    TextButton.icon(
                      onPressed: () => ref.invalidate(savedAddressProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry loading saved address'),
                    ),
                  if (_savedAddress != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F6FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _savedAddress!['recipient'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _savedAddress!['phone'] as String,
                            style: const TextStyle(color: Color(0xFF52647C)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_savedAddress!['address']}\n${_savedAddress!['city']} ${_savedAddress!['postal_code']}',
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: locked
                              ? null
                              : () => setState(() {
                                  _useAddress(_savedAddress!);
                                  _editingAddress = false;
                                }),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 17,
                          ),
                          label: const Text('Use current address'),
                        ),
                        TextButton(
                          onPressed: locked
                              ? null
                              : () => setState(() => _editingAddress = true),
                          child: const Text('Update address'),
                        ),
                      ],
                    ),
                  ],
                  if (_editingAddress) ...[
                    TextFormField(
                      key: const Key('shipping-recipient'),
                      controller: _recipient,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'Recipient name',
                        hintText: 'Juan Dela Cruz',
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) =>
                          (value?.trim().length ?? 0) < 2 ||
                              value!.trim().length > 100
                          ? 'Enter a name between 2 and 100 characters.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('shipping-phone'),
                      controller: _phone,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'Contact number',
                        hintText: '09XXXXXXXXX',
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) =>
                          !RegExp(r'^\+?[0-9][0-9 -]{8,18}$')
                              .hasMatch(value?.trim() ?? '')
                          ? 'Enter a valid contact number.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('shipping-address'),
                      controller: _address,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'House, street and barangay',
                        hintText: '123 Sample Street, Barangay Demo',
                      ),
                      minLines: 2,
                      maxLines: 3,
                      validator: (value) =>
                          (value?.trim().length ?? 0) < 8 ||
                              value!.trim().length > 400
                          ? 'Enter a complete street address (8–400 characters).'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('shipping-city'),
                      controller: _city,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'City / municipality and province',
                        hintText: 'Quezon City, Metro Manila',
                      ),
                      validator: (value) =>
                          (value?.trim().length ?? 0) < 2 ||
                              value!.trim().length > 100
                          ? 'Enter your city and province.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('shipping-postal'),
                      controller: _postal,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'Postal code',
                        hintText: '1100',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) =>
                          !RegExp(r'^\d{4}$').hasMatch(value?.trim() ?? '')
                          ? 'Enter a four-digit postal code.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: locked ? null : _saveAddress,
                      icon: const Icon(Icons.location_on_outlined),
                      label: Text(
                        _savingAddress
                            ? 'Saving address…'
                            : 'Save delivery address',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              CheckoutSection(
                title: 'How would you like to pay?',
                icon: Icons.account_balance_wallet_outlined,
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('payment-method'),
                    isExpanded: true,
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'cod',
                        child: Text('Cash on delivery'),
                      ),
                      DropdownMenuItem(
                        value: 'xendit',
                        child: Text('Online payment'),
                      ),
                    ],
                    onChanged: locked
                        ? null
                        : (value) => setState(() {
                            _method = value!;
                            _key = checkoutKey();
                          }),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _method == 'cod'
                        ? 'Pay the courier when your item arrives. Confirm receipt in Orders after receiving your purchase and paying cash.'
                        : 'Complete your online payment, then return to the app. Your order shows Paid once payment is confirmed.',
                    style: const TextStyle(
                      color: Color(0xFF52647C),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CheckoutSection(
                title: 'Order summary',
                icon: Icons.receipt_long_outlined,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Items × $_quantity',
                          style: const TextStyle(color: Color(0xFF52647C)),
                        ),
                      ),
                      Text(
                        quoteReady
                            ? pesos(quote['total_centavos'] as num)
                            : '—',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Delivery: Free',
                        style: TextStyle(
                          color: Color(0xFF087F60),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Icons.local_shipping_outlined,
                        color: Color(0xFF087F60),
                        size: 20,
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  if (quoteState.isLoading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 10),
                    const Text(
                      'Updating total…',
                      style: TextStyle(color: Color(0xFF52647C)),
                    ),
                  ] else if (quoteState.hasError) ...[
                    Text(
                      quoteState.error.toString().replaceFirst(
                        'Bad state: ',
                        '',
                      ),
                      style: const TextStyle(color: Color(0xFFB42318)),
                    ),
                    TextButton.icon(
                      onPressed: () => ref.invalidate(
                        quoteProvider((widget.productId, _quantity)),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry total'),
                    ),
                  ] else
                    Text(
                      'Total: ${pesos(quote['total_centavos'] as num)}',
                      style: const TextStyle(
                        color: blue,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFB42318)),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: locked || !_quantityValid || !quoteReady
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            _pay(quote);
                          },
                    child: Text(
                      _busy
                          ? 'Placing your order…'
                          : _method == 'cod'
                          ? 'Place order · Cash on delivery'
                          : 'Continue to payment',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => context.go('/orders'),
                child: const Text('View existing orders'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersState();
}

class _OrdersState extends ConsumerState<OrdersScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(ordersProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentUserProvider).asData?.value == null) {
      return const AuthPrompt(
        title: 'Your orders, all together.',
        next: '/orders',
        icon: Icons.inventory_2_outlined,
      );
    }
    return ref
        .watch(ordersProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => InfoPanel(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load orders',
            message: 'Check your connection and try again.',
            action: FilledButton(
              onPressed: () => ref.invalidate(ordersProvider),
              child: const Text('Try again'),
            ),
          ),
          data: (orders) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(ordersProvider);
              await ref.read(ordersProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Your orders',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Track your purchases, delivery updates and reviews.',
                ),
                if (orders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No orders yet. Choose a part and tap Buy now.',
                    ),
                  ),
                for (final order in orders)
                  Card(
                    child: ListTile(
                      title: Text(order['product_name'] as String),
                      subtitle: Text(
                        '${orderSummary(order)}\n${order['quantity']} item(s) · ${pesos(order['total_centavos'] as num)}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/orders/${order['id']}'),
                    ),
                  ),
              ],
            ),
          ),
        );
  }
}

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserProvider).asData?.value == null) {
      return const AuthPrompt(
        title: 'Your cart, all together.',
        next: '/cart',
        icon: Icons.shopping_bag_outlined,
      );
    }
    return ref
        .watch(cartProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => InfoPanel(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load cart',
            message: 'Check your connection and try again.',
            action: FilledButton(
              onPressed: () => ref.invalidate(cartProvider),
              child: const Text('Try again'),
            ),
          ),
          data: (items) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Your cart',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Review each item, choose a delivery address and select how to pay.',
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Your cart is empty. Explore parts to add a listing.',
                  ),
                ),
              for (final item in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Builder(
                      builder: (context) {
                        final product = item['products'] as Map?;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product?['name'] as String? ??
                                  'Listing unavailable',
                            ),
                            if (product != null)
                              Text(pesos(product['price_centavos'] as num)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              children: [
                                if (product != null)
                                  FilledButton(
                                    onPressed: () => context.push(
                                      '/checkout/${item['product_id']}',
                                    ),
                                    child: const Text('Review checkout'),
                                  ),
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(paymentRepositoryProvider)
                                          .removeFromCart(
                                            item['product_id'] as String,
                                          );
                                      ref.invalidate(cartProvider);
                                    } catch (_) {
                                      if (context.mounted) {
                                        showNotice(
                                          context,
                                          'Could not remove this item. Try again.',
                                        );
                                      }
                                    }
                                  },
                                  child: const Text('Remove'),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
  }
}
