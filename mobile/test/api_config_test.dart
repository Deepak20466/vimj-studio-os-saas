import 'package:flutter_test/flutter_test.dart';
import 'package:vimj_attendance/core/api_config.dart';

void main() {
  test('unconfigured mobile builds fail closed instead of targeting Render', () {
    expect(ApiConfig.baseUrl, 'https://api-base-url-required.invalid');
    expect(ApiConfig.baseUrl, isNot(contains('onrender.com')));
  });
}
