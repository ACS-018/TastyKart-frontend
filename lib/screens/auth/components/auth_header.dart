import 'package:flutter/material.dart';
import '../../../constants/color_constants.dart';
import '../../../constants/image_constants.dart';
import '../../../utils/responsive.dart';

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);

    final double logoSize = r.responsive(
      mobile: 250.0,
      tablet: 130.0,
      desktop: 150.0,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Image.asset(
          AppImages.logo,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.shopping_bag_rounded,
            color: AppColors.primary,
            size: logoSize * 0.8,
          ),
        ),
      ],
    );
  }
}
