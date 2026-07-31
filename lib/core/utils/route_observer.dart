import 'package:flutter/material.dart';

/// 全局路由观察者 — 页面在从上层路由返回时（didPopNext）刷新数据
class RouteObservers {
  static final RouteObserver<PageRoute> observer = RouteObserver<PageRoute>();
}
