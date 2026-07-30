/// API通用响应 - 对应 ApiBean.kt
class ApiListResponse<T> {
  final List<T> results;
  final String? error;
  final int code;

  ApiListResponse(this.results, {this.error, this.code = 0});
}
