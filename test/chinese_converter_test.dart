import 'package:flutter_test/flutter_test.dart';
import 'package:scp_app/core/utils/chinese_converter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ChineseConverter.ensureLoaded();
  });

  group('繁→简 (t2s)', () {
    test('高频字全量覆盖', () {
      expect(ChineseConverter.toSimplified('項目編號'), '项目编号');
      expect(ChineseConverter.toSimplified('該項目必須存放於密封容器之中'),
          '该项目必须存放于密封容器之中');
      expect(ChineseConverter.toSimplified('長時間接觸會導致嚴重的心理創傷'),
          '长时间接触会导致严重的心理创伤');
      expect(ChineseConverter.toSimplified('為'), '为');
      expect(ChineseConverter.toSimplified('爲'), '为');
      expect(ChineseConverter.toSimplified('與將幾觸無異'), '与将几触无异');
      expect(ChineseConverter.toSimplified('工作人員進入前需穿著防護裝備'),
          '工作人员进入前需穿著防护装备');
      expect(ChineseConverter.toSimplified('實驗記錄顯示'), '实验记录显示');
      expect(ChineseConverter.toSimplified('根據檔案記載'), '根据档案记载');
    });

    test('同形字不被误转换', () {
      expect(ChineseConverter.toSimplified('控制'), '控制'); // 制不转製
      expect(ChineseConverter.toSimplified('的的是了在'), '的的是了在');
    });

    test('整段繁体 SCP 风格正文', () {
      const trad =
          '項目編號：SCP-XXX\n項目等級：Keter\n特殊收容措施：該項目必須存放於密封容器之中。'
          '工作人員進入前需穿著防護裝備，並在離開後接受心理評估。實驗記錄顯示，長時間接觸會導致嚴重的心理創傷。'
          '我們正在研究如何更有效地控制這個異常，相關數據將持續更新。';
      const want =
          '项目编号：SCP-XXX\n项目等级：Keter\n特殊收容措施：该项目必须存放于密封容器之中。'
          '工作人员进入前需穿著防护装备，并在离开后接受心理评估。实验记录显示，长时间接触会导致严重的心理创伤。'
          '我们正在研究如何更有效地控制这个异常，相关数据将持续更新。';
      expect(ChineseConverter.toSimplified(trad), want);
    });
  });

  group('简→繁 (s2t)', () {
    test('高频字覆盖', () {
      expect(ChineseConverter.toTraditional('我们正在研究如何更有效地控制这个异常'),
          '我們正在研究如何更有效地控制這個異常');
      expect(ChineseConverter.toTraditional('项目编号'), '項目編號');
      expect(ChineseConverter.toTraditional('长时间接触会导致严重的心理创伤'),
          '長時間接觸會導致嚴重的心理創傷');
      expect(ChineseConverter.toTraditional('工作人员进入前需穿着防护装备'),
          '工作人員進入前需穿着防護裝備');
    });

    test('短语歧义消解', () {
      // 干杯→乾杯、干部→幹部 由短语词典区分
      expect(ChineseConverter.toTraditional('干杯'), '乾杯');
      expect(ChineseConverter.toTraditional('干部'), '幹部');
      expect(ChineseConverter.toTraditional('里面'), '裏面');
    });
  });

  test('HTML 标签结构保持不变', () {
    const html = '<p><strong>項目編號：</strong>SCP-002</p><p>該項目必須存放於密封容器之中</p>';
    const want = '<p><strong>项目编号：</strong>SCP-002</p><p>该项目必须存放于密封容器之中</p>';
    // 仅验证转换后的文本部分（标签不动）
    final out = ChineseConverter.toSimplified(html);
    expect(out, want);
  });
}
