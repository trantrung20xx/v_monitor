import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme_colors.dart';
import 'auth_cubit.dart';
import 'auth_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<AuthCubit>().login(
      _usernameController.text,
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final appColors = context.appColors;
        final isSubmitting = state.status == AuthStatus.authenticating;
        final serverUnavailable = state.status == AuthStatus.serverUnavailable;

        return Scaffold(
          backgroundColor: appColors.background,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    elevation: 8,
                    shadowColor: appColors.shadow.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
                      child: AutofillGroup(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: appColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: appColors.border),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Transform.scale(
                                    scale: 1.75,
                                    child: Image.asset(
                                      'assets/branding/v_monitor_logo.png',
                                      fit: BoxFit.cover,
                                      semanticLabel: 'V Monitor',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Đăng nhập hệ thống',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: appColors.textPrimary,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Giám sát thiết bị nội bộ doanh nghiệp',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: appColors.textSecondary),
                              ),
                              const SizedBox(height: 28),
                              TextFormField(
                                key: const Key('login-username'),
                                controller: _usernameController,
                                enabled: !isSubmitting,
                                autofillHints: const [AutofillHints.username],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Tên đăng nhập',
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                  ),
                                ),
                                validator: (value) {
                                  if ((value ?? '').trim().length < 3) {
                                    return 'Tên đăng nhập phải có ít nhất 3 ký tự.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                key: const Key('login-password'),
                                controller: _passwordController,
                                enabled: !isSubmitting,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Mật khẩu',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Hiện mật khẩu'
                                        : 'Ẩn mật khẩu',
                                    onPressed: isSubmitting
                                        ? null
                                        : () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if ((value ?? '').isEmpty) {
                                    return 'Mật khẩu không được để trống.';
                                  }
                                  return null;
                                },
                              ),
                              if (state.message != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: appColors.dangerSoft,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    state.message!,
                                    key: const Key('login-message'),
                                    style: TextStyle(
                                      color: appColors.dangerStrong,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              if (serverUnavailable)
                                OutlinedButton.icon(
                                  key: const Key('retry-authentication'),
                                  onPressed: () =>
                                      context.read<AuthCubit>().initialize(),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Thử kết nối lại'),
                                )
                              else
                                FilledButton(
                                  key: const Key('login-submit'),
                                  onPressed: isSubmitting ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: AppPalette.onAccent,
                                          ),
                                        )
                                      : const Text('Đăng nhập'),
                                ),
                              const SizedBox(height: 18),
                              Text(
                                'Tài khoản do quản trị viên doanh nghiệp cấp.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: appColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AuthCheckingPage extends StatelessWidget {
  const AuthCheckingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.background,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Đang kiểm tra thông tin đăng nhập...'),
          ],
        ),
      ),
    );
  }
}
