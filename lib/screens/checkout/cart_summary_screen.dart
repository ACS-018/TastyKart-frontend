import 'package:flutter/material.dart';
import '../../constants/color_constants.dart';
import '../../state/cart_controller.dart';
import '../location/select_location_screen.dart';
import 'payment_options_screen.dart';

class CartSummaryScreen extends StatelessWidget {
  const CartSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          _CheckoutHeader(
            title: 'Cart Summary',
            subtitle: 'Your Order Is Here',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('Your cart is empty'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      Container(
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
                          children: [
                            for (var i = 0; i < cart.lines.length; i++) ...[
                              if (i > 0) const Divider(height: 24),
                              _CartLineTile(
                                line: cart.lines[i],
                                onMinus: () => cart.updateQuantity(
                                  i,
                                  cart.lines[i].quantity - 1,
                                ),
                                onPlus: () => cart.updateQuantity(
                                  i,
                                  cart.lines[i].quantity + 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Bill Summary',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            _BillRow('Items Total', '₹${cart.itemsTotal}'),
                            _BillRow(
                              'Delivery Fee',
                              '₹${cart.deliveryFee}',
                            ),
                            _BillRow(
                              'Taxes & Charges',
                              '₹${cart.taxes}',
                            ),
                            _BillRow('Discount', '₹${cart.discount}'),
                            _BillRow(
                              'Packing Charges',
                              '₹${cart.packingCharges}',
                            ),
                            if (cart.platformFee > 0)
                              _BillRow(
                                'Platform Fee',
                                '₹${cart.platformFee}',
                              ),
                            const Divider(height: 24),
                            _BillRow(
                              'Grand Total',
                              '₹${cart.grandTotal}',
                              bold: true,
                              highlight: true,
                            ),
                          ],
                        ),
                      ),
                      if (cart.selectedAddress != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cart.selectedAddress!.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      cart.selectedAddress!.fullAddress,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B6B6B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (!cart.isEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (cart.hasDeliveryAddress) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PaymentOptionsScreen(),
                          ),
                        );
                        return;
                      }
                      final address = await SelectLocationScreen.pick(context);
                      if (address == null || !context.mounted) return;
                      cart.setAddress(address);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaymentOptionsScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD6D6),
                      foregroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      cart.hasDeliveryAddress
                          ? 'Proceed to Payment'
                          : 'Select Address & Pay At Next Step',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckoutHeader extends StatelessWidget {
  const _CheckoutHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.white, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.onMinus,
    required this.onPlus,
  });

  final CartLine line;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 56,
            height: 56,
            child: line.item.image.isNotEmpty
                ? Image.network(line.item.image, fit: BoxFit.cover)
                : Container(color: const Color(0xFFEEEEEE)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.item.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '₹${line.unitTotal}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              Text(
                'Serve ${line.quantity}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B)),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDDDDDD)),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onMinus,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              Text(
                '${line.quantity}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onPlus,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow(
    this.label,
    this.value, {
    this.bold = false,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool bold;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: highlight ? AppColors.primary : const Color(0xFF1A1A1A),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }
}
