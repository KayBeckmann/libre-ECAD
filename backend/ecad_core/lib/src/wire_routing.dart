import 'dart:math';

import 'drawing.dart';

typedef _Position = Point<double>;

/// Render-only orthogonal route. Electrical connectivity remains defined by
/// the wire's fixed endpoint references; explicit waypoints take precedence.
/// The automatic grid, obstacle bounds, and tie order mirror the editor route.
List<Point<double>> routedWirePoints(Json d, Json wire) {
  final a = endpointPosition(d, wire['from']);
  final b = endpointPosition(d, wire['to']);
  if (wire['waypoints'] is List) {
    final anchors = <_Position>[
      a,
      for (final p in (wire['waypoints'] as List).cast<Json>())
        Point((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
      b,
    ];
    final route = <_Position>[a];
    for (final next in anchors.skip(1)) {
      final previous = route.last;
      if (previous.x != next.x && previous.y != next.y) {
        route.add(Point(previous.x, next.y));
      }
      route.add(next);
    }
    return route;
  }

  final obstacles = objects(d, 'instances')
      .where(
        (i) =>
            i['sheetId'] == wire['sheetId'] &&
            i['id'] != wire['from']['instanceId'] &&
            i['id'] != wire['to']['instanceId'],
      )
      .map((i) => Point((i['x'] as num).toDouble(), (i['y'] as num).toDouble()))
      .toList();
  bool clear(_Position p, _Position q) {
    for (final center in obstacles) {
      final left = center.x - 48, right = center.x + 48;
      final top = center.y - 24, bottom = center.y + 24;
      if (p.x == q.x &&
          p.x > left &&
          p.x < right &&
          max(p.y, q.y) > top &&
          min(p.y, q.y) < bottom)
        return false;
      if (p.y == q.y &&
          p.y > top &&
          p.y < bottom &&
          max(p.x, q.x) > left &&
          min(p.x, q.x) < right)
        return false;
    }
    return true;
  }

  if ((a.x == b.x || a.y == b.y) && clear(a, b)) return [a, b];
  for (final bend in [Point(b.x, a.y), Point(a.x, b.y)]) {
    if (clear(a, bend) && clear(bend, b)) return [a, bend, b];
  }
  final xs = <double>{
    a.x,
    b.x,
    for (var x = 0; x <= 1200; x += 20) x.toDouble(),
  }.toList()..sort();
  final ys = <double>{
    a.y,
    b.y,
    for (var y = 0; y <= 800; y += 20) y.toDouble(),
  }.toList()..sort();
  final width = xs.length, count = width * ys.length;
  int node(int x, int y) => y * width + x;
  _Position position(int id) => Point(xs[id % width], ys[id ~/ width]);
  final start = node(xs.indexOf(a.x), ys.indexOf(a.y));
  final goal = node(xs.indexOf(b.x), ys.indexOf(b.y));
  final previous = List<int>.filled(count, -1);
  final queue = <int>[start];
  previous[start] = start;
  for (var cursor = 0; cursor < queue.length && previous[goal] < 0; cursor++) {
    final current = queue[cursor], x = current % width, y = current ~/ width;
    for (final next in [
      if (x > 0) node(x - 1, y),
      if (x < width - 1) node(x + 1, y),
      if (y > 0) node(x, y - 1),
      if (y < ys.length - 1) node(x, y + 1),
    ]) {
      if (previous[next] >= 0 || !clear(position(current), position(next)))
        continue;
      previous[next] = current;
      queue.add(next);
    }
  }
  if (previous[goal] < 0) return [a, b];
  final reversed = <_Position>[];
  for (var id = goal; id != start; id = previous[id])
    reversed.add(position(id));
  reversed.add(a);
  final points = reversed.reversed.toList();
  final route = <_Position>[points.first];
  for (var index = 1; index < points.length - 1; index++) {
    final p = points[index - 1], q = points[index], r = points[index + 1];
    if ((p.x == q.x && q.x == r.x) || (p.y == q.y && q.y == r.y)) continue;
    route.add(q);
  }
  route.add(points.last);
  return route;
}
