part of 'payments.dart';

class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<OrderScreen> createState() => _OrderState();
}

class _OrderState extends ConsumerState<OrderScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
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

  void _refresh() {
    ref.invalidate(orderProvider(widget.id));
    ref.invalidate(ordersProvider);
    ref.invalidate(sellerOrdersProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<bool> _operate(
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await ref.read(paymentRepositoryProvider).call(
        action == 'cancel_online' ? 'order-cancel' : 'commerce-order',
        {
          'order_id': widget.id,
          if (action != 'cancel_online') 'action': action,
          ...extra,
        },
      );
      if (!mounted) return true;
      _refresh();
      ref.invalidate(productReviewsProvider);
      ref.invalidate(catalogProvider);
      if (mounted) {
        showNotice(
          context,
          action == 'review' ? 'Thank you for your review.' : 'Order updated.',
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        showNotice(context, error.toString().replaceFirst('Bad state: ', ''));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dispatch() async {
    final courier = TextEditingController(), tracking = TextEditingController();
    final form = GlobalKey<FormState>();
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ModalTitle('Dispatch this order'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter the delivery details after handing the parcel to your courier.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: courier,
                  decoration: const InputDecoration(
                    labelText: 'Courier / delivery service',
                  ),
                  validator: (value) =>
                      (value?.trim().length ?? 0) < 2 ||
                          value!.trim().length > 100
                      ? 'Enter the courier name (2–100 characters).'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: tracking,
                  decoration: const InputDecoration(
                    labelText: 'Tracking / waybill number',
                  ),
                  validator: (value) =>
                      (value?.trim().length ?? 0) < 3 ||
                          value!.trim().length > 100
                      ? 'Enter a tracking number (3–100 characters).'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(dialogContext, {
                  'courier': courier.text.trim(),
                  'tracking_number': tracking.text.trim(),
                });
              }
            },
            child: const Text('Mark out for delivery'),
          ),
        ],
      ),
    );
    // Dispose after the dialog's reverse animation releases its text fields.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    courier.dispose();
    tracking.dispose();
    if (mounted && values != null) await _operate('dispatch', values);
  }

  Future<void> _receive(Map<String, dynamic> order) async {
    final cash = order['payment_method'] == 'cod';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ModalTitle('Confirm item received'),
        content: Text(
          cash
              ? 'Confirm that your item arrived and you paid ${pesos(order['total_centavos'] as num)} in cash to the courier.'
              : 'Confirm that this item has arrived and you have received your purchase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(cash ? 'I received it and paid' : 'I received my item'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) await _operate('receive');
  }

  Future<void> _cancel(bool cash) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ModalTitle('Cancel this order?'),
        content: const Text(
          'Your order can be cancelled before dispatch. Reserved stock will be returned when cancellation is confirmed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await _operate(cash ? 'cancel' : 'cancel_online');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: AppBackButton(
        fallback:
            ref.watch(orderProvider(widget.id)).asData?.value['role'] ==
                'seller'
            ? '/selling'
            : '/orders',
      ),
      title: const Text('Order details'),
    ),
    body: ref.watch(currentUserProvider).asData?.value == null
        ? AuthPrompt(
            title: 'Sign in to view your order',
            next: '/orders/${widget.id}',
            icon: Icons.lock_outline,
          )
        : ref
              .watch(orderProvider(widget.id))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => InfoPanel(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load this order',
                  message: error.toString().replaceFirst('Bad state: ', ''),
                  action: FilledButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ),
                data: (result) {
                  final order = Map<String, dynamic>.from(
                    result['order'] as Map,
                  );
                  final status = order['status'] as String;
                  final cash = order['payment_method'] == 'cod';
                  final seller = result['role'] == 'seller';
                  final delivery = order['fulfillment'] == 'delivery';
                  final stage =
                      order['fulfillment_status'] as String? ?? 'processing';
                  final address = order['shipping_address'] as Map?;
                  final review = result['review'] as Map?;
                  final events = result['events'] as List? ?? [];
                  final ready = ['paid', 'cod_pending'].contains(status);
                  return RefreshIndicator(
                    onRefresh: () async {
                      _refresh();
                      await ref.read(orderProvider(widget.id).future);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(
                              label: Text(
                                cash ? 'Cash on delivery' : 'Online payment',
                              ),
                            ),
                            if (status == 'paid' ||
                                paymentStatus(status) != deliveryStatus(order))
                              Chip(
                                avatar: status == 'paid'
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: Color(0xFF247150),
                                        size: 18,
                                      )
                                    : null,
                                label: Text(paymentStatus(status)),
                              ),
                            if (seller) const Chip(label: Text('Seller order')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          deliveryStatus(order),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          cash && status == 'cod_pending'
                              ? 'Pay the courier when your order arrives.'
                              : status == 'paid'
                              ? cash
                                    ? 'Cash payment confirmed by the buyer.'
                                    : 'Online payment received.'
                              : 'Your latest order status is shown above.',
                        ),
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.memory_rounded,
                                  color: Color(0xFF2457D6),
                                  size: 34,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  order['product_name'] as String,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${order['quantity']} item(s) · ${pesos(order['total_centavos'] as num)}',
                                ),
                                const SizedBox(height: 8),
                                const Text('Delivery: Free'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          'Order: ${order['id']}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (order['created_at'] != null)
                          Text(
                            'Placed ${DateFormat.yMMMd().add_jm().format(DateTime.parse(order['created_at'] as String).toLocal())}',
                          ),
                        const SizedBox(height: 24),
                        if (delivery && ready) _DeliveryProgress(stage: stage),
                        if (address != null) ...[
                          const SizedBox(height: 20),
                          Text(
                            'Delivery address',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('${address['recipient']} · ${address['phone']}'),
                          Text(
                            '${address['address']}\n${address['city']} ${address['postal_code']}',
                          ),
                        ],
                        if (order['courier'] != null) ...[
                          const SizedBox(height: 20),
                          Text(
                            'Delivery tracking',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(order['courier'] as String),
                          SelectableText(
                            'Tracking: ${order['tracking_number']}',
                          ),
                        ],
                        if (result['refresh_delayed'] == true)
                          const Text(
                            'Payment refresh is delayed. Your last confirmed status is shown.',
                          ),
                        if ([
                          'creation_unknown',
                          'creating',
                          'payment_review',
                        ].contains(status))
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'We are checking this payment. Do not pay again or create a replacement order. Refresh the status or contact support with your order ID.',
                            ),
                          ),
                        if (seller &&
                            delivery &&
                            ready &&
                            stage == 'processing') ...[
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _busy ? null : _dispatch,
                            icon: const Icon(Icons.local_shipping_outlined),
                            label: const Text('Mark out for delivery'),
                          ),
                        ],
                        if (!seller && ready && stage == 'shipped') ...[
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            key: const Key('order-receive'),
                            onPressed: _busy ? null : () => _receive(order),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Mark as received'),
                          ),
                        ],
                        if (!seller &&
                            status == 'payment_pending' &&
                            order['payment_link_url'] is String) ...[
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    try {
                                      await openCheckout(
                                        order['payment_link_url'] as String,
                                      );
                                    } catch (_) {
                                      if (context.mounted) {
                                        showNotice(
                                          context,
                                          'Could not open checkout. Try again.',
                                        );
                                      }
                                    }
                                  },
                            child: const Text('Continue online payment'),
                          ),
                        ],
                        if (review != null) ...[
                          const SizedBox(height: 24),
                          Text(
                            seller ? 'Buyer review' : 'Your review',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${'★' * (review['rating'] as num).toInt()} · ${review['reviewer_name']}',
                          ),
                          const SizedBox(height: 6),
                          Text(review['review_notes'] as String),
                          ReviewPhotos(
                            paths: List<String>.from(
                              review['photo_paths'] as List? ?? [],
                            ),
                          ),
                        ] else if (!seller &&
                            stage == 'delivered' &&
                            status == 'paid') ...[
                          const SizedBox(height: 24),
                          _PurchaseReviewForm(
                            orderId: widget.id,
                            busy: _busy,
                            onSubmit: (rating, notes, photos) =>
                                _operate('review', {
                                  'rating': rating,
                                  'review_notes': notes,
                                  'photo_paths': photos,
                                }),
                          ),
                        ],
                        if (events.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          Text(
                            'Order activity',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          for (final event in events.reversed)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(switch (event['event']) {
                                'received' => Icons.check_circle_outline,
                                'shipped' => Icons.local_shipping_outlined,
                                'cancelled' => Icons.cancel_outlined,
                                _ => Icons.receipt_long_outlined,
                              }),
                              title: Text(switch (event['event']) {
                                'received' => 'Item received',
                                'shipped' => 'Out for delivery',
                                'cancelled' => 'Order cancelled',
                                _ => 'Order placed',
                              }),
                              subtitle: Text(
                                '${event['note']}\n${DateFormat.MMMd().add_jm().format(DateTime.parse(event['created_at'] as String).toLocal())}',
                              ),
                            ),
                        ],
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: _busy ? null : _refresh,
                          child: Text(
                            cash ? 'Refresh order' : 'Refresh payment status',
                          ),
                        ),
                        if (cash &&
                            status == 'cod_pending' &&
                            stage == 'processing')
                          TextButton(
                            onPressed: _busy ? null : () => _cancel(true),
                            child: const Text('Cancel order'),
                          ),
                        if (!seller && status == 'payment_pending')
                          TextButton(
                            onPressed: _busy ? null : () => _cancel(false),
                            child: const Text('Cancel unpaid checkout'),
                          ),
                        TextButton(
                          onPressed: () =>
                              context.go(seller ? '/selling' : '/orders'),
                          child: Text(
                            seller ? 'Back to Seller Center' : 'All orders',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
  );
}

class _DeliveryProgress extends StatelessWidget {
  const _DeliveryProgress({required this.stage});
  final String stage;
  @override
  Widget build(BuildContext context) {
    final current = stage == 'delivered'
        ? 2
        : stage == 'shipped'
        ? 1
        : 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < 3; index++)
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: index <= current
                      ? const Color(0xFF2457D6)
                      : const Color(0xFFE4E8EF),
                  child: Icon(
                    [
                      Icons.receipt_long_outlined,
                      Icons.local_shipping_outlined,
                      Icons.inventory_2_outlined,
                    ][index],
                    color: index <= current ? Colors.white : Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ['Ordered', 'On delivery', 'Received'][index],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PurchaseReviewForm extends ConsumerStatefulWidget {
  const _PurchaseReviewForm({
    required this.orderId,
    required this.busy,
    required this.onSubmit,
  });
  final String orderId;
  final bool busy;
  final Future<bool> Function(int, String, List<String>) onSubmit;
  @override
  ConsumerState<_PurchaseReviewForm> createState() =>
      _PurchaseReviewFormState();
}

class _PurchaseReviewFormState extends ConsumerState<_PurchaseReviewForm> {
  final _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  int _rating = 0;
  final _photos = <ReviewDraftPhoto>[];
  bool _working = false;
  bool get _disabled => widget.busy || _working;
  @override
  void initState() {
    super.initState();
    _recoverPhoto();
  }

  Future<void> _recoverPhoto() async {
    try {
      final result = await ref
          .read(reviewPhotoPickerProvider)
          .retrieveLostData();
      if (mounted && result.files != null) {
        for (final file in result.files!.take(3)) {
          await _addPhoto(file);
        }
      }
    } catch (_) {
      /* Recovery is unavailable on non-Android platforms. */
    }
  }

  Future<void> _addPhoto(XFile file) async {
    if (await file.length() > 3 * 1024 * 1024) {
      if (mounted) {
        showNotice(context, 'Choose a JPG, PNG or WebP photo under 3 MB.');
      }
      return;
    }
    final bytes = await file.readAsBytes();
    final extension = reviewPhotoExtension(bytes);
    if (!mounted) return;
    if (extension == null) {
      showNotice(context, 'Choose a JPG, PNG or WebP photo under 3 MB.');
    } else if (_photos.length < 3) {
      setState(() => _photos.add(ReviewDraftPhoto(bytes, extension)));
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_disabled || _photos.length >= 3) return;
    setState(() => _working = true);
    try {
      final file = await ref
          .read(reviewPhotoPickerProvider)
          .pickImage(
            source: source,
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 85,
            requestFullMetadata: false,
          );
      if (file != null && mounted) await _addPhoto(file);
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Could not open the camera or photos. Check permission and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _submit() async {
    if (_disabled || !_form.currentState!.validate()) return;
    setState(() => _working = true);
    try {
      for (final photo in _photos) {
        photo.uploadedPath ??= await ref
            .read(paymentRepositoryProvider)
            .uploadReviewPhoto(widget.orderId, photo.bytes, photo.extension);
        if (!mounted) return;
      }
      await widget.onSubmit(
        _rating,
        _notes.text.trim(),
        _photos.map((p) => p.uploadedPath!).toList(),
      );
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Photo upload failed. Your review is still here; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rate your purchase',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text('Your review will appear on the product listing.'),
        Row(
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                tooltip: 'Rate $star stars',
                onPressed: _disabled
                    ? null
                    : () => setState(() => _rating = star),
                icon: Icon(
                  star <= _rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: const Color(0xFFDB9E19),
                  size: 32,
                ),
              ),
          ],
        ),
        TextFormField(
          key: const Key('review-notes'),
          controller: _notes,
          enabled: !_disabled,
          minLines: 3,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Review notes',
            hintText: 'How was the item and your delivery experience?',
          ),
          validator: (value) => (value?.trim().length ?? 0) < 5
              ? 'Write at least five characters.'
              : null,
        ),
        const SizedBox(height: 12),
        const Text(
          'Item photos (optional, up to 3). Photos are public with your review.',
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _disabled || _photos.length >= 3
                  ? null
                  : () => _pickPhoto(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Capture item'),
            ),
            OutlinedButton.icon(
              onPressed: _disabled || _photos.length >= 3
                  ? null
                  : () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Add photo'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final photo in _photos)
              Stack(
                children: [
                  Image.memory(
                    photo.bytes,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton.filled(
                      tooltip: 'Remove photo',
                      onPressed: _disabled
                          ? null
                          : () => setState(() => _photos.remove(photo)),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('review-submit'),
          onPressed: _disabled || _rating == 0 ? null : _submit,
          child: Text(_disabled ? 'Saving…' : 'Submit review'),
        ),
      ],
    ),
  );
}
