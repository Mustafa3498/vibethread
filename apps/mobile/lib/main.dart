import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/network/dio_client.dart';
import 'core/services/secure_storage_service.dart';
import 'core/services/socket_service.dart';
import 'core/theme/app_theme.dart';
import 'core/tracking/tracking_service.dart';
import 'features/auth/data/datasources/auth_remote_datasource.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/cart/data/cart_repository.dart';
import 'features/cart/presentation/cart_bloc.dart';
import 'features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'features/checkout/data/checkout_repository.dart';
import 'features/orders/data/order_repository.dart';
import 'features/catalog/data/repositories/catalog_repository_impl.dart';
import 'features/catalog/domain/repositories/catalog_repository.dart';
import 'features/catalog/presentation/bloc/catalog_bloc.dart';
import 'features/catalog/presentation/pages/catalog_page.dart';
import 'features/product/data/datasources/product_remote_datasource.dart';
import 'features/product/data/repositories/product_repository_impl.dart';
import 'features/product/domain/repositories/product_repository.dart';

/// Backend URLs. Do NOT add `/api` here: datasources already use full paths
/// such as `/api/auth/login`.
///
/// Real phone over USB: run `adb reverse tcp:4000 tcp:4000` and keep the
/// defaults. Other setups, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:4000
///               --dart-define=SOCKET_URL=http://192.168.1.10:4000
const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:4000',
);
const String _socketUrl = String.fromEnvironment(
  'SOCKET_URL',
  defaultValue: 'http://localhost:4000',
);

Future<void> main() async {
  // Anything uncaught in this zone is routed to _reportError.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _reportError(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _reportError(error, stack);
      return true;
    };

    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    final deps = await AppDependencies.create();

    if (kDebugMode) Bloc.observer = _AppBlocObserver();

    runApp(VibeThreadApp(deps: deps));
  }, _reportError);
}

void _reportError(Object error, StackTrace? stack) {
  // TODO: forward to Crashlytics / Sentry in production.
  debugPrint('Unhandled error: $error\n$stack');
}

// -----------------------------------------------------------------------------
// Composition root
// -----------------------------------------------------------------------------

/// Builds the object graph once at startup.
class AppDependencies {
  AppDependencies._({
    required this.secureStorage,
    required this.socketService,
    required this.authRepository,
    required this.catalogRepository,
    required this.productRepository,
    required this.cartRepository,
    required this.checkoutRepository,
    required this.orderRepository,
    required this.trackingService,
    required this.sessionExpired,
  });

  final SecureStorageService secureStorage;
  final SocketService socketService;
  final AuthRepository authRepository;
  final CatalogRepository catalogRepository;
  final ProductRepository productRepository;
  final CartRepository cartRepository;
  final CheckoutRepository checkoutRepository;
  final OrderRepository orderRepository;
  final TrackingService trackingService;

  /// Emits when the refresh token was rejected and the user must sign in again.
  final Stream<void> sessionExpired;

  static Future<AppDependencies> create() async {
    final secureStorage = SecureStorageService();
    final sessionExpired = StreamController<void>.broadcast();

    // Dio + interceptors + CookieJar live inside DioClient.
    final dioClient = await DioClient.create(
      baseUrl: _apiBaseUrl,
      secureStorage: secureStorage,
      onSessionExpired: () => sessionExpired.add(null),
    );

    final authRepository = AuthRepositoryImpl(
      remote: AuthRemoteDataSource(dioClient.dio),
      storage: secureStorage,
      cookieJar: dioClient.cookieJar,
    );

    final catalogRepository = CatalogRepositoryImpl(
      CatalogRemoteDataSource(dioClient.dio),
    );

    final productRepository = ProductRepositoryImpl(
      ProductRemoteDataSource(dioClient.dio),
    );

    final cartRepository = CartRepository(dioClient.dio);
    final checkoutRepository = CheckoutRepository(dioClient.dio);
    final orderRepository = OrderRepository(dioClient.dio);
    final trackingService = TrackingService(dio: dioClient.dio);
    await trackingService.start();

    final socketService = SocketService(
      secureStorage: secureStorage,
      serverUrl: _socketUrl,
    );

    return AppDependencies._(
      secureStorage: secureStorage,
      socketService: socketService,
      authRepository: authRepository,
      catalogRepository: catalogRepository,
      productRepository: productRepository,
      cartRepository: cartRepository,
      checkoutRepository: checkoutRepository,
      orderRepository: orderRepository,
      trackingService: trackingService,
      sessionExpired: sessionExpired.stream,
    );
  }
}

// -----------------------------------------------------------------------------
// App
// -----------------------------------------------------------------------------

class VibeThreadApp extends StatelessWidget {
  const VibeThreadApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SecureStorageService>.value(
          value: deps.secureStorage,
        ),
        RepositoryProvider<AuthRepository>.value(value: deps.authRepository),
        RepositoryProvider<CatalogRepository>.value(
          value: deps.catalogRepository,
        ),
        RepositoryProvider<ProductRepository>.value(
          value: deps.productRepository,
        ),
        RepositoryProvider<CartRepository>.value(value: deps.cartRepository),
        RepositoryProvider<CheckoutRepository>.value(
          value: deps.checkoutRepository,
        ),
        RepositoryProvider<OrderRepository>.value(value: deps.orderRepository),
        RepositoryProvider<TrackingService>.value(value: deps.trackingService),
        // Lives for the whole app lifetime, so no explicit dispose is needed.
        RepositoryProvider<SocketService>.value(value: deps.socketService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (_) => AuthBloc(authRepository: deps.authRepository)
              ..add(const AuthCheckRequested()),
          ),
          BlocProvider<CatalogBloc>(
            create: (_) => CatalogBloc(deps.catalogRepository),
          ),
          BlocProvider<CartBloc>(
            create: (_) => CartBloc(
              repository: deps.cartRepository,
              socket: deps.socketService,
            ),
          ),
        ],
        child: MaterialApp(
          title: 'VibeThread',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(),
          home: _AuthGate(sessionExpired: deps.sessionExpired),
        ),
      ),
    );
  }
}

/// Switches between login and the main experience based on [AuthBloc] state
/// and ties the socket lifecycle to authentication.
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.sessionExpired});

  final Stream<void> sessionExpired;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  StreamSubscription<void>? _expiredSub;

  @override
  void initState() {
    super.initState();
    _expiredSub = widget.sessionExpired.listen((_) {
      if (mounted) context.read<AuthBloc>().add(const AuthSessionExpired());
    });
  }

  @override
  void dispose() {
    _expiredSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final socket = context.read<SocketService>();

    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          unawaited(socket.reconnect()); // fresh token after login/refresh
          context.read<CartBloc>().add(const CartStarted());
        } else if (state is AuthUnauthenticated) {
          socket.disconnect();
          unawaited(context.read<TrackingService>().endSessionAndRotate());
          context.read<CartBloc>().add(const CartReset());
        }
      },
      builder: (context, state) {
        if (state is AuthAuthenticated) return const CatalogScreen();
        if (state is AuthInitial) return const _SplashScreen();
        // Unauthenticated, Loading (login in progress) and Failure all keep
        // the login form on screen so typed text is not lost.
        return const LoginPage();
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// -----------------------------------------------------------------------------
// Debug tooling
// -----------------------------------------------------------------------------

class _AppBlocObserver extends BlocObserver {
  @override
  void onTransition(Bloc bloc, Transition transition) {
    super.onTransition(bloc, transition);
    // Event/state class names only: states can contain user data.
    debugPrint('[${bloc.runtimeType}] ${transition.event.runtimeType}');
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    debugPrint('[${bloc.runtimeType}] error: $error');
    super.onError(bloc, error, stackTrace);
  }
}
