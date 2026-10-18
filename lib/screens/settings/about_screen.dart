import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../core/config.dart';
import '../../services/update_service.dart';
import '../../widgets/common.dart';

/// «عن التطبيق» والتراخيص بلغة جهاز المستخدم (حسب دولته/لغته). العربي هو الأساس.
class _T {
  final String about, title, desc, features, licenses, licensesNote, made;
  final bool rtl;
  const _T(this.about, this.title, this.desc, this.features, this.licenses, this.licensesNote, this.made, {this.rtl = false});
}

const _texts = <String, _T>{
  'ar': _T(
    'عن التطبيق',
    'VYFRI — تواصل آمن وسريع',
    'VYFRI تطبيق تواصل اجتماعي ومراسلة عربي: تنشر منشورات وصور وفيديوهات وريلز، تتفاعل بالإعجابات والتعليقات والمشاركة، تسولف بالدردشة والمكالمات الصوتية والفيديو، وتبيع وتشتري بالسوق، مع بث مباشر وقصص وسمات متحركة.',
    '• حماية متعددة الطبقات للحسابات والبيانات\n• شبكات توصيل عالمية مجانية لتصفح أسرع\n• تشفير الاتصال بين جهازك والخادم\n• تسجيل دخول بكوكل أو برقم الهاتف عبر تلكرام',
    'التراخيص',
    'هذه تراخيص المكتبات مفتوحة المصدر المستخدمة ببناء التطبيق. نصوص التراخيص القانونية تبقى بلغتها الأصلية (الإنكليزية) لأنها وثائق قانونية رسمية.',
    'صُنع بواسطة المبرمج المجهول',
    rtl: true,
  ),
  'en': _T(
    'About',
    'VYFRI — Fast & secure social',
    'VYFRI is a social and messaging app: share posts, photos, videos and reels, react, comment and share, chat with voice and video calls, buy and sell in the marketplace, go live, post stories and use animated themes.',
    '• Multi-layer protection for accounts and data\n• Free global delivery networks for faster browsing\n• Encrypted connection between your device and the server\n• Sign in with Google or with your phone via Telegram',
    'Licenses',
    'These are the licenses of the open-source libraries used to build the app. Legal license texts are kept in their original language.',
    'Made by Almajhool',
  ),
  'ku': _T(
    'دەربارەی ئەپ',
    'VYFRI — پەیوەندی خێرا و پارێزراو',
    'VYFRI ئەپێکی تۆڕی کۆمەڵایەتی و نامەناردنە: پۆست، وێنە، ڤیدیۆ و ڕیلز بڵاو بکەرەوە، لایک و کۆمێنت و هاوبەشی بکە، چات و پەیوەندی دەنگی و ڤیدیۆیی بکە، و لە بازاڕدا بکڕە و بفرۆشە.',
    '• پاراستنی چەند چینە بۆ هەژمار و زانیارییەکان\n• تۆڕی گەیاندنی جیهانی بێبەرامبەر بۆ گەڕانی خێراتر\n• پەیوەندی شفرەکراو لەنێوان ئامێرەکەت و سێرڤەر',
    'مۆڵەتەکان',
    'ئەمانە مۆڵەتی کتێبخانە کراوەکانن کە لە دروستکردنی ئەپەکەدا بەکارهاتوون. دەقە یاساییەکان بە زمانی ڕەسەنی خۆیان دەمێننەوە.',
    'دروستکراوە لەلایەن المبرمج المجهول',
    rtl: true,
  ),
  'fa': _T(
    'درباره برنامه',
    'VYFRI — ارتباط سریع و امن',
    'VYFRI یک برنامه شبکه اجتماعی و پیام‌رسان است: پست، عکس، ویدیو و ریلز منتشر کنید، واکنش نشان دهید، نظر بدهید و به اشتراک بگذارید، گفتگو و تماس صوتی و تصویری داشته باشید و در بازار خرید و فروش کنید.',
    '• حفاظت چندلایه از حساب‌ها و داده‌ها\n• شبکه‌های تحویل جهانی رایگان برای مرور سریع‌تر\n• اتصال رمزگذاری‌شده بین دستگاه شما و سرور',
    'مجوزها',
    'این‌ها مجوزهای کتابخانه‌های متن‌باز به‌کاررفته در ساخت برنامه هستند. متن‌های حقوقی به زبان اصلی خود باقی می‌مانند.',
    'ساخته شده توسط المبرمج المجهول',
    rtl: true,
  ),
  'ur': _T(
    'ایپ کے بارے میں',
    'VYFRI — تیز اور محفوظ رابطہ',
    'VYFRI ایک سوشل اور میسجنگ ایپ ہے: پوسٹس، تصاویر، ویڈیوز اور ریلز شیئر کریں، ری ایکٹ، کمنٹ اور شیئر کریں، چیٹ اور آڈیو/ویڈیو کالز کریں، اور مارکیٹ میں خرید و فروخت کریں۔',
    '• اکاؤنٹس اور ڈیٹا کے لیے کثیر سطحی تحفظ\n• تیز براؤزنگ کے لیے مفت عالمی نیٹ ورکس\n• آپ کے آلے اور سرور کے درمیان خفیہ کنکشن',
    'لائسنس',
    'یہ ایپ میں استعمال ہونے والی اوپن سورس لائبریریوں کے لائسنس ہیں۔ قانونی متن اپنی اصل زبان میں رہتے ہیں۔',
    'المبرمج المجهول کی تخلیق',
    rtl: true,
  ),
  'tr': _T(
    'Hakkında',
    'VYFRI — Hızlı ve güvenli sosyal ağ',
    'VYFRI bir sosyal medya ve mesajlaşma uygulamasıdır: gönderi, fotoğraf, video ve reels paylaşın, tepki verin, yorum yapın, sohbet edin, sesli ve görüntülü arama yapın, pazar yerinde alım satım yapın.',
    '• Hesaplar ve veriler için çok katmanlı koruma\n• Daha hızlı gezinme için ücretsiz küresel ağlar\n• Cihazınız ile sunucu arasında şifreli bağlantı',
    'Lisanslar',
    'Bunlar uygulamada kullanılan açık kaynak kütüphanelerin lisanslarıdır. Hukuki metinler orijinal dillerinde kalır.',
    'Almajhool tarafından yapıldı',
  ),
  'fr': _T(
    'À propos',
    'VYFRI — Social rapide et sécurisé',
    'VYFRI est une application sociale et de messagerie : publiez des posts, photos, vidéos et reels, réagissez, commentez et partagez, discutez avec appels audio et vidéo, achetez et vendez sur la marketplace.',
    '• Protection multicouche des comptes et des données\n• Réseaux de diffusion mondiaux gratuits pour une navigation plus rapide\n• Connexion chiffrée entre votre appareil et le serveur',
    'Licences',
    'Voici les licences des bibliothèques open source utilisées. Les textes juridiques restent dans leur langue d\'origine.',
    'Créé par Almajhool',
  ),
  'es': _T(
    'Acerca de',
    'VYFRI — Social rápido y seguro',
    'VYFRI es una app social y de mensajería: publica posts, fotos, videos y reels, reacciona, comenta y comparte, chatea con llamadas de voz y video, y compra y vende en el mercado.',
    '• Protección multicapa para cuentas y datos\n• Redes globales gratuitas para navegar más rápido\n• Conexión cifrada entre tu dispositivo y el servidor',
    'Licencias',
    'Estas son las licencias de las bibliotecas de código abierto usadas. Los textos legales se mantienen en su idioma original.',
    'Hecho por Almajhool',
  ),
  'de': _T(
    'Über die App',
    'VYFRI — Schnell & sicher vernetzt',
    'VYFRI ist eine Social- und Messaging-App: Beiträge, Fotos, Videos und Reels teilen, reagieren, kommentieren, chatten, Sprach- und Videoanrufe führen und auf dem Marktplatz kaufen und verkaufen.',
    '• Mehrschichtiger Schutz für Konten und Daten\n• Kostenlose globale Netzwerke für schnelleres Surfen\n• Verschlüsselte Verbindung zwischen Gerät und Server',
    'Lizenzen',
    'Dies sind die Lizenzen der verwendeten Open-Source-Bibliotheken. Rechtstexte bleiben in ihrer Originalsprache.',
    'Erstellt von Almajhool',
  ),
  'ru': _T(
    'О приложении',
    'VYFRI — быстрое и безопасное общение',
    'VYFRI — социальная сеть и мессенджер: публикуйте посты, фото, видео и рилсы, ставьте реакции, комментируйте, общайтесь в чате и по аудио/видеосвязи, покупайте и продавайте на маркетплейсе.',
    '• Многоуровневая защита аккаунтов и данных\n• Бесплатные глобальные сети для быстрой загрузки\n• Зашифрованное соединение с сервером',
    'Лицензии',
    'Это лицензии библиотек с открытым кодом, использованных в приложении. Юридические тексты остаются на языке оригинала.',
    'Создано Almajhool',
  ),
  'hi': _T(
    'ऐप के बारे में',
    'VYFRI — तेज़ और सुरक्षित सोशल',
    'VYFRI एक सोशल और मैसेजिंग ऐप है: पोस्ट, फ़ोटो, वीडियो और रील्स शेयर करें, रिएक्ट, कमेंट और शेयर करें, चैट और ऑडियो/वीडियो कॉल करें, और मार्केट में खरीदें-बेचें।',
    '• खातों और डेटा के लिए बहु-स्तरीय सुरक्षा\n• तेज़ ब्राउज़िंग के लिए मुफ़्त वैश्विक नेटवर्क\n• डिवाइस और सर्वर के बीच एन्क्रिप्टेड कनेक्शन',
    'लाइसेंस',
    'ये ऐप में उपयोग की गई ओपन-सोर्स लाइब्रेरी के लाइसेंस हैं। कानूनी पाठ अपनी मूल भाषा में रहते हैं।',
    'Almajhool द्वारा बनाया गया',
  ),
  'id': _T(
    'Tentang',
    'VYFRI — Sosial cepat & aman',
    'VYFRI adalah aplikasi sosial dan perpesanan: bagikan postingan, foto, video, dan reels, beri reaksi, komentar dan bagikan, chat dengan panggilan suara dan video, serta jual beli di marketplace.',
    '• Perlindungan berlapis untuk akun dan data\n• Jaringan global gratis untuk penjelajahan lebih cepat\n• Koneksi terenkripsi antara perangkat dan server',
    'Lisensi',
    'Ini adalah lisensi pustaka sumber terbuka yang digunakan. Teks hukum tetap dalam bahasa aslinya.',
    'Dibuat oleh Almajhool',
  ),
  'zh': _T(
    '关于',
    'VYFRI — 快速安全的社交',
    'VYFRI 是一款社交和即时通讯应用：发布动态、照片、视频和短视频，点赞、评论和分享，聊天及语音/视频通话，并在市场中买卖。',
    '• 账户和数据的多层保护\n• 免费全球加速网络，浏览更快\n• 设备与服务器之间的加密连接',
    '许可证',
    '以下是本应用使用的开源库许可证。法律文本保留其原始语言。',
    '由 Almajhool 制作',
  ),
  'pt': _T(
    'Sobre',
    'VYFRI — Social rápido e seguro',
    'VYFRI é um app social e de mensagens: publique posts, fotos, vídeos e reels, reaja, comente e compartilhe, converse com chamadas de voz e vídeo, e compre e venda no marketplace.',
    '• Proteção em várias camadas para contas e dados\n• Redes globais gratuitas para navegação mais rápida\n• Conexão criptografada entre o aparelho e o servidor',
    'Licenças',
    'Estas são as licenças das bibliotecas de código aberto usadas. Os textos legais permanecem no idioma original.',
    'Feito por Almajhool',
  ),
};

Locale _deviceLocale() => WidgetsBinding.instance.platformDispatcher.locale;

_T _text() {
  final l = _deviceLocale().languageCode;
  if (l == 'ckb') return _texts['ku']!;
  return _texts[l] ?? _texts['ar']!;
}

/// يفتح صفحة التراخيص بلغة الجهاز (إذا مدعومة) وإلا بالعربي
void openLicenses(BuildContext context) {
  final t = _text();
  var loc = _deviceLocale();
  if (!GlobalMaterialLocalizations.delegate.isSupported(loc)) loc = const Locale('ar');
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Localizations.override(
        context: context,
        locale: Locale(loc.languageCode),
        child: Directionality(
          textDirection: t.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: LicensePage(
            applicationName: AppConfig.appName,
            applicationVersion: UpdateService.currentVersion,
            applicationIcon: const Padding(padding: EdgeInsets.all(8), child: BrandLogo(size: 56, showName: false)),
            applicationLegalese: '${t.desc}\n\n${t.licensesNote}\n\n${t.made}',
          ),
        ),
      ),
    ),
  );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = _text();
    return Directionality(
      textDirection: t.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(t.about)),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Center(child: BrandLogo(size: 88, showName: false)),
          const SizedBox(height: 12),
          Center(
            child: Text(AppConfig.appName, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          ),
          Center(child: Text(UpdateService.currentVersion, style: TextStyle(color: Theme.of(context).hintColor))),
          const SizedBox(height: 18),
          Text(t.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(t.desc, style: const TextStyle(fontSize: 15, height: 1.6)),
          const SizedBox(height: 14),
          Text(t.features, style: const TextStyle(fontSize: 14.5, height: 1.8)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => openLicenses(context),
            icon: const Icon(Icons.description_outlined),
            label: Text(t.licenses),
          ),
          const SizedBox(height: 24),
          Center(child: Text(t.made, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor))),
        ]),
      ),
    );
  }
}
