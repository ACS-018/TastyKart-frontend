import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../models/admin_models.dart';
import '../../state/cart_controller.dart';

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final customerId = CartScope.maybeOf(context)?.customerId;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 16,
              bottom: 18,
            ),
            color: AppColors.primary,
            child: Row(
              children: [
                if (!embedded)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.white,
                      size: 20,
                    ),
                  ),
                const SizedBox(width: 4),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order History',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Your Completed Orders',
                      style: TextStyle(color: AppColors.white, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Unordered to avoid requiring a composite index; sort client-side.
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .limit(40)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Failed to load orders\n${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var orders = (snapshot.data?.docs ?? [])
                    .map(TkOrder.fromDoc)
                    .where((o) => o.id.isNotEmpty)
                    .toList();

                if (customerId != null) {
                  final mine =
                      orders.where((o) => o.customerId == customerId).toList();
                  if (mine.isNotEmpty) orders = mine;
                }

                orders.sort((a, b) {
                  final aa =
                      a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bb =
                      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return bb.compareTo(aa);
                });

                if (orders.isEmpty) {
                  return const Center(child: Text('No orders yet'));
                }

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    embedded ? 100 : 24,
                  ),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) =>
                      _OrderHistoryCard(order: orders[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  const _OrderHistoryCard({required this.order});

  final TkOrder order;

  @override
  Widget build(BuildContext context) {
    final firstItem =
        order.items.isNotEmpty ? order.items.first['name']?.toString() : '';
    final dateLabel = order.createdAt != null
        ? '${order.createdAt!.day}/${order.createdAt!.month}/${order.createdAt!.year}'
        : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8E8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.restaurantName.isEmpty
                          ? 'Tasty Kart Order'
                          : order.restaurantName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      order.address.isEmpty ? '—' : order.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B6B6B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Order ID ${order.orderNumber} · ₹${order.total} · ${order.paymentMethod}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          _InfoRow('Status', order.status),
          if (dateLabel.isNotEmpty) _InfoRow('Date', dateLabel),
          _InfoRow('Phone', order.customerPhone),
          _InfoRow('Deliver To', order.address),
          if (firstItem != null && firstItem.isNotEmpty)
            _InfoRow('Items', firstItem),
          _InfoRow('Item Total', '₹${order.subtotal}'),
          _InfoRow('Delivery Charges', '₹${order.deliveryFee}'),
          _InfoRow('Tax', '₹${order.tax}'),
          _InfoRow('Grand Total', '₹${order.total}', bold: true),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Open restaurant to repeat items'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Repeat Order',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF6B6B6B),
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold ? AppColors.primary : const Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
