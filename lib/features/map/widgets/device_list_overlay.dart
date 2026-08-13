import 'package:flutter/material.dart';
import '../../../data/models/device_model.dart';
import '../../../domain/entities/device_status_resolver.dart';

class DeviceListOverlay extends StatefulWidget {
  const DeviceListOverlay({
    super.key,
    required this.devices,
    required this.onDeviceSelected,
    this.onClose,
  });

  final List<DeviceModel> devices;
  final void Function(DeviceModel) onDeviceSelected;
  final VoidCallback? onClose;

  @override
  State<DeviceListOverlay> createState() => _DeviceListOverlayState();
}

class _DeviceListOverlayState extends State<DeviceListOverlay> {
  String _searchQuery = '';
  bool _isSearchExpanded = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Thiết bị (${widget.devices.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_isSearchExpanded ? Icons.search_off : Icons.search),
                      onPressed: () {
                        setState(() {
                          _isSearchExpanded = !_isSearchExpanded;
                          if (!_isSearchExpanded) {
                            _searchQuery = '';
                            _searchController.clear();
                          }
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 20,
                    ),
                    if (widget.onClose != null) ...[
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: widget.onClose,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        iconSize: 20,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Search Bar
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isSearchExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm thiết bị...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: theme.colorScheme.primary),
                        ),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const Divider(height: 1),
          // List
          Expanded(
            child: Builder(
              builder: (context) {
                final filteredDevices = widget.devices.where((d) {
                  final query = _searchQuery.toLowerCase();
                  return d.name.toLowerCase().contains(query) || 
                         d.deviceCode.toLowerCase().contains(query);
                }).toList();

                if (filteredDevices.isEmpty) {
                  return const Center(child: Text('Không tìm thấy thiết bị nào'));
                }

                return ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: filteredDevices.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = filteredDevices[index];
                    return _DeviceListItem(
                      device: device,
                      onTap: () => widget.onDeviceSelected(device),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceListItem extends StatelessWidget {
  const _DeviceListItem({required this.device, required this.onTap});

  final DeviceModel device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );

    // Speed formatting
    String speedText = '--';
    if (device.currentSpeedMps != null) {
      speedText = (device.currentSpeedMps! * 3.6).toStringAsFixed(1);
    }

    final displayName = device.name.isNotEmpty ? device.name : device.deviceCode;
    final subtitle = device.name.isNotEmpty && device.deviceCode != device.name 
        ? device.deviceCode 
        : '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Status Indicator
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _getStatusColor(status.connectivity, status.movement),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            // Identity
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Speed
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  speedText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'km/h',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    height: 0.8,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(ConnectivityStatus conn, MovementStatus move) {
    if (conn == ConnectivityStatus.offline) return Colors.grey;
    if (move == MovementStatus.moving) return Colors.blue;
    return Colors.green; // Online, stopped/idle
  }
}
