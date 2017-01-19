// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'armadillo_drag_target.dart';
import 'armadillo_overlay.dart';
import 'nothing.dart';
import 'optional_wrapper.dart';
import 'panel.dart';
import 'simulated_fractionally_sized_box.dart';
import 'simulated_padding.dart';
import 'story.dart';
import 'story_bar.dart';
import 'story_cluster.dart';
import 'story_cluster_drag_feedback.dart';
import 'story_cluster_id.dart';
import 'story_full_size_simulated_sized_box.dart';
import 'story_manager.dart';
import 'story_positioned.dart';

const double _kStoryBarMinimizedHeight = 4.0;
const double _kStoryBarMaximizedHeight = 48.0;
const Color _kTargetOverlayColor = const Color.fromARGB(128, 153, 234, 216);

/// Displays up to four stories in a grid-like layout.
class StoryPanels extends StatefulWidget {
  final StoryCluster storyCluster;
  final double focusProgress;
  final bool highlight;
  final GlobalKey<ArmadilloOverlayState> overlayKey;
  final Map<StoryId, Widget> storyWidgets;

  StoryPanels({
    Key key,
    this.storyCluster,
    this.focusProgress,
    this.highlight,
    this.overlayKey,
    this.storyWidgets,
  })
      : super(key: key) {
    assert(() {
      Panel.haveFullCoverage(
        storyCluster.stories
            .map(
              (Story story) => story.panel,
            )
            .toList(),
      );
      return true;
    });
  }

  @override
  StoryPanelsState createState() => new StoryPanelsState();
}

class StoryPanelsState extends State<StoryPanels> {
  @override
  void initState() {
    super.initState();
    config.storyCluster.addPanelListener(_onPanelsChanged);
  }

  @override
  void didUpdateConfig(StoryPanels oldConfig) {
    super.didUpdateConfig(oldConfig);
    if (oldConfig.storyCluster.id != config.storyCluster.id) {
      oldConfig.storyCluster.removePanelListener(_onPanelsChanged);
      config.storyCluster.addPanelListener(_onPanelsChanged);
    }
  }

  @override
  void dispose() {
    config.storyCluster.removePanelListener(_onPanelsChanged);
    super.dispose();
  }

  void _onPanelsChanged() => scheduleMicrotask(() => setState(() {}));

  @override
  Widget build(BuildContext context) => new Container(
        foregroundDecoration: config.highlight
            ? new BoxDecoration(
                backgroundColor: _kTargetOverlayColor,
              )
            : null,
        child: new LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
          Size currentSize = new Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          return new Stack(
            overflow: Overflow.visible,
            children: config.storyCluster.stories
                .map(
                  (Story story) => new StoryPositioned(
                        focusProgress: config.focusProgress,
                        displayMode: config.storyCluster.displayMode,
                        isFocused:
                            (config.storyCluster.focusedStoryId == story.id),
                        story: story,
                        currentSize: currentSize,
                        focusSimulationKey:
                            config.storyCluster.focusSimulationKey,
                        child: _getStory(
                          context,
                          story,
                          _getStoryBarPadding(
                            story: story,
                            currentSize: currentSize,
                          ),
                        ),
                      ),
                )
                .toList(),
          );
        }),
      );

  Widget _getStoryBarDraggableWrapper({
    BuildContext context,
    Story story,
    Widget child,
  }) {
    final Widget storyWidget = config.storyWidgets[story.id];
    Rect initialBoundsOnDrag;
    return new OptionalWrapper(
      // Don't allow dragging if we're the only story.
      useWrapper: config.storyCluster.stories.length > 1,
      builder: (BuildContext context, Widget child) =>
          new ArmadilloLongPressDraggable<StoryClusterId>(
            key: story.clusterDraggableKey,
            overlayKey: config.overlayKey,
            data: story.clusterId,
            onDragStarted: () {
              RenderBox box =
                  story.positionedKey.currentContext.findRenderObject();
              Point boxTopLeft = box.localToGlobal(Point.origin);
              Point boxBottomRight = box.localToGlobal(
                new Point(box.size.width, box.size.height),
              );
              initialBoundsOnDrag = new Rect.fromLTRB(
                boxTopLeft.x,
                boxTopLeft.y,
                boxBottomRight.x,
                boxBottomRight.y,
              );
              InheritedStoryManager.of(context).split(
                    storyToSplit: story,
                    from: config.storyCluster,
                  );
              story.storyBarKey.currentState?.minimize();
            },
            childWhenDragging: Nothing.widget,
            feedbackBuilder: (Point localDragStartPoint) {
              StoryCluster storyCluster = InheritedStoryManager
                  .of(context)
                  .getStoryCluster(story.clusterId);
              return new StoryClusterDragFeedback(
                key: storyCluster.dragFeedbackKey,
                storyCluster: storyCluster,
                storyWidgets: {story.id: storyWidget},
                localDragStartPoint: localDragStartPoint,
                initialBounds: initialBoundsOnDrag,
              );
            },
            child: child,
          ),
      child: child,
    );
  }

  Widget _getStory(
    BuildContext context,
    Story story,
    EdgeInsets storyBarPadding,
  ) =>
      story.isPlaceHolder
          ? Nothing.widget
          : new Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The story bar that pushes down the story.
                new SimulatedPadding(
                  key: story.storyBarPaddingKey,
                  padding: storyBarPadding,
                  child: new GestureDetector(
                    onTap: () {
                      config.storyCluster.focusedStoryId = story.id;
                      _onPanelsChanged();
                    },
                    child: _getStoryBarDraggableWrapper(
                      context: context,
                      story: story,
                      child: new StoryBar(
                        key: story.storyBarKey,
                        story: story,
                        minimizedHeight: _kStoryBarMinimizedHeight,
                        maximizedHeight: _kStoryBarMaximizedHeight,
                      ),
                    ),
                  ),
                ),

                // The story itself.
                new Expanded(
                  child: new SimulatedFractionallySizedBox(
                    key: story.tabSizerKey,
                    alignment: FractionalOffset.topCenter,
                    heightFactor:
                        (config.storyCluster.focusedStoryId == story.id ||
                                config.storyCluster.displayMode ==
                                    DisplayMode.panels)
                            ? 1.0
                            : 0.0,
                    child: new Container(
                      decoration: new BoxDecoration(
                        backgroundColor: story.themeColor,
                      ),
                      child: _getStoryContents(context, story),
                    ),
                  ),
                ),
              ],
            );

  /// The scaled and clipped story.  When full size, the story will
  /// no longer be scaled or clipped.
  Widget _getStoryContents(BuildContext context, Story story) => new FittedBox(
        fit: ImageFit.cover,
        alignment: FractionalOffset.topCenter,
        child: new StoryFullSizeSimulatedSizedBox(
          displayMode: config.storyCluster.displayMode,
          panel: story.panel,
          containerKey: story.containerKey,
          focusSimulationKey: config.storyCluster.focusSimulationKey,
          child: config.storyWidgets[story.id],
        ),
      );

  EdgeInsets _getStoryBarPadding({
    Story story,
    Size currentSize,
  }) {
    if (config.storyCluster.displayMode == DisplayMode.panels) {
      return new EdgeInsets.symmetric(horizontal: 0.0);
    }
    int spaces = config.storyCluster.stories.length + 1;
    double widthPerSpace = toGridValue(currentSize.width / spaces);
    int index = config.storyCluster.stories.indexOf(story);
    double left = 0.0;
    for (int i = 0; i < config.storyCluster.stories.length; i++) {
      if (i == index) {
        break;
      }
      left += widthPerSpace;
      if (config.storyCluster.stories[i].id ==
          config.storyCluster.focusedStoryId) {
        left += widthPerSpace;
      }
    }
    double width = (story.id == config.storyCluster.focusedStoryId)
        ? 2.0 * widthPerSpace
        : widthPerSpace;
    double right = (widthPerSpace * spaces) - left - width;
    return new EdgeInsets.only(
      left: math.max(0.0, left),
      right: math.max(0.0, right),
    );
  }
}
