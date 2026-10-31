import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/services/survey_service.dart';

void main() {
  test('collects every photo path of a survey', () {
    final survey = {
      'survey_data': {
        'points': [
          {
            'photos': [
              {'storage_path': 'u/s/point_1/photo_1.jpg'},
              {'storage_path': 'u/s/point_1/photo_2.jpg'},
            ],
          },
          {'photos': <Map<String, dynamic>>[]},
          {
            'photos': [
              {'storage_path': 'u/s/point_3/photo_1.jpg'},
              {'storage_path': ''},
            ],
          },
        ],
      },
    };

    expect(SurveyService.photoPathsOf(survey), [
      'u/s/point_1/photo_1.jpg',
      'u/s/point_1/photo_2.jpg',
      'u/s/point_3/photo_1.jpg',
    ]);
  });

  test('handles surveys without points or photos', () {
    expect(SurveyService.photoPathsOf({}), isEmpty);
    expect(SurveyService.photoPathsOf({'survey_data': 'broken'}), isEmpty);
    expect(
      SurveyService.photoPathsOf({
        'survey_data': {'points': []},
      }),
      isEmpty,
    );
  });
}
