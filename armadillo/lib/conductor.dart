// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:keyboard/keyboard.dart';
import 'package:sysui_widgets/device_extension_state.dart';

import 'armadillo_overlay.dart';
import 'device_extender.dart';
import 'edge_scroll_drag_target.dart';
import 'expand_suggestion.dart';
import 'keyboard_device_extension.dart';
import 'quick_settings.dart';
import 'nothing.dart';
import 'now.dart';
import 'peek_manager.dart';
import 'peeking_overlay.dart';
import 'scroll_locker.dart';
import 'selected_suggestion_overlay.dart';
import 'size_model.dart';
import 'splash_suggestion.dart';
import 'story.dart';
import 'story_cluster.dart';
import 'story_cluster_drag_state_model.dart';
import 'story_drag_transition_model.dart';
import 'story_list.dart';
import 'story_model.dart';
import 'suggestion.dart';
import 'suggestion_list.dart';
import 'suggestion_model.dart';
import 'vertical_shifter.dart';

/// The height of [Now]'s bar when minimized.
const double _kMinimizedNowHeight = 50.0;

/// The height of [Now] when maximized.
const double _kMaximizedNowHeight = 440.0;

/// How far [Now] should raise when quick settings is activated inline.
const double _kQuickSettingsHeightBump = 120.0;

/// How far above the bottom the suggestions overlay peeks.
const double _kSuggestionOverlayPeekHeight = 116.0;

/// If the width of the [Conductor] exceeds this value we will switch to
/// multicolumn mode for the [StoryList].
const double _kStoryListMultiColumnWidthThreshold = 500.0;

/// If the width of the [Conductor] exceeds this value we will switch to
/// two column mode for the [SuggestionList].
const double _kSuggestionListTwoColumnWidthThreshold = 700.0;

/// If the width of the [Conductor] exceeds this value we will switch to
/// three column mode for the [SuggestionList].
const double _kSuggestionListThreeColumnWidthThreshold = 1000.0;

const double _kSuggestionOverlayPullScrollOffset = 100.0;
const double _kSuggestionOverlayScrollFactor = 1.2;

final GlobalKey<SuggestionListState> _suggestionListKey =
    new GlobalKey<SuggestionListState>();
final ScrollController _suggestionListScrollController = new ScrollController();
final GlobalKey<NowState> _nowKey = new GlobalKey<NowState>();
final GlobalKey<QuickSettingsOverlayState> _quickSettingsOverlayKey =
    new GlobalKey<QuickSettingsOverlayState>();
final GlobalKey<PeekingOverlayState> _suggestionOverlayKey =
    new GlobalKey<PeekingOverlayState>();
final GlobalKey<DeviceExtensionState<KeyboardDeviceExtension>>
    _keyboardDeviceExtensionKey =
    new GlobalKey<DeviceExtensionState<KeyboardDeviceExtension>>();
final GlobalKey<KeyboardState> _keyboardKey = new GlobalKey<KeyboardState>();

/// The [VerticalShifter] is used to shift the [StoryList] up when [Now]'s
/// inline quick settings are activated.
final GlobalKey<VerticalShifterState> _verticalShifterKey =
    new GlobalKey<VerticalShifterState>();

final ScrollController _scrollController = new ScrollController();
final GlobalKey<ScrollLockerState> _scrollLockerKey =
    new GlobalKey<ScrollLockerState>();
final GlobalKey<EdgeScrollDragTargetState> _edgeScrollDragTargetKey =
    new GlobalKey<EdgeScrollDragTargetState>();

/// The key for adding [Suggestion]s to the [SelectedSuggestionOverlay].  This
/// is to allow us to animate from a [Suggestion] in an open [SuggestionList]
/// to a [Story] focused in the [StoryList].
final GlobalKey<SelectedSuggestionOverlayState> _selectedSuggestionOverlayKey =
    new GlobalKey<SelectedSuggestionOverlayState>();

final GlobalKey<ArmadilloOverlayState> _overlayKey =
    new GlobalKey<ArmadilloOverlayState>();

/// Called when an overlay becomes active or inactive.
typedef void OnOverlayChanged(bool active);

/// Manages the position, size, and state of the story list, user context,
/// suggestion overlay, device extensions. interruption overlay, and quick
/// settings overlay.
// TODO(pylaligand): mark class as @immutable.
// ignore: must_be_immutable
class Conductor extends StatelessWidget {
  /// Set to true to use a software keyboard when asking.
  final bool useSoftKeyboard;

  /// Set to true to blur scrimmed children when performing an inline preview.
  final bool blurScrimmedChildren;

  /// Called when the quick settings overlay becomes active or inactive.
  final OnOverlayChanged onQuickSettingsOverlayChanged;

  /// Called when the suggestions overlay becomes active or inactive.
  final OnOverlayChanged onSuggestionsOverlayChanged;

  /// Called when the user selects log out from the quick settings.
  final VoidCallback onLogoutSelected;

  final PeekManager _peekManager;
  bool _ignoreNextScrollOffsetChange = false;

  /// Constructor.  [storyClusterDragStateModel] is used to create a
  /// [PeekManager] for the suggestion list's peeking overlay.
  Conductor({
    this.useSoftKeyboard: true,
    this.blurScrimmedChildren,
    this.onQuickSettingsOverlayChanged,
    this.onSuggestionsOverlayChanged,
    this.onLogoutSelected,
    StoryClusterDragStateModel storyClusterDragStateModel,
  })
      : _peekManager = new PeekManager(
          peekingOverlayKey: _suggestionOverlayKey,
          storyClusterDragStateModel: storyClusterDragStateModel,
        );

  /// Note in particular the magic we're employing here to make the user
  /// state appear to be a part of the story list:
  /// By giving the story list bottom padding and clipping its bottom to the
  /// size of the final user state bar we have the user state appear to be
  /// a part of the story list and yet prevent the story list from painting
  /// behind it.
  @override
  Widget build(BuildContext context) => new LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth == 0.0 || constraints.maxHeight == 0.0) {
            return new Offstage(offstage: true);
          }
          Size fullSize = new Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          StoryModel storyModel = StoryModel.of(context);

          storyModel.updateLayouts(fullSize);

          Widget stack = new Stack(
            fit: StackFit.passthrough,
            children: <Widget>[
              /// Story List.
              new ScopedModelDescendant<StoryDragTransitionModel>(
                builder: (
                  BuildContext context,
                  Widget child,
                  StoryDragTransitionModel storyDragTransitionModel,
                ) =>
                    new Positioned(
                      left: 0.0,
                      right: 0.0,
                      top: 0.0,
                      bottom: lerpDouble(
                        _kMinimizedNowHeight,
                        0.0,
                        storyDragTransitionModel.progress,
                      ),
                      child: child,
                    ),
                child: _getStoryList(
                  storyModel,
                  constraints.maxWidth,
                  new Size(
                    fullSize.width,
                    fullSize.height - _kMinimizedNowHeight,
                  ),
                ),
              ),

              // Now.
              _getNow(storyModel, constraints.maxWidth),

              // Suggestions Overlay.
              _getSuggestionOverlay(
                SuggestionModel.of(context),
                storyModel,
                constraints.maxWidth,
              ),

              // Selected Suggestion Overlay.
              _getSelectedSuggestionOverlay(),

              // Quick Settings Overlay.
              new QuickSettingsOverlay(
                key: _quickSettingsOverlayKey,
                minimizedNowBarHeight: _kMinimizedNowHeight,
                onProgressChanged: (double progress) {
                  if (progress == 0.0) {
                    onQuickSettingsOverlayChanged?.call(false);
                  } else {
                    onQuickSettingsOverlayChanged?.call(true);
                  }
                },
                onLogoutSelected: onLogoutSelected,
              ),

              // Top and bottom edge scrolling drag targets.
              new Positioned(
                top: 0.0,
                left: 0.0,
                right: 0.0,
                bottom: 0.0,
                child: new EdgeScrollDragTarget(
                  key: _edgeScrollDragTargetKey,
                  scrollController: _scrollController,
                ),
              ),

              // This layout builder tracks the size available for the
              // suggestion overlay and sets its maxHeight appropriately.
              // TODO(apwilson): refactor this to not be so weird.
              new LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  double targetMaxHeight = 0.8 * constraints.maxHeight;
                  if (_suggestionOverlayKey.currentState.maxHeight !=
                          targetMaxHeight &&
                      targetMaxHeight != 0.0) {
                    _suggestionOverlayKey.currentState.maxHeight =
                        targetMaxHeight;
                    if (!_suggestionOverlayKey.currentState.hiding) {
                      _suggestionOverlayKey.currentState.show();
                    }
                  }
                  return Nothing.widget;
                },
              ),
            ],
          );
          return useSoftKeyboard
              ? new DeviceExtender(
                  deviceExtensions: <Widget>[_getKeyboard()],
                  child: stack,
                )
              : stack;
        },
      );

  Widget _getKeyboard() => new KeyboardDeviceExtension(
        key: _keyboardDeviceExtensionKey,
        keyboardKey: _keyboardKey,
        onText: (String text) => _suggestionListKey.currentState.append(text),
        onSuggestion: (String suggestion) =>
            _suggestionListKey.currentState.onSuggestion(suggestion),
        onDelete: () => _suggestionListKey.currentState.backspace(),
        onGo: () {
          _suggestionListKey.currentState.selectFirstSuggestions();
        },
      );

  Widget _getStoryList(
    StoryModel storyModel,
    double maxWidth,
    Size parentSize,
  ) =>
      new VerticalShifter(
        key: _verticalShifterKey,
        verticalShift: _kQuickSettingsHeightBump,
        child: new ScrollLocker(
          key: _scrollLockerKey,
          child: new ScopedModelDescendant<StoryDragTransitionModel>(
            builder: (
              BuildContext context,
              Widget child,
              StoryDragTransitionModel storyDragTransitionModel,
            ) =>
                new StoryList(
                  scrollController: _scrollController,
                  overlayKey: _overlayKey,
                  blurScrimmedChildren: blurScrimmedChildren,
                  bottomPadding: _kMaximizedNowHeight +
                      lerpDouble(
                        0.0,
                        _kMinimizedNowHeight,
                        storyDragTransitionModel.progress,
                      ),
                  onScroll: (double scrollOffset) {
                    if (_ignoreNextScrollOffsetChange) {
                      _ignoreNextScrollOffsetChange = false;
                      return;
                    }
                    _nowKey.currentState.scrollOffset = scrollOffset;

                    // Peak suggestion overlay more when overscrolling.
                    if (scrollOffset < -_kSuggestionOverlayPullScrollOffset &&
                        _suggestionOverlayKey.currentState.hiding) {
                      _suggestionOverlayKey.currentState.setHeight(
                        _kSuggestionOverlayPeekHeight -
                            (scrollOffset +
                                    _kSuggestionOverlayPullScrollOffset) *
                                _kSuggestionOverlayScrollFactor,
                      );
                    }
                  },
                  onStoryClusterFocusStarted: () {
                    // Lock scrolling.
                    _scrollLockerKey.currentState.lock();
                    _edgeScrollDragTargetKey.currentState.disable();
                    _minimizeNow();
                  },
                  onStoryClusterFocusCompleted: (StoryCluster storyCluster) {
                    _focusStoryCluster(storyModel, storyCluster);
                  },
                  parentSize: parentSize,
                  onStoryClusterVerticalEdgeHover: () => goToOrigin(storyModel),
                ),
          ),
        ),
      );

  // We place Now in a RepaintBoundary as its animations
  // don't require its parent and siblings to redraw.
  Widget _getNow(StoryModel storyModel, double parentWidth) =>
      new RepaintBoundary(
        child: new Now(
          key: _nowKey,
          parentWidth: parentWidth,
          minHeight: _kMinimizedNowHeight,
          maxHeight: _kMaximizedNowHeight,
          quickSettingsHeightBump: _kQuickSettingsHeightBump,
          onQuickSettingsProgressChange: (double quickSettingsProgress) =>
              _verticalShifterKey.currentState.shiftProgress =
                  quickSettingsProgress,
          onMinimizedTap: () => goToOrigin(storyModel),
          onMinimizedLongPress: () =>
              _quickSettingsOverlayKey.currentState.show(),
          onQuickSettingsMaximized: () {
            // When quick settings starts being shown, scroll to 0.0.
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.fastOutSlowIn,
            );
          },
          onMinimize: () {
            _peekManager.nowMinimized = true;
            _suggestionOverlayKey.currentState.hide();
          },
          onMaximize: () {
            _peekManager.nowMinimized = false;
            _suggestionOverlayKey.currentState.hide();
          },
          onBarVerticalDragUpdate: (DragUpdateDetails details) =>
              _suggestionOverlayKey.currentState.onVerticalDragUpdate(details),
          onBarVerticalDragEnd: (DragEndDetails details) =>
              _suggestionOverlayKey.currentState.onVerticalDragEnd(details),
          onOverscrollThresholdRelease: () =>
              _suggestionOverlayKey.currentState.show(),
          scrollController: _scrollController,
          onLogoutSelected: onLogoutSelected,
        ),
      );

  Widget _getSuggestionOverlay(
    SuggestionModel suggestionModel,
    StoryModel storyModel,
    double maxWidth,
  ) =>
      new PeekingOverlay(
        key: _suggestionOverlayKey,
        peekHeight: _kSuggestionOverlayPeekHeight,
        parentWidth: maxWidth,
        onHide: () {
          onSuggestionsOverlayChanged?.call(false);
          if (useSoftKeyboard) {
            _keyboardDeviceExtensionKey.currentState?.hide();
          }
          if (_suggestionListScrollController.hasClients) {
            _suggestionListScrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 1000),
              curve: Curves.fastOutSlowIn,
            );
          }
          _suggestionListKey.currentState?.clear();
          _suggestionListKey.currentState?.stopAsking();
        },
        onShow: () {
          onSuggestionsOverlayChanged?.call(true);
        },
        child: new SuggestionList(
          key: _suggestionListKey,
          scrollController: _suggestionListScrollController,
          columnCount: maxWidth > _kSuggestionListThreeColumnWidthThreshold
              ? 3
              : maxWidth > _kSuggestionListTwoColumnWidthThreshold ? 2 : 1,
          onAskingStarted: () {
            _suggestionOverlayKey.currentState.show();
            if (useSoftKeyboard) {
              _keyboardDeviceExtensionKey.currentState.show();
            }
          },
          onAskingEnded: () {
            if (useSoftKeyboard) {
              _keyboardDeviceExtensionKey.currentState.hide();
            }
          },
          onAskTextChanged: (String text) {
            if (useSoftKeyboard) {
              _keyboardKey.currentState.updateSuggestions(
                _suggestionListKey.currentState.text,
              );
            }
          },
          onSuggestionSelected: (Suggestion suggestion, Rect globalBounds) {
            suggestionModel.onSuggestionSelected(suggestion);

            if (suggestion.selectionType == SelectionType.closeSuggestions) {
              _suggestionOverlayKey.currentState.hide();
            } else {
              _selectedSuggestionOverlayKey.currentState.suggestionSelected(
                expansionBehavior:
                    suggestion.selectionType == SelectionType.launchStory
                        ? new ExpandSuggestion(
                            suggestion: suggestion,
                            suggestionInitialGlobalBounds: globalBounds,
                            onSuggestionExpanded: (Suggestion suggestion) =>
                                _focusOnStory(
                                  suggestion.selectionStoryId,
                                  storyModel,
                                ),
                            bottomMargin: _kMinimizedNowHeight,
                          )
                        : new SplashSuggestion(
                            suggestion: suggestion,
                            suggestionInitialGlobalBounds: globalBounds,
                            onSuggestionExpanded: (Suggestion suggestion) =>
                                _focusOnStory(
                                  suggestion.selectionStoryId,
                                  storyModel,
                                ),
                          ),
              );
              _minimizeNow();
            }
          },
        ),
      );

  // This is only visible in transitoning the user from a Suggestion
  // in an open SuggestionList to a focused Story in the StoryList.
  Widget _getSelectedSuggestionOverlay() => new SelectedSuggestionOverlay(
        key: _selectedSuggestionOverlayKey,
      );

  void _defocus(StoryModel storyModel) {
    // Unfocus all story clusters.
    storyModel.activeSortedStoryClusters.forEach(
      (StoryCluster storyCluster) => storyCluster.unFocus(),
    );

    // Unlock scrolling.
    _scrollLockerKey.currentState.unlock();
    _edgeScrollDragTargetKey.currentState.enable();
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.fastOutSlowIn,
    );
  }

  void _focusStoryCluster(
    StoryModel storyModel,
    StoryCluster storyCluster,
  ) {
    // Tell the [StoryModel] the story is now in focus.  This will move the
    // [Story] to the front of the [StoryList].
    storyModel.interactionStarted(storyCluster);

    // We need to set the scroll offset to 0.0 to ensure the story
    // bars don't become untouchable when fully focused:
    // If we're at a scroll offset other than zero, the RenderStoryListBody
    // might not be as big as it would need to be to fully cover the screen and
    // thus would have areas where its painting but not receiving hit testing.
    // Right now the RenderStoryListBody ensures that its at least the size of
    // the screen when we're focused but doesn't take into account the scroll
    // offset.  It seems weird to size the RenderStoryListBody based on the
    // scroll offset and it also seems weird to scroll to offset 0.0 from some
    // arbitrary scroll offset when we defocus so this solves both issues with
    // one stone.
    //
    // If we don't ignore the onScroll resulting from setting the scroll offset
    // to 0.0 we will inadvertently maximize now and peek the suggestion
    // overlay.
    _ignoreNextScrollOffsetChange = true;
    _scrollController.jumpTo(0.0);

    _scrollLockerKey.currentState.lock();
    _edgeScrollDragTargetKey.currentState.disable();
  }

  void _minimizeNow() {
    _nowKey.currentState.minimize();
    _nowKey.currentState.hideQuickSettings();
    _peekManager.nowMinimized = true;
    _suggestionOverlayKey.currentState.hide();
  }

  /// Returns the state of the children to their initial values.
  /// This includes:
  /// 1) Unfocusing any focused stories.
  /// 2) Maximizing now.
  /// 3) Enabling scrolling of the story list.
  /// 4) Scrolling to the beginning of the story list.
  /// 5) Peeking the suggestion list.
  void goToOrigin(StoryModel storyModel) {
    _defocus(storyModel);
    _nowKey.currentState.maximize();
    storyModel.interactionStopped();
    storyModel.clearPlaceHolderStoryClusters();
  }

  /// Called to request the conductor focus on the cluster with [storyId].
  void requestStoryFocus(
    StoryId storyId,
    StoryModel storyModel, {
    bool jumpToFinish: true,
  }) {
    _scrollLockerKey.currentState.lock();
    _edgeScrollDragTargetKey.currentState.disable();
    _minimizeNow();
    _focusOnStory(storyId, storyModel, jumpToFinish: jumpToFinish);
  }

  void _focusOnStory(
    StoryId storyId,
    StoryModel storyModel, {
    bool jumpToFinish: true,
  }) {
    List<StoryCluster> targetStoryClusters =
        storyModel.storyClusters.where((StoryCluster storyCluster) {
      bool result = false;
      storyCluster.stories.forEach((Story story) {
        if (story.id == storyId) {
          result = true;
        }
      });
      return result;
    }).toList();

    // There should be only one story cluster with a story with this id.  If
    // that's not true, bail out.
    if (targetStoryClusters.length != 1) {
      print(
          'WARNING: Found ${targetStoryClusters.length} story clusters with a story with id $storyId. Returning to origin.');
      goToOrigin(storyModel);
    } else {
      // Unfocus all story clusters.
      storyModel.activeSortedStoryClusters.forEach(
        (StoryCluster storyCluster) => storyCluster.unFocus(),
      );

      // Ensure the focused story is completely expanded.
      targetStoryClusters[0].focusSimulationKey.currentState?.jump(1.0);

      // Ensure the focused story's story bar is full open.
      targetStoryClusters[0].maximizeStoryBars(jumpToFinish: jumpToFinish);

      // Focus on the story cluster.
      _focusStoryCluster(storyModel, targetStoryClusters[0]);
    }

    // Unhide selected suggestion in suggestion list.
    _suggestionListKey.currentState.resetSelection();
  }
}
