library graphview;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

part 'Algorithm.dart';
part 'Graph.dart';
part 'edgerenderer/ArrowEdgeRenderer.dart';
part 'edgerenderer/EdgeRenderer.dart';
part 'forcedirected/FruchtermanReingoldAlgorithm.dart';
part 'layered/SugiyamaAlgorithm.dart';
part 'layered/SugiyamaConfiguration.dart';
part 'layered/SugiyamaEdgeData.dart';
part 'layered/SugiyamaEdgeRenderer.dart';
part 'layered/SugiyamaNodeData.dart';
part 'tree/BuchheimWalkerAlgorithm.dart';
part 'tree/BuchheimWalkerConfiguration.dart';
part 'tree/BuchheimWalkerNodeData.dart';
part 'tree/TreeEdgeRenderer.dart';

typedef NodeWidgetBuilder = Widget Function(Node node);
typedef EdgePaintBuilder = Paint Function(Edge? edge);

class GraphView extends StatefulWidget {
  final Graph graph;
  final Algorithm algorithm;
  final NodeWidgetBuilder builder;
  final EdgePaintBuilder? edgePaintBuilder;
  final bool animated;

  GraphView(
      {Key? key,
      required this.graph,
      required this.algorithm,
      this.edgePaintBuilder,
      required this.builder,
      this.animated = true})
      : super(key: key);

  @override
  _GraphViewState createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> {
  @override
  Widget build(BuildContext context) {
    if (widget.algorithm is FruchtermanReingoldAlgorithm) {
      return _GraphViewAnimated(
        key: widget.key,
        graph: widget.graph,
        algorithm: widget.algorithm,
        edgePaintBuilder: widget.edgePaintBuilder,
        builder: widget.builder,
      );
    } else {
      return _GraphView(
        key: widget.key,
        graph: widget.graph,
        algorithm: widget.algorithm,
        edgePaintBuilder: widget.edgePaintBuilder,
        builder: widget.builder,
      );
    }
  }
}

class _GraphView extends MultiChildRenderObjectWidget {
  final Graph graph;
  final Algorithm algorithm;
  final EdgePaintBuilder? edgePaintBuilder;

  _GraphView(
      {Key? key,
      required this.graph,
      required this.algorithm,
      this.edgePaintBuilder,
      required NodeWidgetBuilder builder})
      : super(key: key, children: _extractChildren(graph, builder)) {
    assert(() {
      if (children.isEmpty) {
        throw FlutterError(
          'Children must not be empty, ensure you are overriding the builder',
        );
      }

      return true;
    }());
  }

  // Traverses the nodes depth-first collects the list of child widgets that are created.
  static List<Widget> _extractChildren(Graph graph, NodeWidgetBuilder builder) {
    final result = <Widget>[];

    graph.nodes.forEach((node) {
      var widget = node.data ?? builder(node);
      result.add(widget);
    });

    return result;
  }

  @override
  RenderCustomLayoutBox createRenderObject(BuildContext context) {
    return RenderCustomLayoutBox(graph, algorithm, edgePaintBuilder);
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderCustomLayoutBox renderObject) {
    renderObject
      ..graph = graph
      ..algorithm = algorithm
      ..edgePaint = edgePaintBuilder;
  }
}

class RenderCustomLayoutBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, NodeBoxData>,
        RenderBoxContainerDefaultsMixin<RenderBox, NodeBoxData> {
  late Graph _graph;
  late Algorithm _algorithm;
  late EdgePaintBuilder? _edgePaintBuilder;
  RenderCustomLayoutBox(
    Graph graph,
    Algorithm algorithm,
    EdgePaintBuilder? edgePaintBuilder, {
    List<RenderBox>? children,
  }) {
    _algorithm = algorithm;
    _graph = graph;
    _edgePaintBuilder = edgePaintBuilder;
    addAll(children);
  }
  EdgePaintBuilder? get edgePaint => _edgePaintBuilder;

  set edgePaint(EdgePaintBuilder? value) {
    _edgePaintBuilder = value;
    markNeedsPaint();
  }

  Graph get graph => _graph;

  set graph(Graph value) {
    _graph = value;
    markNeedsLayout();
  }

  Algorithm get algorithm => _algorithm;

  set algorithm(Algorithm value) {
    _algorithm = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! NodeBoxData) {
      child.parentData = NodeBoxData();
    }
  }

  @override
  void performLayout() {
    if (childCount == 0) {
      size = constraints.biggest;
      assert(size.isFinite);
      return;
    }

    var child = firstChild;
    var position = 0;
    var looseConstraints = BoxConstraints.loose(constraints.biggest);
    while (child != null) {
      final node = child.parentData as NodeBoxData;

      child.layout(looseConstraints, parentUsesSize: true);
      graph.getNodeAtPosition(position).size = child.size;

      child = node.nextSibling;
      position++;
    }

    size = algorithm.run(graph, 10, 10);

    child = firstChild;
    position = 0;
    while (child != null) {
      final node = child.parentData as NodeBoxData;

      node.offset = graph.getNodeAtPosition(position).position;

      child = node.nextSibling;
      position++;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.save();
    context.canvas.translate(offset.dx, offset.dy);

    algorithm.renderer?.render(context.canvas, graph, edgePaint);

    context.canvas.restore();

    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Graph>('graph', graph));
    properties.add(DiagnosticsProperty<Algorithm>('algorithm', algorithm));
    properties.add(DiagnosticsProperty<EdgePaintBuilder>('paint', edgePaint));
  }
}

class NodeBoxData extends ContainerBoxParentData<RenderBox> {}

class _GraphViewAnimated extends StatefulWidget {
  final Graph graph;
  final Algorithm algorithm;
  final EdgePaintBuilder? edgePaintBuilder;
  final NodeWidgetBuilder builder;
  final stepMilis = 25;

  _GraphViewAnimated(
      {Key? key,
      required this.graph,
      required this.algorithm,
      this.edgePaintBuilder,
      required this.builder});

  @override
  _GraphViewAnimatedState createState() => _GraphViewAnimatedState();
}

class _GraphViewAnimatedState extends State<_GraphViewAnimated> {
  late Timer timer;
  late Graph graph;
  late Algorithm algorithm;

  @override
  void initState() {
    graph = widget.graph;

    algorithm = widget.algorithm;
    algorithm.init(graph);
    startTimer();

    super.initState();
  }

  void startTimer() {
    timer = Timer.periodic(Duration(milliseconds: widget.stepMilis), (timer) {
      algorithm.step(graph);
      update();
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    algorithm.setDimensions(
        MediaQuery.of(context).size.width, MediaQuery.of(context).size.height);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CustomPaint(
          size: MediaQuery.of(context).size,
          painter: EdgeRender(algorithm, graph, Offset(20, 20),
              edgePaintBuilder: widget.edgePaintBuilder),
        ),
        ...List<Widget>.generate(graph.nodeCount(), (index) {
          return Positioned(
            child: GestureDetector(
              child:
                  graph.nodes[index].data ?? widget.builder(graph.nodes[index]),
              onPanUpdate: (details) {
                graph.getNodeAtPosition(index).position += details.delta;
                update();
              },
            ),
            top: graph.getNodeAtPosition(index).position.dy,
            left: graph.getNodeAtPosition(index).position.dx,
          );
        }),
      ],
    );
  }

  Future<void> update() async {
    setState(() {});
  }
}

class EdgeRender extends CustomPainter {
  Algorithm algorithm;
  Graph graph;
  Offset offset;
  EdgePaintBuilder? edgePaintBuilder;

  EdgeRender(this.algorithm, this.graph, this.offset, {this.edgePaintBuilder});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    algorithm.renderer!.render(canvas, graph, edgePaintBuilder);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
