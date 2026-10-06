import 'package:flutter/material.dart';

import '../constants/color_constants.dart';
import '../models/restaurant.dart';
import '../state/favorites_controller.dart';
import '../utils/app_feedback.dart';

/// Heart toggle for favourite restaurants (Firestore-backed).
class FavoriteRestaurantButton extends StatefulWidget {
  const FavoriteRestaurantButton({
    super.key,
    required this.restaurant,
    this.size = 34,
    this.iconSize = 18,
    this.backgroundColor,
  });

  final Restaurant restaurant;
  final double size;
  final double iconSize;
  final Color? backgroundColor;

  @override
  State<FavoriteRestaurantButton> createState() =>
      _FavoriteRestaurantButtonState();
}

class _FavoriteRestaurantButtonState extends State<FavoriteRestaurantButton> {
  bool _busy = false;

  Future<void> _toggle(FavoritesController favorites) async {
    if (_busy) return;
    setState(() => _busy = true);
    final wasOn = favorites.isFavorite(widget.restaurant.id);
    AppFeedback.light();
    try {
      await favorites.toggle(widget.restaurant);
      if (!mounted) return;
      if (!wasOn) {
        AppFeedback.success();
      }
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context, 'Could not update favourites');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = FavoritesScope.maybeOf(context);
    if (favorites == null || widget.restaurant.id.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final on = favorites.isFavorite(widget.restaurant.id);
        return GestureDetector(
          onTap: _busy ? null : () => _toggle(favorites),
          child: AnimatedScale(
            scale: on ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.backgroundColor ??
                    AppColors.white.withValues(alpha: 0.95),
                shape: BoxShape.circle,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  on ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(on),
                  size: widget.iconSize,
                  color: on ? AppColors.primary : const Color(0xFF6B6B6B),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// App bar heart for restaurant menu header.
class FavoriteRestaurantIconButton extends StatefulWidget {
  const FavoriteRestaurantIconButton({super.key, required this.restaurant});

  final Restaurant? restaurant;

  @override
  State<FavoriteRestaurantIconButton> createState() =>
      _FavoriteRestaurantIconButtonState();
}

class _FavoriteRestaurantIconButtonState
    extends State<FavoriteRestaurantIconButton> {
  bool _busy = false;

  Future<void> _toggle(FavoritesController favorites, Restaurant restaurant) async {
    if (_busy) return;
    setState(() => _busy = true);
    final wasOn = favorites.isFavorite(restaurant.id);
    AppFeedback.light();
    try {
      await favorites.toggle(restaurant);
      if (!mounted) return;
      if (!wasOn) AppFeedback.success();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context, 'Could not update favourites');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.restaurant == null || widget.restaurant!.id.isEmpty) {
      return const SizedBox.shrink();
    }

    final favorites = FavoritesScope.maybeOf(context);
    if (favorites == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final isOn = favorites.isFavorite(widget.restaurant!.id);
        return IconButton(
          onPressed: _busy
              ? null
              : () => _toggle(favorites, widget.restaurant!),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              isOn ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(isOn),
              color: isOn ? AppColors.primary : null,
            ),
          ),
        );
      },
    );
  }
}
