import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/domain/smart_parts/smart_part.dart';
import 'package:mohsen_tripo/src/features/workspace/part_prompt_profiles.dart';

void main() {
  test('MetaHuman anatomy prompts remove garment layers', () {
    final arm = PartPromptProfiles.build(SmartPartKind.rightArmDetached);
    final torso = PartPromptProfiles.build(SmartPartKind.torsoFront);
    final body = PartPromptProfiles.build(SmartPartKind.fullBodyAPose);

    expect(arm, contains('BARE right arm'));
    expect(arm, contains('Remove sleeves, gloves, bandages/wraps'));
    expect(torso, contains('BARE base torso anatomy'));
    expect(torso, contains('Remove shirts, gowns, jackets'));
    expect(body, contains('BASE ANATOMY'));
    expect(body, contains('Remove all clothing'));
    expect(body, contains('no explicit sexual anatomy'));
  });

  test('MetaHuman wearable prompts exclude body geometry', () {
    final footwear = PartPromptProfiles.build(SmartPartKind.feetShoes);

    expect(footwear, contains('footwear/shoes as separate wearable assets'));
    expect(footwear, contains('Do not include feet, leg skin'));
    final clothing = PartPromptProfiles.build(SmartPartKind.clothingOutfit);
    expect(clothing, contains('separate empty wearable geometry'));
    expect(clothing, contains('Do not include skin, body anatomy'));
    expect(PartKindClassifier.classify('ملابس / زي'), SmartPartKind.clothingOutfit);
  });

  test('clean head prompt removes hair and eyelashes', () {
    final head = PartPromptProfiles.build(SmartPartKind.headClean);

    expect(head, contains('bald head'));
    expect(head, contains('Remove all hair, eyelashes'));
  });
}
