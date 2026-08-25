// Lắp ráp dependency, repository và Cubit cấp ứng dụng; đồng thời chọn màn hình
// đăng nhập hay hệ thống giám sát theo AuthState và áp dụng theme từ SettingsState.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app_router.dart';
import 'app_theme.dart';
import '../core/auth/auth_token_store.dart';
import '../core/network/api_client.dart';
import '../core/network/websocket_client.dart';
import '../data/repositories/device_repository.dart';
import '../data/repositories/geocoding_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/tracking_repository.dart';
import '../features/auth/auth_cubit.dart';
import '../features/auth/auth_state.dart';
import '../features/auth/login_page.dart';
import '../features/settings/settings_cubit.dart';
import '../features/settings/settings_state.dart';

// Gốc dependency: nhận hai client từ main, tạo token store/repository/AuthCubit
// và chọn màn hình theo trạng thái xác thực.
class VMonitorApp extends StatelessWidget {
  final ApiClient apiClient;
  final WebsocketClient websocketClient;
  final AuthTokenStore? authTokenStore;

  const VMonitorApp({
    super.key,
    required this.apiClient,
    required this.websocketClient,
    this.authTokenStore,
  });

  @override
  Widget build(BuildContext context) {
    // MultiRepositoryProvider bảo đảm mọi Cubit/route dùng cùng repository và cache runtime.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DeviceRepository>(
          create: (_) => DeviceRepository(apiClient, websocketClient),
        ),
        RepositoryProvider<TrackingRepository>(
          create: (_) => TrackingRepository(apiClient),
        ),
        RepositoryProvider<GeocodingRepository>(
          create: (_) => GeocodingRepository(apiClient),
        ),
        RepositoryProvider<SettingsRepository>(
          create: (_) => SettingsRepository(apiClient, websocketClient),
          dispose: (repository) => unawaited(repository.dispose()),
        ),
        RepositoryProvider<WebsocketClient>.value(value: websocketClient),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => AuthCubit(
              apiClient,
              websocketClient,
              authTokenStore ?? SecureAuthTokenStore(),
            )..initialize(),
          ),
          BlocProvider(
            create: (context) =>
                SettingsCubit(context.read<SettingsRepository>()),
          ),
        ],
        child: const _AuthenticatedApplication(),
      ),
    );
  }
}

// Cây sau đăng nhập: khởi tạo SettingsCubit, nạp cấu hình cá nhân/hệ thống rồi
// MaterialApp.router dựng theme và điều hướng theo các snapshot đó.
class _AuthenticatedApplication extends StatelessWidget {
  const _AuthenticatedApplication();

  @override
  Widget build(BuildContext context) {
    // BlocBuilder chỉ rebuild MaterialApp khi settings/theme thay đổi; router và
    // repository vẫn giữ cùng instance.
    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        final settingsCubit = context.read<SettingsCubit>();
        if (state.isAuthenticated) {
          settingsCubit.initialize();
        } else {
          settingsCubit.reset();
        }
      },
      child: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, authState) {
          if (authState.isAuthenticated) {
            return BlocBuilder<SettingsCubit, SettingsState>(
              builder: (context, settingsState) => MaterialApp.router(
                title: 'v_monitor',
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: settingsState.userSettings.themeMode,
                routerConfig: AppRouter.router,
                debugShowCheckedModeBanner: false,
                builder: _fixedTextScaleBuilder,
              ),
            );
          }

          return MaterialApp(
            title: 'v_monitor',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            debugShowCheckedModeBanner: false,
            builder: _fixedTextScaleBuilder,
            home: authState.status == AuthStatus.checking
                ? const AuthCheckingPage()
                : const LoginPage(),
          );
        },
      ),
    );
  }
}

Widget _fixedTextScaleBuilder(BuildContext context, Widget? child) {
  // Giữ textScaler theo chính sách giao diện hiện tại và bọc child an toàn khi null.
  final data = MediaQuery.of(context);
  return MediaQuery(
    data: data.copyWith(
      textScaler: data.textScaler.clamp(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.0,
      ),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}
