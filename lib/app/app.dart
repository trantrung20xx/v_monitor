import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:device_preview/device_preview.dart';
import 'app_router.dart';
import 'app_theme.dart';
import '../core/network/api_client.dart';
import '../core/network/websocket_client.dart';
import '../data/repositories/device_repository.dart';
import '../data/repositories/tracking_repository.dart';
import '../features/dashboard/dashboard_cubit.dart';

class VMonitorApp extends StatelessWidget {
  final ApiClient apiClient;
  final WebsocketClient websocketClient;

  const VMonitorApp({
    super.key, 
    required this.apiClient,
    required this.websocketClient,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DeviceRepository>(
          create: (_) => DeviceRepository(apiClient, websocketClient),
        ),
        RepositoryProvider<TrackingRepository>(
          create: (_) => TrackingRepository(apiClient),
        ),
        RepositoryProvider<WebsocketClient>.value(
          value: websocketClient,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<DashboardCubit>(
            create: (context) => DashboardCubit(
              deviceRepo: context.read<DeviceRepository>(),
            )..loadDashboard(),
          ),
        ],
        child: MaterialApp.router(
          title: 'v_monitor',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          routerConfig: AppRouter.router,
          debugShowCheckedModeBanner: false,
          locale: DevicePreview.locale(context),
          builder: DevicePreview.appBuilder,
        ),
      ),
    );
  }
}
