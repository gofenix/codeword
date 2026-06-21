/// Build the Youdao dictvoice URL for a given word and accent.
///
/// `lang` must be `'us'` (American, type=2) or `'uk'` (British, type=1).
String youdaoAudioUrl(String text, String lang) {
  final type = lang == 'uk' ? 1 : 2;
  return 'https://dict.youdao.com/dictvoice?audio='
      '${Uri.encodeQueryComponent(text)}&type=$type';
}
