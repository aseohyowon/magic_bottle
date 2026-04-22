import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _releaseBannerAdUnitIdAndroid =
    'ca-app-pub-6516622519474642/8898217393';
const String _releaseInterstitialAdUnitIdAndroid =
    'ca-app-pub-6516622519474642/4852842784';
const String _testBannerAdUnitIdAndroid =
    'ca-app-pub-3940256099942544/6300978111';
const String _testBannerAdUnitIdIos =
    'ca-app-pub-3940256099942544/2934735716';
const String _testInterstitialAdUnitIdAndroid =
    'ca-app-pub-3940256099942544/1033173712';
const String _testInterstitialAdUnitIdIos =
    'ca-app-pub-3940256099942544/4411468910';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // iOS 우선 출시를 고려해 세로 모드만 허용한다.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 상태 저장을 위해 앱 시작 시 SharedPreferences 를 미리 준비한다.
  final prefs = await SharedPreferences.getInstance();
  final repository = ProgressRepository(prefs);
  await MobileAds.instance.initialize();

  runApp(MagicBottleApp(repository: repository));
}

String get bannerAdUnitId {
  if (kDebugMode) {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? _testBannerAdUnitIdIos
        : _testBannerAdUnitIdAndroid;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return _releaseBannerAdUnitIdAndroid;
  }
  return _testBannerAdUnitIdIos;
}

String get interstitialAdUnitId {
  if (kDebugMode) {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? _testInterstitialAdUnitIdIos
        : _testInterstitialAdUnitIdAndroid;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return _releaseInterstitialAdUnitIdAndroid;
  }
  return _testInterstitialAdUnitIdIos;
}

class MagicBottleApp extends StatelessWidget {
  const MagicBottleApp({super.key, required this.repository});

  final ProgressRepository repository;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: repository,
      child: BlocProvider(
        create:
            (_) => MagicSortCubit(
              repository: repository,
              audioService: MagicAudioService(),
            )..loadInitialData(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Magic Bottle',
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF09061D),
            fontFamily: 'SF Pro Display',
            useMaterial3: true,
          ),
          home: const MagicSortPage(),
        ),
      ),
    );
  }
}

class MagicSortPage extends StatefulWidget {
  const MagicSortPage({super.key});

  @override
  State<MagicSortPage> createState() => _MagicSortPageState();
}

class _MagicSortPageState extends State<MagicSortPage> {
  late final BottleBoardGame _game;
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;
  InterstitialAd? _interstitialAd;
  int _clearsSinceInterstitial = 0;

  @override
  void initState() {
    super.initState();

    // Flame 게임 객체는 한 번만 생성하고, 상태 변화만 주입해서 재사용한다.
    _game = BottleBoardGame(
      onTubeTap: (tubeIndex) {
        context.read<MagicSortCubit>().onTubeTapped(tubeIndex);
      },
    );
    _loadBannerAd();
    _loadInterstitialAd();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MagicSortCubit, MagicSortState>(
      listenWhen:
          (previous, current) =>
              previous.victoryNonce != current.victoryNonce ||
              previous.stageSelectionNonce != current.stageSelectionNonce,
      listener: (context, state) async {
        _game.syncState(state);

        if (state.stageSelectionNonce > 0) {
          if (!mounted) return;
          await _showStageSelector(this.context, state);
        }

        if (state.victoryNonce > 0) {
          if (!mounted) return;
          _handleInterstitialOpportunity();
          await _showVictoryDialog(this.context, state);
        }
      },
      child: BlocBuilder<MagicSortCubit, MagicSortState>(
        builder: (context, state) {
          _game.syncState(state);

          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF160F3D),
                    Color(0xFF27155B),
                    Color(0xFF060716),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: _TopHud(state: state),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x1FFFFFFF), Color(0x0DFFFFFF)],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (details) {
                                  final box =
                                      context.findRenderObject() as RenderBox?;
                                  if (box == null) {
                                    return;
                                  }

                                  final localPosition = box.globalToLocal(
                                    details.globalPosition,
                                  );
                                  _game.handleTap(
                                    localPosition,
                                    Size(
                                      constraints.maxWidth,
                                      constraints.maxHeight,
                                    ),
                                  );
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    IgnorePointer(
                                      child: GameWidget(game: _game),
                                    ),
                                    RepaintBoundary(
                                      child: CustomPaint(
                                        painter: BottleBoardPainter(
                                          state: state,
                                        ),
                                      ),
                                    ),
                                    BottleBoardOverlay(
                                      state: state,
                                      onTubeTap: (tubeIndex) {
                                        context
                                            .read<MagicSortCubit>()
                                            .onTubeTapped(tubeIndex);
                                      },
                                    ),
                                    if (state.tubes.isEmpty)
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withValues(
                                              alpha: 0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(
                                              color: Colors.redAccent
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                          child: const Text(
                                            '보드 데이터가 비어 있습니다',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: _BottomHud(state: state),
                    ),
                    if (_isBannerLoaded && _bannerAd != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SizedBox(
                          width: _bannerAd!.size.width.toDouble(),
                          height: _bannerAd!.size.height.toDouble(),
                          child: AdWidget(ad: _bannerAd!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _loadBannerAd() {
    final ad = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[MagicBottle] banner failed: $error');
          ad.dispose();
        },
      ),
    );
    ad.load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd?.dispose();
          _interstitialAd = ad;
          _interstitialAd?.setImmersiveMode(true);
          _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('[MagicBottle] interstitial show failed: $error');
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('[MagicBottle] interstitial failed: $error');
          _interstitialAd = null;
        },
      ),
    );
  }

  void _handleInterstitialOpportunity() {
    _clearsSinceInterstitial += 1;
    if (_clearsSinceInterstitial < 3) {
      return;
    }
    _clearsSinceInterstitial = 0;
    _interstitialAd?.show();
    _interstitialAd = null;
  }

  Future<void> _showStageSelector(
    BuildContext context,
    MagicSortState state,
  ) async {
    final cubit = context.read<MagicSortCubit>();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14112F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '스테이지 선택',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '클리어한 스테이지까지 다음 단계가 해금됩니다.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(stageDefinitions.length, (index) {
                    final stageNumber = index + 1;
                    final unlocked = stageNumber <= state.unlockedStage;
                    final bestStars = state.bestStars[stageNumber] ?? 0;
                    final selected = stageNumber == state.currentStage;

                    return GestureDetector(
                      onTap:
                          unlocked
                              ? () {
                                Navigator.of(context).pop();
                                cubit.selectStage(stageNumber);
                              }
                              : null,
                      child: Container(
                        width: 88,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color:
                              selected
                                  ? const Color(0xFF854CFF)
                                  : unlocked
                                  ? const Color(0xFF211A45)
                                  : const Color(0xFF18142E),
                          border: Border.all(
                            color:
                                unlocked
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              unlocked ? '$stageNumber' : '잠금',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: unlocked ? Colors.white : Colors.white38,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              unlocked
                                  ? '★' * bestStars + '☆' * (3 - bestStars)
                                  : '☆☆☆',
                              style: TextStyle(
                                color:
                                    unlocked
                                        ? const Color(0xFFFFD76A)
                                        : Colors.white24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );

    cubit.consumeStageSelectionRequest();
  }

  Future<void> _showVictoryDialog(
    BuildContext context,
    MagicSortState state,
  ) async {
    final cubit = context.read<MagicSortCubit>();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF140F2F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '마법 정렬 성공!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(
                  '스테이지 ${state.currentStage} 클리어',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '★' * state.starCount + '☆' * (3 - state.starCount),
                  style: const TextStyle(
                    fontSize: 30,
                    color: Color(0xFFFFD76A),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '이동 횟수 ${state.moveCount}회',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.74),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () {
                          Navigator.of(context).pop();
                          cubit.restartStage();
                        },
                        child: const Text('다시하기'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          cubit.goToNextStage();
                        },
                        child: Text(
                          state.currentStage >= stageDefinitions.length
                              ? '완료'
                              : '다음',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    cubit.consumeVictory();
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({required this.state});

  final MagicSortState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MagicSortCubit>();

    return Row(
      children: [
        _HudIconButton(
          icon: Icons.home_rounded,
          label: '홈',
          onTap: cubit.requestStageSelection,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: _glassBoxDecoration(),
            child: Column(
              children: [
                Text(
                  'STAGE ${state.currentStage}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '이동 ${state.moveCount}회   ·   별 ${state.starCount}개',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _HudIconButton(
          icon: Icons.restart_alt_rounded,
          label: '재시작',
          onTap: cubit.restartStage,
        ),
      ],
    );
  }
}

class _BottomHud extends StatelessWidget {
  const _BottomHud({required this.state});

  final MagicSortState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MagicSortCubit>();

    return Row(
      children: [
        Expanded(
          child: _BottomActionButton(
            icon: Icons.undo_rounded,
            title: '언두',
            subtitle: '${state.undoCount}/5',
            enabled: state.undoCount > 0,
            onTap: cubit.undoMove,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BottomActionButton(
            icon: Icons.auto_awesome_rounded,
            title: '힌트',
            subtitle: '가능 이동',
            enabled: !state.isAnimating,
            onTap: cubit.showHint,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BottomActionButton(
            icon: Icons.grid_view_rounded,
            title: '스테이지',
            subtitle: '선택',
            enabled: true,
            onTap: cubit.requestStageSelection,
          ),
        ),
      ],
    );
  }
}

class _HudIconButton extends StatelessWidget {
  const _HudIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: _glassBoxDecoration(),
        child: Column(
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActionButton extends StatelessWidget {
  const _BottomActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0.45,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: _glassBoxDecoration(),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

BoxDecoration _glassBoxDecoration() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0x30FFFFFF), Color(0x14FFFFFF)],
    ),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x33000000),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
    ],
  );
}

class MagicSortCubit extends Cubit<MagicSortState> {
  MagicSortCubit({required this.repository, required this.audioService})
    : super(MagicSortState.initial());

  final ProgressRepository repository;
  final MagicAudioService audioService;

  Future<void> loadInitialData() async {
    final unlockedStage = repository.loadUnlockedStage();
    final bestStars = repository.loadBestStars();
    debugPrint(
      '[MagicBottle] loadInitialData unlocked=$unlockedStage bestStars=$bestStars',
    );
    final initialStage = _createStageState(
      stageNumber: 1,
      unlockedStage: unlockedStage,
      bestStars: bestStars,
    );
    debugPrint(
      '[MagicBottle] initialStage stage=${initialStage.currentStage} tubes=${initialStage.tubes.length}',
    );
    emit(initialStage);
  }

  void requestStageSelection() {
    emit(state.copyWith(stageSelectionNonce: state.stageSelectionNonce + 1));
  }

  void consumeStageSelectionRequest() {
    emit(state.copyWith(stageSelectionNonce: 0));
  }

  void selectStage(int stageNumber) {
    if (stageNumber > state.unlockedStage) {
      return;
    }

    emit(
      _createStageState(
        stageNumber: stageNumber,
        unlockedStage: state.unlockedStage,
        bestStars: state.bestStars,
      ),
    );
  }

  void restartStage() {
    emit(
      state.copyWith(
        tubes: state.initialTubes.deepCopy(),
        clearSelection: true,
        moveCount: 0,
        moveHistory: const [],
        clearHint: true,
        isAnimating: false,
        invalidAnimationNonce: state.invalidAnimationNonce + 1,
        completed: false,
        victoryNonce: 0,
        lastMoveAnimation: null,
      ),
    );
  }

  Future<void> onTubeTapped(int index) async {
    if (state.isAnimating || state.completed) {
      return;
    }

    if (index < 0 || index >= state.tubes.length) {
      return;
    }

    final tappedTube = state.tubes[index];
    final currentSelection = state.selectedTube;

    if (currentSelection == null) {
      if (tappedTube.isEmpty) {
        await audioService.playError();
        emit(
          state.copyWith(
            invalidTubeIndices: [index],
            invalidAnimationNonce: state.invalidAnimationNonce + 1,
          ),
        );
        return;
      }

      await audioService.playSelect();
      emit(state.copyWith(selectedTube: index, clearHint: true));
      return;
    }

    if (currentSelection == index) {
      emit(state.copyWith(clearSelection: true, clearHint: true));
      return;
    }

    final move = _buildMove(state.tubes, currentSelection, index);
    if (move == null) {
      await audioService.playError();
      emit(
        state.copyWith(
          invalidTubeIndices: [currentSelection, index],
          invalidAnimationNonce: state.invalidAnimationNonce + 1,
        ),
      );
      return;
    }

    final previousSnapshot = state.tubes.deepCopy();
    final movedTubes = _applyMove(previousSnapshot, move);
    final history = [
      ...state.moveHistory,
      MoveSnapshot(tubes: previousSnapshot),
    ]..retainLast(5);

    await audioService.playMove();

    emit(
      state.copyWith(
        tubes: movedTubes,
        clearSelection: true,
        moveCount: state.moveCount + 1,
        moveHistory: history,
        clearHint: true,
        isAnimating: true,
        invalidTubeIndices: const [],
        lastMoveAnimation: move,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 340));

    final solved = _isSolved(movedTubes);
    if (solved) {
      final starCount = _calculateStars(
        state.currentStage,
        state.moveCount + 1,
      );
      final updatedUnlocked = min(
        stageDefinitions.length,
        max(state.unlockedStage, state.currentStage + 1),
      );
      final updatedBestStars = {...state.bestStars};
      updatedBestStars[state.currentStage] = max(
        updatedBestStars[state.currentStage] ?? 0,
        starCount,
      );

      await repository.saveUnlockedStage(updatedUnlocked);
      await repository.saveBestStars(updatedBestStars);
      await audioService.playVictory();

      emit(
        state.copyWith(
          isAnimating: false,
          completed: true,
          starCount: starCount,
          unlockedStage: updatedUnlocked,
          bestStars: updatedBestStars,
          victoryNonce: state.victoryNonce + 1,
        ),
      );
      return;
    }

    emit(state.copyWith(isAnimating: false));
  }

  void undoMove() {
    if (state.moveHistory.isEmpty || state.isAnimating) {
      return;
    }

    final history = [...state.moveHistory];
    final latest = history.removeLast();

    emit(
      state.copyWith(
        tubes: latest.tubes.deepCopy(),
        clearSelection: true,
        moveCount: max(0, state.moveCount - 1),
        moveHistory: history,
        clearHint: true,
        completed: false,
        victoryNonce: 0,
        lastMoveAnimation: null,
      ),
    );
  }

  Future<void> showHint() async {
    if (state.isAnimating || state.completed) {
      return;
    }

    final hint = _findHintMove(state.tubes);
    if (hint == null) {
      await audioService.playError();
      emit(
        state.copyWith(
          invalidTubeIndices: const [],
          invalidAnimationNonce: state.invalidAnimationNonce + 1,
        ),
      );
      return;
    }

    await audioService.playSelect();
    emit(
      state.copyWith(
        hintMove: HintMove(fromIndex: hint.fromIndex, toIndex: hint.toIndex),
      ),
    );
  }

  void goToNextStage() {
    final nextStage = min(stageDefinitions.length, state.currentStage + 1);
    emit(
      _createStageState(
        stageNumber: nextStage,
        unlockedStage: state.unlockedStage,
        bestStars: state.bestStars,
      ),
    );
  }

  void consumeVictory() {
    emit(state.copyWith(victoryNonce: 0));
  }

  MagicSortState _createStageState({
    required int stageNumber,
    required int unlockedStage,
    required Map<int, int> bestStars,
  }) {
    final definition = stageDefinitions[stageNumber - 1];
    final generatedTubes = [
      for (final balls in definition.layout)
        TubeModel(balls: List<int>.from(balls)),
    ];

    return MagicSortState(
      currentStage: stageNumber,
      unlockedStage: unlockedStage,
      bestStars: bestStars,
      tubes: generatedTubes.deepCopy(),
      initialTubes: generatedTubes.deepCopy(),
      selectedTube: null,
      moveCount: 0,
      moveHistory: const [],
      completed: false,
      starCount: _calculateStars(stageNumber, 0),
      hintMove: null,
      lastMoveAnimation: null,
      invalidTubeIndices: const [],
      invalidAnimationNonce: 0,
      victoryNonce: 0,
      stageSelectionNonce: 0,
      isAnimating: false,
    );
  }

  MoveAnimation? _findHintMove(List<TubeModel> tubes) {
    MoveAnimation? fallback;

    for (int from = 0; from < tubes.length; from++) {
      for (int to = 0; to < tubes.length; to++) {
        final move = _buildMove(tubes, from, to);
        if (move == null) {
          continue;
        }

        final targetTube = tubes[to];
        if (!targetTube.isEmpty) {
          return move;
        }
        fallback ??= move;
      }
    }

    return fallback;
  }

  MoveAnimation? _buildMove(List<TubeModel> tubes, int fromIndex, int toIndex) {
    if (fromIndex == toIndex) {
      return null;
    }

    final fromTube = tubes[fromIndex];
    final toTube = tubes[toIndex];

    if (fromTube.isEmpty || toTube.isFull) {
      return null;
    }

    final movingColor = fromTube.topColor!;
    final movableGroupSize = fromTube.topGroupSize;
    final availableSpace = tubeCapacity - toTube.balls.length;

    if (!toTube.canAcceptColor(movingColor)) {
      return null;
    }

    final movedCount = min(movableGroupSize, availableSpace);
    if (movedCount <= 0) {
      return null;
    }

    return MoveAnimation(
      fromIndex: fromIndex,
      toIndex: toIndex,
      colorIndex: movingColor,
      movedCount: movedCount,
      sourceCountBefore: fromTube.balls.length,
      targetCountBefore: toTube.balls.length,
    );
  }

  List<TubeModel> _applyMove(List<TubeModel> tubes, MoveAnimation move) {
    final source = tubes[move.fromIndex];
    final target = tubes[move.toIndex];
    final moved = <int>[];

    for (int i = 0; i < move.movedCount; i++) {
      moved.add(source.balls.removeLast());
    }

    for (int i = moved.length - 1; i >= 0; i--) {
      target.balls.add(moved[i]);
    }

    return tubes;
  }

  bool _isSolved(List<TubeModel> tubes) {
    for (final tube in tubes) {
      if (tube.isEmpty) {
        continue;
      }

      if (!tube.isUniform) {
        return false;
      }
    }

    return true;
  }

  int _calculateStars(int stageNumber, int moves) {
    final definition = stageDefinitions[stageNumber - 1];

    if (moves <= definition.parMoves) {
      return 3;
    }
    if (moves <= definition.parMoves + 4) {
      return 2;
    }
    return 1;
  }
}

class MagicSortState {
  const MagicSortState({
    required this.currentStage,
    required this.unlockedStage,
    required this.bestStars,
    required this.tubes,
    required this.initialTubes,
    required this.selectedTube,
    required this.moveCount,
    required this.moveHistory,
    required this.completed,
    required this.starCount,
    required this.hintMove,
    required this.lastMoveAnimation,
    required this.invalidTubeIndices,
    required this.invalidAnimationNonce,
    required this.victoryNonce,
    required this.stageSelectionNonce,
    required this.isAnimating,
  });

  factory MagicSortState.initial() {
    return const MagicSortState(
      currentStage: 1,
      unlockedStage: 1,
      bestStars: {},
      tubes: [],
      initialTubes: [],
      selectedTube: null,
      moveCount: 0,
      moveHistory: [],
      completed: false,
      starCount: 3,
      hintMove: null,
      lastMoveAnimation: null,
      invalidTubeIndices: [],
      invalidAnimationNonce: 0,
      victoryNonce: 0,
      stageSelectionNonce: 0,
      isAnimating: false,
    );
  }

  final int currentStage;
  final int unlockedStage;
  final Map<int, int> bestStars;
  final List<TubeModel> tubes;
  final List<TubeModel> initialTubes;
  final int? selectedTube;
  final int moveCount;
  final List<MoveSnapshot> moveHistory;
  final bool completed;
  final int starCount;
  final HintMove? hintMove;
  final MoveAnimation? lastMoveAnimation;
  final List<int> invalidTubeIndices;
  final int invalidAnimationNonce;
  final int victoryNonce;
  final int stageSelectionNonce;
  final bool isAnimating;

  int get undoCount => moveHistory.length;

  MagicSortState copyWith({
    int? currentStage,
    int? unlockedStage,
    Map<int, int>? bestStars,
    List<TubeModel>? tubes,
    List<TubeModel>? initialTubes,
    int? selectedTube,
    bool clearSelection = false,
    int? moveCount,
    List<MoveSnapshot>? moveHistory,
    bool? completed,
    int? starCount,
    HintMove? hintMove,
    bool clearHint = false,
    MoveAnimation? lastMoveAnimation,
    List<int>? invalidTubeIndices,
    int? invalidAnimationNonce,
    int? victoryNonce,
    int? stageSelectionNonce,
    bool? isAnimating,
  }) {
    return MagicSortState(
      currentStage: currentStage ?? this.currentStage,
      unlockedStage: unlockedStage ?? this.unlockedStage,
      bestStars: bestStars ?? this.bestStars,
      tubes: tubes ?? this.tubes,
      initialTubes: initialTubes ?? this.initialTubes,
      selectedTube: clearSelection ? null : selectedTube ?? this.selectedTube,
      moveCount: moveCount ?? this.moveCount,
      moveHistory: moveHistory ?? this.moveHistory,
      completed: completed ?? this.completed,
      starCount: starCount ?? this.starCount,
      hintMove: clearHint ? null : hintMove ?? this.hintMove,
      lastMoveAnimation: lastMoveAnimation ?? this.lastMoveAnimation,
      invalidTubeIndices: invalidTubeIndices ?? this.invalidTubeIndices,
      invalidAnimationNonce:
          invalidAnimationNonce ?? this.invalidAnimationNonce,
      victoryNonce: victoryNonce ?? this.victoryNonce,
      stageSelectionNonce: stageSelectionNonce ?? this.stageSelectionNonce,
      isAnimating: isAnimating ?? this.isAnimating,
    );
  }
}

class StageDefinition {
  const StageDefinition({
    required this.stageNumber,
    required this.colorCount,
    required this.emptyTubeCount,
    required this.parMoves,
    required this.layout,
  });

  final int stageNumber;
  final int colorCount;
  final int emptyTubeCount;
  final int parMoves;
  final List<List<int>> layout;
}

const int tubeCapacity = 4;

const List<StageDefinition> stageDefinitions = [
  StageDefinition(
    stageNumber: 1,
    colorCount: 3,
    emptyTubeCount: 2,
    parMoves: 7,
    layout: [
      [0, 1, 2, 0],
      [1, 2, 0, 1],
      [2, 0, 1, 2],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 2,
    colorCount: 3,
    emptyTubeCount: 2,
    parMoves: 8,
    layout: [
      [0, 1, 1, 2],
      [2, 0, 2, 1],
      [1, 2, 0, 0],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 3,
    colorCount: 4,
    emptyTubeCount: 2,
    parMoves: 11,
    layout: [
      [0, 1, 2, 3],
      [3, 2, 1, 0],
      [1, 0, 3, 2],
      [2, 3, 0, 1],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 4,
    colorCount: 4,
    emptyTubeCount: 2,
    parMoves: 13,
    layout: [
      [0, 1, 2, 0],
      [2, 3, 1, 3],
      [1, 0, 3, 2],
      [3, 2, 0, 1],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 5,
    colorCount: 4,
    emptyTubeCount: 2,
    parMoves: 15,
    layout: [
      [0, 1, 2, 3],
      [1, 2, 3, 0],
      [2, 3, 0, 1],
      [3, 0, 1, 2],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 6,
    colorCount: 5,
    emptyTubeCount: 2,
    parMoves: 18,
    layout: [
      [0, 1, 2, 3],
      [4, 3, 2, 1],
      [0, 4, 3, 2],
      [1, 0, 4, 3],
      [2, 1, 0, 4],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 7,
    colorCount: 5,
    emptyTubeCount: 2,
    parMoves: 20,
    layout: [
      [0, 1, 2, 3],
      [4, 0, 1, 2],
      [3, 4, 0, 1],
      [2, 3, 4, 0],
      [1, 2, 3, 4],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 8,
    colorCount: 5,
    emptyTubeCount: 2,
    parMoves: 22,
    layout: [
      [0, 1, 2, 3],
      [4, 2, 1, 0],
      [1, 3, 4, 2],
      [0, 4, 3, 1],
      [2, 0, 4, 3],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 9,
    colorCount: 5,
    emptyTubeCount: 3,
    parMoves: 24,
    layout: [
      [0, 1, 2, 3],
      [4, 0, 2, 1],
      [3, 4, 1, 0],
      [2, 3, 0, 4],
      [1, 2, 4, 3],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 10,
    colorCount: 5,
    emptyTubeCount: 3,
    parMoves: 26,
    layout: [
      [0, 3, 1, 4],
      [0, 2, 1, 2],
      [3, 4, 0, 2],
      [4, 4, 1, 0],
      [3, 1, 3, 2],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 11,
    colorCount: 3,
    emptyTubeCount: 2,
    parMoves: 9,
    layout: [
      [1, 0, 0, 2],
      [2, 1, 2, 0],
      [1, 2, 1, 0],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 12,
    colorCount: 3,
    emptyTubeCount: 2,
    parMoves: 10,
    layout: [
      [1, 2, 1, 0],
      [0, 1, 2, 2],
      [2, 0, 0, 1],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 13,
    colorCount: 4,
    emptyTubeCount: 2,
    parMoves: 13,
    layout: [
      [0, 2, 1, 3],
      [2, 0, 3, 1],
      [1, 3, 0, 2],
      [3, 1, 2, 0],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 14,
    colorCount: 4,
    emptyTubeCount: 2,
    parMoves: 14,
    layout: [
      [0, 2, 1, 3],
      [2, 0, 3, 2],
      [1, 3, 2, 0],
      [3, 1, 0, 1],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 15,
    colorCount: 4,
    emptyTubeCount: 2,
    parMoves: 15,
    layout: [
      [1, 0, 2, 3],
      [2, 3, 1, 0],
      [3, 1, 0, 2],
      [0, 2, 3, 1],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 16,
    colorCount: 5,
    emptyTubeCount: 2,
    parMoves: 18,
    layout: [
      [3, 0, 4, 2],
      [4, 2, 1, 3],
      [4, 0, 3, 1],
      [0, 4, 2, 1],
      [2, 1, 3, 0],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 17,
    colorCount: 5,
    emptyTubeCount: 2,
    parMoves: 20,
    layout: [
      [3, 2, 4, 1],
      [4, 1, 0, 3],
      [0, 3, 2, 4],
      [2, 4, 1, 0],
      [1, 0, 3, 2],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 18,
    colorCount: 5,
    emptyTubeCount: 2,
    parMoves: 22,
    layout: [
      [1, 0, 2, 4],
      [3, 1, 4, 0],
      [4, 3, 2, 0],
      [2, 4, 1, 3],
      [3, 2, 0, 1],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 19,
    colorCount: 5,
    emptyTubeCount: 3,
    parMoves: 24,
    layout: [
      [0, 3, 4, 1],
      [1, 4, 0, 2],
      [2, 0, 1, 3],
      [4, 2, 0, 3],
      [3, 1, 2, 4],
      [],
      [],
    ],
  ),
  StageDefinition(
    stageNumber: 20,
    colorCount: 5,
    emptyTubeCount: 3,
    parMoves: 26,
    layout: [
      [0, 4, 0, 2],
      [0, 3, 1, 2],
      [1, 2, 4, 2],
      [1, 0, 4, 3],
      [3, 3, 4, 1],
      [],
      [],
    ],
  ),
];

class TubeModel {
  const TubeModel({required this.balls});

  final List<int> balls;

  bool get isEmpty => balls.isEmpty;

  bool get isFull => balls.length >= tubeCapacity;

  int? get topColor => balls.isEmpty ? null : balls.last;

  int get topGroupSize {
    if (balls.isEmpty) {
      return 0;
    }

    final color = balls.last;
    int count = 0;
    for (int i = balls.length - 1; i >= 0; i--) {
      if (balls[i] != color) {
        break;
      }
      count++;
    }
    return count;
  }

  bool get isUniform {
    if (balls.isEmpty) {
      return true;
    }

    final first = balls.first;
    return balls.every((color) => color == first);
  }

  bool canAcceptColor(int color) {
    if (isFull) {
      return false;
    }
    if (isEmpty) {
      return true;
    }
    return topColor == color;
  }

  TubeModel copy() => TubeModel(balls: List<int>.from(balls));
}

class MoveSnapshot {
  const MoveSnapshot({required this.tubes});

  final List<TubeModel> tubes;
}

class MoveAnimation {
  const MoveAnimation({
    required this.fromIndex,
    required this.toIndex,
    required this.colorIndex,
    required this.movedCount,
    required this.sourceCountBefore,
    required this.targetCountBefore,
  });

  final int fromIndex;
  final int toIndex;
  final int colorIndex;
  final int movedCount;
  final int sourceCountBefore;
  final int targetCountBefore;
}

class HintMove {
  const HintMove({required this.fromIndex, required this.toIndex});

  final int fromIndex;
  final int toIndex;
}

class ProgressRepository {
  ProgressRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String unlockedStageKey = 'unlocked_stage';
  static const String bestStarsKey = 'best_stars';

  int loadUnlockedStage() {
    return _prefs.getInt(unlockedStageKey) ?? 1;
  }

  Future<void> saveUnlockedStage(int stage) async {
    await _prefs.setInt(unlockedStageKey, stage);
  }

  Map<int, int> loadBestStars() {
    final raw = _prefs.getString(bestStarsKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        int.parse(entry.key): entry.value as int,
    };
  }

  Future<void> saveBestStars(Map<int, int> stars) async {
    final encoded = jsonEncode({
      for (final entry in stars.entries) '${entry.key}': entry.value,
    });
    await _prefs.setString(bestStarsKey, encoded);
  }
}

class MagicAudioService {
  AudioPlayer? _player;

  Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) {
      return existing;
    }

    final created = AudioPlayer();
    await created.setReleaseMode(ReleaseMode.stop);
    await created.setPlayerMode(PlayerMode.lowLatency);
    await created.setVolume(1);
    _player = created;
    return created;
  }

  Future<void> playSelect() async {
    await _playAssetOrFallback(
      assetPath: 'audio/select.mp3',
      fallback: SystemSoundType.click,
    );
  }

  Future<void> playMove() async {
    await _playAssetOrFallback(
      assetPath: 'audio/move.mp3',
      fallback: SystemSoundType.click,
    );
  }

  Future<void> playVictory() async {
    await _playAssetOrFallback(
      assetPath: 'audio/victory.mp3',
      fallback: SystemSoundType.alert,
    );
  }

  Future<void> playError() async {
    await _playAssetOrFallback(
      assetPath: 'audio/error.mp3',
      fallback: SystemSoundType.alert,
    );
  }

  Future<void> _playAssetOrFallback({
    required String assetPath,
    required SystemSoundType fallback,
  }) async {
    try {
      final player = await _ensurePlayer();
      await player.stop();
      await player.play(AssetSource(assetPath));
    } catch (_) {
      await SystemSound.play(fallback);
    }
  }
}

class BottleBoardGame extends FlameGame {
  BottleBoardGame({required this.onTubeTap});

  final ValueChanged<int> onTubeTap;

  MagicSortState _state = MagicSortState.initial();
  int _lastInvalidNonce = 0;
  int _lastVictoryNonce = 0;
  MoveAnimation? _animatingMove;
  double _animationProgress = 1;
  double _hintPulse = 0;
  final Random _random = Random(42);
  late final List<_SparkleParticle> _sparkles = List.generate(
    24,
    (_) => _SparkleParticle.random(_random),
  );
  final Map<int, double> _shakeTimers = {};

  void syncState(MagicSortState nextState) {
    _state = nextState;

    if (_lastInvalidNonce != nextState.invalidAnimationNonce) {
      _lastInvalidNonce = nextState.invalidAnimationNonce;
      for (final tubeIndex in nextState.invalidTubeIndices) {
        _shakeTimers[tubeIndex] = 0.36;
      }
    }

    if (nextState.lastMoveAnimation != null &&
        (_animatingMove == null ||
            nextState.lastMoveAnimation!.fromIndex !=
                _animatingMove!.fromIndex ||
            nextState.lastMoveAnimation!.toIndex != _animatingMove!.toIndex ||
            nextState.lastMoveAnimation!.sourceCountBefore !=
                _animatingMove!.sourceCountBefore ||
            nextState.lastMoveAnimation!.targetCountBefore !=
                _animatingMove!.targetCountBefore)) {
      _animatingMove = nextState.lastMoveAnimation;
      _animationProgress = 0;
    }

    if (_lastVictoryNonce != nextState.victoryNonce) {
      _lastVictoryNonce = nextState.victoryNonce;
      if (nextState.victoryNonce > 0) {
        for (int i = 0; i < _state.tubes.length; i++) {
          _shakeTimers[i] = 0.6;
        }
      }
    }
  }

  void handleTap(Offset localPosition, Size boardSize) {
    if (_state.tubes.isEmpty) {
      return;
    }

    final rects = _computeTubeRects(boardSize, _state.tubes.length);
    for (int i = 0; i < rects.length; i++) {
      if (rects[i].inflate(8).contains(localPosition)) {
        onTubeTap(i);
        break;
      }
    }
  }

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  void update(double dt) {
    super.update(dt);

    _hintPulse += dt * 2.5;

    if (_animatingMove != null) {
      _animationProgress += dt * 2.8;
      if (_animationProgress >= 1) {
        _animationProgress = 1;
      }
    }

    final finishedShakes = <int>[];
    _shakeTimers.forEach((index, time) {
      final remaining = time - dt;
      if (remaining <= 0) {
        finishedShakes.add(index);
      } else {
        _shakeTimers[index] = remaining;
      }
    });
    for (final index in finishedShakes) {
      _shakeTimers.remove(index);
    }

    for (final sparkle in _sparkles) {
      sparkle.update(dt, _random);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (_state.tubes.isEmpty) {
      return;
    }

    _renderSparkles(canvas);

    final rects = _computeTubeRects(size.toSize(), _state.tubes.length);
    final tubeWidth = rects.first.width;

    if (_state.hintMove != null) {
      _renderHintPath(canvas, rects, _state.hintMove!);
    }

    for (int i = 0; i < _state.tubes.length; i++) {
      final rect = rects[i];
      final tube = _state.tubes[i];
      final isSelected = i == _state.selectedTube;
      final isHintSource = _state.hintMove?.fromIndex == i;
      final isHintTarget = _state.hintMove?.toIndex == i;
      final shakeOffset = _shakeOffset(i);

      canvas.save();
      canvas.translate(shakeOffset, 0);
      _renderTube(
        canvas,
        rect,
        tube,
        isSelected: isSelected,
        isHintSource: isHintSource,
        isHintTarget: isHintTarget,
        tubeWidth: tubeWidth,
      );
      canvas.restore();
    }

    _renderMoveAnimation(canvas, rects);
  }

  List<Rect> _computeTubeRects(Size boardSize, int count) {
    const double horizontalPadding = 24;
    const double topPadding = 22;
    const double bottomPadding = 36;
    const double gap = 16;
    final availableWidth = boardSize.width - horizontalPadding * 2;
    final baseTubeWidth = min(
      92.0,
      (availableWidth - gap * (count - 1)) / count,
    );
    final tubeWidth = max(56.0, baseTubeWidth);
    final totalWidth = tubeWidth * count + gap * (count - 1);
    final startX = (boardSize.width - totalWidth) / 2;
    final tubeHeight = min(
      boardSize.height - topPadding - bottomPadding,
      boardSize.height * 0.72,
    );
    final top = max(topPadding, (boardSize.height - tubeHeight) / 2 - 8);

    return List.generate(count, (index) {
      final left = startX + index * (tubeWidth + gap);
      return Rect.fromLTWH(left, top, tubeWidth, tubeHeight);
    });
  }

  void _renderSparkles(Canvas canvas) {
    for (final sparkle in _sparkles) {
      final paint =
          Paint()
            ..color = Colors.white.withValues(alpha: sparkle.alpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        Offset(sparkle.x * size.x, sparkle.y * size.y),
        sparkle.radius,
        paint,
      );
    }
  }

  void _renderHintPath(Canvas canvas, List<Rect> rects, HintMove hintMove) {
    final start = Offset(
      rects[hintMove.fromIndex].center.dx,
      rects[hintMove.fromIndex].top + 24,
    );
    final end = Offset(
      rects[hintMove.toIndex].center.dx,
      rects[hintMove.toIndex].top + 24,
    );
    final path =
        Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(
            (start.dx + end.dx) / 2,
            min(start.dy, end.dy) - 40,
            end.dx,
            end.dy,
          );

    final pulse = (sin(_hintPulse) + 1) / 2;
    final paint =
        Paint()
          ..color = const Color(
            0xFFFFE066,
          ).withValues(alpha: 0.28 + pulse * 0.32)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(path, paint);
  }

  void _renderTube(
    Canvas canvas,
    Rect rect,
    TubeModel tube, {
    required bool isSelected,
    required bool isHintSource,
    required bool isHintTarget,
    required double tubeWidth,
  }) {
    final outerRRect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(tubeWidth * 0.4),
    );
    final innerRect = Rect.fromLTWH(
      rect.left + tubeWidth * 0.14,
      rect.top + tubeWidth * 0.12,
      rect.width - tubeWidth * 0.28,
      rect.height - tubeWidth * 0.18,
    );
    if (isSelected || isHintSource || isHintTarget) {
      final glowColor =
          isHintTarget ? const Color(0xFFFFE066) : const Color(0xFF8F65FF);
      final glowPaint =
          Paint()
            ..color = glowColor.withValues(alpha: isSelected ? 0.45 : 0.30)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
      canvas.drawRRect(outerRRect.inflate(6), glowPaint);
    }

    final glassPaint =
        Paint()
          ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0.08),
          ]);
    canvas.drawRRect(outerRRect, glassPaint);

    final outlinePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
            Colors.white.withValues(alpha: 0.78),
            Colors.white.withValues(alpha: 0.18),
          ]);
    canvas.drawRRect(outerRRect, outlinePaint);

    final glossPaint =
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(rect.left, rect.top),
            Offset(rect.left + rect.width * 0.4, rect.bottom),
            [
              Colors.white.withValues(alpha: 0.24),
              Colors.white.withValues(alpha: 0.02),
            ],
          );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rect.left + 8,
          rect.top + 8,
          rect.width * 0.22,
          rect.height - 16,
        ),
        const Radius.circular(16),
      ),
      glossPaint,
    );

    final orbRadius = innerRect.width * 0.36;
    final verticalSpacing = innerRect.height / tubeCapacity;

    for (int i = 0; i < tube.balls.length; i++) {
      final colorIndex = tube.balls[i];
      final center = Offset(
        innerRect.center.dx,
        innerRect.bottom - verticalSpacing * (i + 0.5),
      );
      _renderOrb(canvas, center, orbRadius, magicColors[colorIndex]);
    }
  }

  void _renderOrb(Canvas canvas, Offset center, double radius, Color color) {
    final glowPaint =
        Paint()
          ..color = color.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(center, radius * 1.25, glowPaint);

    final orbPaint =
        Paint()
          ..shader = ui.Gradient.radial(
            center.translate(-radius * 0.18, -radius * 0.22),
            radius * 1.4,
            [
              Colors.white.withValues(alpha: 0.95),
              color.withValues(alpha: 0.98),
              color.withValues(alpha: 0.72),
            ],
            [0, 0.18, 1],
          );
    canvas.drawCircle(center, radius, orbPaint);

    final shinePaint = Paint()..color = Colors.white.withValues(alpha: 0.65);
    canvas.drawCircle(
      center.translate(-radius * 0.25, -radius * 0.28),
      radius * 0.18,
      shinePaint,
    );
  }

  void _renderMoveAnimation(Canvas canvas, List<Rect> rects) {
    final move = _animatingMove;
    if (move == null || _animationProgress >= 1) {
      return;
    }

    final fromRect = rects[move.fromIndex];
    final toRect = rects[move.toIndex];
    final orbColor = magicColors[move.colorIndex];
    final liftedY = min(fromRect.top, toRect.top) - 40;

    final start = Offset(
      fromRect.center.dx,
      fromRect.bottom -
          fromRect.height / tubeCapacity * (move.sourceCountBefore - 0.5),
    );
    final lift = Offset(fromRect.center.dx, liftedY);
    final drop = Offset(toRect.center.dx, liftedY);
    final end = Offset(
      toRect.center.dx,
      toRect.bottom -
          toRect.height / tubeCapacity * (move.targetCountBefore + 0.5),
    );

    final t = Curves.easeInOut.transform(_animationProgress.clamp(0, 1));
    final point = _bezierLerp(start, lift, drop, end, t);
    _renderOrb(canvas, point, fromRect.width * 0.19, orbColor);
  }

  Offset _bezierLerp(Offset a, Offset b, Offset c, Offset d, double t) {
    final ab = Offset.lerp(a, b, t)!;
    final bc = Offset.lerp(b, c, t)!;
    final cd = Offset.lerp(c, d, t)!;
    final abbc = Offset.lerp(ab, bc, t)!;
    final bccd = Offset.lerp(bc, cd, t)!;
    return Offset.lerp(abbc, bccd, t)!;
  }

  double _shakeOffset(int index) {
    final timer = _shakeTimers[index];
    if (timer == null) {
      return 0;
    }
    return sin(timer * 38) * 8;
  }
}

class BottleBoardPainter extends CustomPainter {
  BottleBoardPainter({required this.state});

  final MagicSortState state;

  @override
  void paint(Canvas canvas, Size size) {
    if (state.tubes.isEmpty) {
      return;
    }

    final rects = _computeTubeRects(size, state.tubes.length);
    final tubeWidth = rects.first.width;

    if (state.hintMove != null) {
      _renderHintPath(canvas, rects, state.hintMove!);
    }

    for (int i = 0; i < state.tubes.length; i++) {
      final rect = rects[i];
      final tube = state.tubes[i];
      final isSelected = i == state.selectedTube;
      final isHintSource = state.hintMove?.fromIndex == i;
      final isHintTarget = state.hintMove?.toIndex == i;

      _renderTube(
        canvas,
        rect,
        tube,
        isSelected: isSelected,
        isHintSource: isHintSource,
        isHintTarget: isHintTarget,
        tubeWidth: tubeWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BottleBoardPainter oldDelegate) {
    return oldDelegate.state != state;
  }
}

class BottleBoardOverlay extends StatelessWidget {
  const BottleBoardOverlay({
    super.key,
    required this.state,
    required this.onTubeTap,
  });

  final MagicSortState state;
  final ValueChanged<int> onTubeTap;

  @override
  Widget build(BuildContext context) {
    if (state.tubes.isEmpty) {
      return const SizedBox.expand();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final rects = _computeTubeRects(
          Size(constraints.maxWidth, constraints.maxHeight),
          state.tubes.length,
        );

        return Stack(
          children: [
            for (int i = 0; i < state.tubes.length; i++)
              Positioned(
                left: rects[i].left,
                top: rects[i].top,
                width: rects[i].width,
                height: rects[i].height,
                child: _TubeWidget(
                  tube: state.tubes[i],
                  isSelected: i == state.selectedTube,
                  isHintSource: state.hintMove?.fromIndex == i,
                  isHintTarget: state.hintMove?.toIndex == i,
                  onTap: () => onTubeTap(i),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TubeWidget extends StatelessWidget {
  const _TubeWidget({
    required this.tube,
    required this.isSelected,
    required this.isHintSource,
    required this.isHintTarget,
    required this.onTap,
  });

  final TubeModel tube;
  final bool isSelected;
  final bool isHintSource;
  final bool isHintTarget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final glowColor =
        isHintTarget ? const Color(0xFFFFE066) : const Color(0xFF8F65FF);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.28),
              Colors.white.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(
              alpha: isSelected || isHintSource || isHintTarget ? 0.68 : 0.24,
            ),
            width: isSelected ? 2.4 : 1.6,
          ),
          boxShadow: [
            if (isSelected || isHintSource || isHintTarget)
              BoxShadow(
                color: glowColor.withValues(alpha: 0.45),
                blurRadius: 24,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (int slot = tubeCapacity - 1; slot >= 0; slot--)
              Expanded(
                child: Center(
                  child:
                      slot < tube.balls.length
                          ? _OrbWidget(color: magicColors[tube.balls[slot]])
                          : Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrbWidget extends StatelessWidget {
  const _OrbWidget({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.25, -0.25),
          radius: 0.95,
          colors: [
            Colors.white.withValues(alpha: 0.95),
            color.withValues(alpha: 0.98),
            color.withValues(alpha: 0.76),
          ],
          stops: const [0.0, 0.18, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Align(
        alignment: const Alignment(-0.25, -0.25),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

List<Rect> _computeTubeRects(Size boardSize, int count) {
  const double horizontalPadding = 24;
  const double topPadding = 22;
  const double bottomPadding = 36;
  const double gap = 16;
  final availableWidth = boardSize.width - horizontalPadding * 2;
  final baseTubeWidth = min(92.0, (availableWidth - gap * (count - 1)) / count);
  final tubeWidth = max(56.0, baseTubeWidth);
  final totalWidth = tubeWidth * count + gap * (count - 1);
  final startX = (boardSize.width - totalWidth) / 2;
  final tubeHeight = min(
    boardSize.height - topPadding - bottomPadding,
    boardSize.height * 0.72,
  );
  final top = max(topPadding, (boardSize.height - tubeHeight) / 2 - 8);

  return List.generate(count, (index) {
    final left = startX + index * (tubeWidth + gap);
    return Rect.fromLTWH(left, top, tubeWidth, tubeHeight);
  });
}

void _renderHintPath(Canvas canvas, List<Rect> rects, HintMove hintMove) {
  final start = Offset(
    rects[hintMove.fromIndex].center.dx,
    rects[hintMove.fromIndex].top + 24,
  );
  final end = Offset(
    rects[hintMove.toIndex].center.dx,
    rects[hintMove.toIndex].top + 24,
  );
  final path =
      Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(
          (start.dx + end.dx) / 2,
          min(start.dy, end.dy) - 40,
          end.dx,
          end.dy,
        );

  final paint =
      Paint()
        ..color = const Color(0xFFFFE066).withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
  canvas.drawPath(path, paint);
}

void _renderTube(
  Canvas canvas,
  Rect rect,
  TubeModel tube, {
  required bool isSelected,
  required bool isHintSource,
  required bool isHintTarget,
  required double tubeWidth,
}) {
  final outerRRect = RRect.fromRectAndRadius(
    rect,
    Radius.circular(tubeWidth * 0.4),
  );
  final innerRect = Rect.fromLTWH(
    rect.left + tubeWidth * 0.14,
    rect.top + tubeWidth * 0.12,
    rect.width - tubeWidth * 0.28,
    rect.height - tubeWidth * 0.18,
  );

  if (isSelected || isHintSource || isHintTarget) {
    final glowColor =
        isHintTarget ? const Color(0xFFFFE066) : const Color(0xFF8F65FF);
    final glowPaint =
        Paint()
          ..color = glowColor.withValues(alpha: isSelected ? 0.45 : 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawRRect(outerRRect.inflate(6), glowPaint);
  }

  final glassPaint =
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          Colors.white.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.08),
        ]);
  canvas.drawRRect(outerRRect, glassPaint);

  final outlinePaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          Colors.white.withValues(alpha: 0.78),
          Colors.white.withValues(alpha: 0.18),
        ]);
  canvas.drawRRect(outerRRect, outlinePaint);

  final glossPaint =
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(rect.left, rect.top),
          Offset(rect.left + rect.width * 0.4, rect.bottom),
          [
            Colors.white.withValues(alpha: 0.24),
            Colors.white.withValues(alpha: 0.02),
          ],
        );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(
        rect.left + 8,
        rect.top + 8,
        rect.width * 0.22,
        rect.height - 16,
      ),
      const Radius.circular(16),
    ),
    glossPaint,
  );

  final orbRadius = innerRect.width * 0.36;
  final verticalSpacing = innerRect.height / tubeCapacity;

  for (int i = 0; i < tube.balls.length; i++) {
    final colorIndex = tube.balls[i];
    final center = Offset(
      innerRect.center.dx,
      innerRect.bottom - verticalSpacing * (i + 0.5),
    );
    _renderOrb(canvas, center, orbRadius, magicColors[colorIndex]);
  }
}

void _renderOrb(Canvas canvas, Offset center, double radius, Color color) {
  final glowPaint =
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
  canvas.drawCircle(center, radius * 1.25, glowPaint);

  final orbPaint =
      Paint()
        ..shader = ui.Gradient.radial(
          center.translate(-radius * 0.18, -radius * 0.22),
          radius * 1.4,
          [
            Colors.white.withValues(alpha: 0.95),
            color.withValues(alpha: 0.98),
            color.withValues(alpha: 0.72),
          ],
          [0, 0.18, 1],
        );
  canvas.drawCircle(center, radius, orbPaint);

  final shinePaint = Paint()..color = Colors.white.withValues(alpha: 0.65);
  canvas.drawCircle(
    center.translate(-radius * 0.25, -radius * 0.28),
    radius * 0.18,
    shinePaint,
  );
}

class _SparkleParticle {
  _SparkleParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.radius,
    required this.alpha,
  });

  factory _SparkleParticle.random(Random random) {
    return _SparkleParticle(
      x: random.nextDouble(),
      y: random.nextDouble(),
      speed: 0.015 + random.nextDouble() * 0.03,
      radius: 1 + random.nextDouble() * 2.6,
      alpha: 0.08 + random.nextDouble() * 0.22,
    );
  }

  double x;
  double y;
  double speed;
  double radius;
  double alpha;

  void update(double dt, Random random) {
    y -= speed * dt;
    if (y < -0.05) {
      y = 1.05;
      x = random.nextDouble();
      alpha = 0.08 + random.nextDouble() * 0.22;
      radius = 1 + random.nextDouble() * 2.6;
    }
  }
}

const List<Color> magicColors = [
  Color(0xFFFF5D8F),
  Color(0xFF4DA3FF),
  Color(0xFF47F3A0),
  Color(0xFFFFD74A),
  Color(0xFFC36CFF),
  Color(0xFFFF8A3D),
];

extension TubeCopyExtension on List<TubeModel> {
  List<TubeModel> deepCopy() {
    return map((tube) => tube.copy()).toList(growable: true);
  }
}

extension RetainLastExtension<T> on List<T> {
  void retainLast(int count) {
    if (length <= count) {
      return;
    }
    removeRange(0, length - count);
  }
}
