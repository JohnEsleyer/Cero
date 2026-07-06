import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'services/server_service.dart';
import 'models/page_model.dart';
import 'models/card_model.dart' as models;
import 'widgets/card_column.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final serverService = ServerService();
  await serverService.init();

  runApp(MyApp(serverService: serverService));
}

class MyApp extends StatelessWidget {
  final ServerService serverService;

  const MyApp({super.key, required this.serverService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cero Journal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF191919),
        primaryColor: const Color(0xFF818CF8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF818CF8),
          brightness: Brightness.dark,
          primary: const Color(0xFF818CF8),
          secondary: const Color(0xFF818CF8),
          surface: const Color(0xFF202020),
        ),
        cardTheme: const CardThemeData(color: Color(0xFF202020), elevation: 0),
        drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFF202020)),
      ),
      home: MainJournalScreen(serverService: serverService),
    );
  }
}

class MainJournalScreen extends StatefulWidget {
  final ServerService serverService;

  const MainJournalScreen({super.key, required this.serverService});

  @override
  State<MainJournalScreen> createState() => _MainJournalScreenState();
}

class _MainJournalScreenState extends State<MainJournalScreen> {
  late final ServerService _serverService;

  DbPage? _selectedPage;
  final Set<String> _expandedPageIds = {};
  bool _showArchived = false;
  List<DbPage> _archivedPages = [];
  final List<String> _navigationHistory = [];
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final ScrollController _cardScrollController = ScrollController();
  List<models.Card> _pageCards = [];
  List<DbPage> _sidePages = [];
  bool _isRefreshingPage = false;
  Timer? _saveDebounceTimer;
  List<String> _recentEmojis = [];
  final TextEditingController _clientIpController = TextEditingController();
  final TextEditingController _clientPinController = TextEditingController();
  bool _isClientModeTab = false;

  // Rich Keyboard-Matching Categorized Emojis Catalog with names for search
  final List<Map<String, dynamic>> _emojiCategories = [
    {
      'id': 'smileys',
      'label': '😀 Smileys',
      'emojis': [
        {'char': '😀', 'name': 'grinning face happy smile laugh'},
        {'char': '😃', 'name': 'grinning face with big eyes happy smile laugh'},
        {'char': '😄', 'name': 'grinning face with smiling eyes happy smile laugh'},
        {'char': '😁', 'name': 'beaming face with smiling eyes happy smile grin laugh'},
        {'char': '😆', 'name': 'grinning squinting face happy smile laugh'},
        {'char': '😅', 'name': 'grinning face with sweat hot warm relief nervous laugh'},
        {'char': '😂', 'name': 'face with tears of joy funny happy cry laugh'},
        {'char': '🤣', 'name': 'rolling on the floor laughing funny happy laugh'},
        {'char': '😊', 'name': 'smiling face with smiling eyes happy smile blush warm'},
        {'char': '😇', 'name': 'smiling face with halo angel innocent good'},
        {'char': '🙂', 'name': 'slightly smiling face happy smile'},
        {'char': '🙃', 'name': 'upside down face silly crazy head over heels'},
        {'char': '😉', 'name': 'winking face blink joke hint'},
        {'char': '😌', 'name': 'relieved face calm peace quiet satisfied'},
        {'char': '😍', 'name': 'smiling face with heart eyes love heart crush adore'},
        {'char': '🥰', 'name': 'smiling face with hearts love heart blush warm adore'},
        {'char': '😘', 'name': 'face blowing a kiss love heart kiss romantic'},
        {'char': '😗', 'name': 'kissing face kiss lips'},
        {'char': '😙', 'name': 'kissing face with smiling eyes kiss lips'},
        {'char': '😚', 'name': 'kissing face with closed eyes kiss lips'},
        {'char': '😋', 'name': 'face savoring food delicious tasty hungry yum tongue'},
        {'char': '😛', 'name': 'face with tongue silly cheek tongue out'},
        {'char': '😝', 'name': 'squinting face with tongue silly cheek tongue out'},
        {'char': '😜', 'name': 'winking face with tongue silly cheek tongue out blink'},
        {'char': '🤪', 'name': 'zany face crazy silly wild eyes'},
        {'char': '🤨', 'name': 'face with raised eyebrow suspicious skeptical question doubt'},
        {'char': '🧐', 'name': 'face with monocle smart nerdy research look check'},
        {'char': '🤓', 'name': 'nerd face smart nerdy glasses geek'},
        {'char': '😎', 'name': 'smiling face with sunglasses cool sunglasses style'},
        {'char': '🥸', 'name': 'disguised face mask detective hide secret'},
        {'char': '🤩', 'name': 'star struck star eyes amazing cool wow'},
        {'char': '🥳', 'name': 'partying face party celebration noise hat'},
        {'char': '😏', 'name': 'smirking face smile smug clever sassy'},
        {'char': '😒', 'name': 'unamused face meh bored unhappy sad'},
        {'char': '😞', 'name': 'disappointed face sad unhappy regret'},
        {'char': '😔', 'name': 'pensive face sad thoughtful sorry regret'},
        {'char': '😟', 'name': 'worried face anxious nervous afraid'},
        {'char': '😕', 'name': 'confused face unsure puzzled doubt'},
        {'char': '🙁', 'name': 'slightly frowning face sad unhappy'},
        {'char': '☹️', 'name': 'frowning face sad unhappy cry'},
        {'char': '😣', 'name': 'persevering face struggle try hard stress'},
        {'char': '😖', 'name': 'confounded face stress worried painful'},
        {'char': '😫', 'name': 'tired face yawn sleep exhausted'},
        {'char': '😩', 'name': 'weary face yawn sleep exhausted stress'},
        {'char': '🥺', 'name': 'pleading face please beg cute eyes'},
        {'char': '😢', 'name': 'crying face sad tear unhappy cry'},
        {'char': '😭', 'name': 'loudly crying face sad tear unhappy cry sob'},
        {'char': '😤', 'name': 'face with steam from nose angry mad proud victory'},
        {'char': '😠', 'name': 'angry face mad rage annoyed'},
        {'char': '😡', 'name': 'pouting face angry mad rage red'},
        {'char': '🤬', 'name': 'face with symbols on mouth swear bad angry rage'},
        {'char': '🤯', 'name': 'exploding head mind blown shock amazing wow'},
        {'char': '😳', 'name': 'flushed face blush shock surprise shame embarrassed'},
        {'char': '🥵', 'name': 'hot face heat summer warm sweat red'},
        {'char': '🥶', 'name': 'cold face freeze ice winter blue shivering'},
        {'char': '😱', 'name': 'face screaming in fear fear scream shock surprise afraid ghost'},
        {'char': '😨', 'name': 'fearful face fear afraid worried'},
        {'char': '😰', 'name': 'anxious face with sweat fear sweat nervous worried'},
        {'char': '😥', 'name': 'sad but relieved face relief nervous tear sweat'},
        {'char': '😓', 'name': 'downcast face with sweat stress sad unhappy nervous'},
        {'char': '🤔', 'name': 'thinking face think wonder guess ponder'},
        {'char': '🫣', 'name': 'face with peeking eye hide look watch afraid'},
        {'char': '🤭', 'name': 'face with hand over mouth oops laugh giggle secret'},
        {'char': '🫢', 'name': 'face with open eyes and hand over mouth shock gasp surprise'},
        {'char': '🫡', 'name': 'saluting face salute respect military'},
        {'char': '🤫', 'name': 'shushing face quiet silence shh'},
        {'char': '🫠', 'name': 'melting face hot summer dissolve melt'},
        {'char': '🤥', 'name': 'lying face liar nose long pinocchio'},
        {'char': '😶', 'name': 'face without mouth quiet silent speech'},
        {'char': '😐', 'name': 'neutral face meh indifferent direct'},
        {'char': '😑', 'name': 'expressionless face meh indifferent closed eyes'},
        {'char': '😬', 'name': 'grimacing face oops awkward worry nervous'},
        {'char': '🫨', 'name': 'shaking face shock wave dizzy vibration'},
        {'char': '😴', 'name': 'sleeping face sleep zzz night dream'},
        {'char': '🤤', 'name': 'drooling face sleep delicious hungry saliva'},
        {'char': '😪', 'name': 'sleepy face sleep tired snot bubble'},
        {'char': '😵', 'name': 'dizzy face shock dead eyes crossed'},
        {'char': '😵💫', 'name': 'face with spiral eyes shock dizzy crazy'},
        {'char': '🤐', 'name': 'zipper mouth face silent quiet secret shut'},
        {'char': '🥴', 'name': 'woozy face drunk high dizzy wavy'},
        {'char': '🤢', 'name': 'nauseated face sick green vomit bad disgust'},
        {'char': '🤮', 'name': 'face vomiting sick vomit green disgust'},
        {'char': '🤧', 'name': 'sneezing face sick sneeze cold tissue flu'},
        {'char': '😷', 'name': 'face with medical mask sick doctor health flu safety'},
        {'char': '🤒', 'name': 'face with thermometer sick hot heat fever flu'},
        {'char': '🤕', 'name': 'face with head bandage sick hurt pain accident bandage'},
        {'char': '😈', 'name': 'smiling face with horns devil evil purple bad plan'},
        {'char': '👿', 'name': 'angry face with horns devil evil purple bad angry'},
        {'char': '👹', 'name': 'ogre japanese mask red evil monster'},
        {'char': '👺', 'name': 'goblin japanese mask red long nose evil monster'},
        {'char': '💀', 'name': 'skull bone dead skeleton halloween danger'},
        {'char': '☠️', 'name': 'skull and crossbones dead bone pirate danger'},
        {'char': '👻', 'name': 'ghost white scary halloween spooky'},
        {'char': '👽', 'name': 'alien space ufo monster green sci-fi'},
        {'char': '👾', 'name': 'alien monster retro pixel game space arcade'},
        {'char': '🤖', 'name': 'robot face bot tech screen machine computer'},
        {'char': '🎃', 'name': 'jack o lantern pumpkin orange halloween holiday'},
        {'char': '😺', 'name': 'grinning cat cat face pet animal happy smile'},
        {'char': '😸', 'name': 'grinning cat with smiling eyes cat face pet animal happy smile'},
        {'char': '😹', 'name': 'cat with tears of joy cat face pet animal funny cry laugh'},
        {'char': '😻', 'name': 'smiling cat with heart eyes cat face pet animal love adore'},
        {'char': '😼', 'name': 'cat with wry smile cat face pet animal smirk smug'},
        {'char': '😽', 'name': 'kissing cat cat face pet animal kiss romantic lips'},
        {'char': '😾', 'name': 'pouting cat cat face pet animal angry mad rage'},
        {'char': '😿', 'name': 'crying cat cat face pet animal sad tear cry'},
        {'char': '🙀', 'name': 'weary cat cat face pet animal shock gasp surprise fear'},
        {'char': '👋', 'name': 'waving hand wave hello goodbye hi meet'},
        {'char': '🤚', 'name': 'raised back of hand hand stop'},
        {'char': '🖐️', 'name': 'hand with fingers splayed hand stop fingers five'},
        {'char': '✋', 'name': 'raised hand stop high five hold'},
        {'char': '🖖', 'name': 'vulcan salute sci-fi space live long prosper'},
        {'char': '👌', 'name': 'ok hand sign okay correct perfect good alright'},
        {'char': '🤌', 'name': 'pinched fingers italian question what do you want'},
        {'char': '🤏', 'name': 'pinching hand small little tiny bit'},
        {'char': '✌️', 'name': 'victory hand peace sign two double victory win'},
        {'char': '🤞', 'name': 'crossed fingers luck hope wish cross'},
        {'char': '🫰', 'name': 'hand with index finger and thumb crossed love heart cute kpop'},
        {'char': '🤟', 'name': 'love you gesture hand love forever respect rock'},
        {'char': '🤘', 'name': 'sign of the horns rock hand music heavy metal'},
        {'char': '🤙', 'name': 'call me hand call phone gesture telephone'},
        {'char': '👈', 'name': 'backhand index pointing left point left direction hand'},
        {'char': '👉', 'name': 'backhand index pointing right point right direction hand'},
        {'char': '👆', 'name': 'backhand index pointing up point up direction hand rise'},
        {'char': '🖕', 'name': 'middle finger hand bad gesture rude insult'},
        {'char': '👇', 'name': 'backhand index pointing down point down direction hand drop'},
        {'char': '☝️', 'name': 'index pointing up point up hand direction priority'},
        {'char': '👍', 'name': 'thumbs up good correct nice positive yes like agree ok'},
        {'char': '👎', 'name': 'thumbs down bad incorrect negative dislike no disagree reject'},
        {'char': '✊', 'name': 'raised fist power strength rebel fight'},
        {'char': '👊', 'name': 'oncoming fist punch power fight hand'},
        {'char': '🤛', 'name': 'left facing fist punch power fight hand'},
        {'char': '🤜', 'name': 'right facing fist punch power fight hand'},
        {'char': '👏', 'name': 'clapping hands clap good job praise bravo nice'},
        {'char': '🙌', 'name': 'raising hands celebrate party win high five praise'},
        {'char': '🫶', 'name': 'heart hands love heart warmth appreciate adore'},
        {'char': '👐', 'name': 'open hands warm embrace hug welcome open'},
        {'char': '🤲', 'name': 'palms up together pray beg read gift book offer'},
        {'char': '🤝', 'name': 'handshake agree deal partner match meeting shake'},
        {'char': '🙏', 'name': 'folded hands pray please thank you support bless respect bow'},
        {'char': '✍️', 'name': 'writing hand write pencil pen signature note paper'},
        {'char': '💅', 'name': 'nail polish manicure care style beauty fashion'},
        {'char': '🤳', 'name': 'selfie phone camera snap photo'},
        {'char': '💪', 'name': 'flexed biceps power muscle strength strong gym sport health'},
        {'char': '🦾', 'name': 'mechanical arm robot arm tech cyber strength science'},
        {'char': '🦿', 'name': 'mechanical leg robot leg tech cyber strength science'},
        {'char': '🦵', 'name': 'leg run foot step knee kick'},
        {'char': '🦶', 'name': 'foot step run toes kick stand walking'},
        {'char': '👂', 'name': 'ear listen hear noise sound'},
        {'char': '🦻', 'name': 'ear with hearing aid hear deaf medical tech'},
        {'char': '👃', 'name': 'nose smell breathe scent sniff'},
        {'char': '🧠', 'name': 'brain smart intelligent mind thinking science education'},
        {'char': '🫀', 'name': 'anatomical heart love organ medical pulse red life'},
        {'char': '🫁', 'name': 'lungs breathe oxygen medical health body'},
        {'char': '🦷', 'name': 'tooth dentist dental clean health mouth white'},
        {'char': '🦴', 'name': 'bone dog skeleton structure dead halloween'},
        {'char': '👀', 'name': 'eyes look watch see search explore find'},
        {'char': '👁️', 'name': 'eye look see watch attention secret'},
        {'char': '👅', 'name': 'tongue taste lick mouth talk cheek'},
        {'char': '👄', 'name': 'mouth lips speak talk kiss beauty red'},
        {'char': '💋', 'name': 'kiss mark love kiss lips red romantic beauty lipstick'},
        {'char': '🩸', 'name': 'drop of blood bleed drop medical donor red'},
        {'char': '👤', 'name': 'bust in silhouette person user profile member'},
        {'char': '👥', 'name': 'busts in silhouette people users profiles team group'},
        {'char': '🫂', 'name': 'people hugging hug love friend care support warm'},
      ]
    },
    {
      'id': 'animals',
      'label': '🐱 Animals',
      'emojis': [
        {'char': '🐶', 'name': 'dog face doggy pet animal puppy wag bark'},
        {'char': '🐱', 'name': 'cat face kitten pet animal kitty meow purr'},
        {'char': '🐭', 'name': 'mouse face mouse pet animal squeak cheese'},
        {'char': '🐹', 'name': 'hamster face pet animal hamster wheel fat cute'},
        {'char': '🐰', 'name': 'rabbit face pet animal bunny carrot ears jump'},
        {'char': '🦊', 'name': 'fox face wild animal orange tail clever sneaky'},
        {'char': '🐻', 'name': 'bear face wild animal brown forest cute grizzly'},
        {'char': '🐼', 'name': 'panda face wild animal bamboo forest black white giant'},
        {'char': '🐨', 'name': 'koala face wild animal eucalyptus tree cute gray'},
        {'char': '🐯', 'name': 'tiger face wild animal cat orange stripes predator roar'},
        {'char': '🦁', 'name': 'lion face wild animal cat yellow mane king safari roar'},
        {'char': '🐮', 'name': 'cow face farm animal milk farm moo'},
        {'char': '🐷', 'name': 'pig face farm animal pink farm oink snout'},
        {'char': '🐽', 'name': 'pig nose pink farm oink snout'},
        {'char': '🐸', 'name': 'frog face animal green jump croak pond water'},
        {'char': '🐵', 'name': 'monkey face animal banana tree forest climb clever'},
        {'char': '🙈', 'name': 'see no evil monkey hand cover eyes hide secret monkey'},
        {'char': '🙉', 'name': 'hear no evil monkey hand cover ears quiet silent monkey'},
        {'char': '🙊', 'name': 'speak no evil monkey hand cover mouth quiet silent monkey'},
        {'char': '🐒', 'name': 'monkey animal banana forest climb'},
        {'char': '🐔', 'name': 'chicken farm animal hen bird egg farm cluck'},
        {'char': '🐧', 'name': 'penguin wild animal bird ice winter south polar swim'},
        {'char': '🐦', 'name': 'bird animal wild fly chirp nest sky wing'},
        {'char': '🐤', 'name': 'baby chick bird baby yellow cute egg chirp hatch'},
        {'char': '🐣', 'name': 'hatching chick bird baby yellow cute egg chirp hatch crack'},
        {'char': '🐥', 'name': 'front facing baby chick bird baby yellow cute egg chirp hatch'},
        {'char': '🦆', 'name': 'duck farm animal bird swim quack lake pond water'},
        {'char': '🦅', 'name': 'eagle wild animal bird fly hunter sky power wings'},
        {'char': '🦉', 'name': 'owl wild animal bird fly night wise intelligent tree'},
        {'char': '🪱', 'name': 'worm insect crawl dirt ground wet rain'},
        {'char': '🐛', 'name': 'bug insect caterpillar crawl green worm leaves'},
        {'char': '🦋', 'name': 'butterfly insect wings fly beauty insect colorful'},
        {'char': '🐌', 'name': 'snail bug insect shell crawl slow garden ground'},
        {'char': '🐞', 'name': 'lady beetle ladybug insect bug red spots garden wings'},
        {'char': '🐜', 'name': 'ant insect bug colony small tiny worker dirt'},
        {'char': '🪰', 'name': 'fly insect bug wings dirty annoying'},
        {'char': '🪲', 'name': 'beetle bug insect shell horn garden'},
        {'char': '🪳', 'name': 'cockroach bug insect dirty crawl dark night'},
        {'char': '🦗', 'name': 'cricket bug insect jump noise green garden'},
        {'char': '🕷️', 'name': 'spider bug insect web eight legs scary halloween creep'},
        {'char': '🕸️', 'name': 'spider web spider insect bug halloween thread design'},
        {'char': '🦂', 'name': 'scorpion desert bug insect sting tail danger dry'},
        {'char': '🐢', 'name': 'turtle reptile shell ocean swim sea slow green beach'},
        {'char': '🐍', 'name': 'snake reptile hiss crawl poison green jungle animal'},
        {'char': '🦎', 'name': 'lizard reptile lizard crawl tail green dragon garden'},
        {'char': '🐙', 'name': 'octopus ocean sea swim creature water eight arms tentacle'},
        {'char': '🦑', 'name': 'squid ocean sea swim creature water tentacle pink'},
        {'char': '🦞', 'name': 'lobster ocean sea swim creature water red pinch dinner'},
        {'char': '🦀', 'name': 'crab ocean sea swim creature water beach red pinch'},
        {'char': '🐡', 'name': 'blowfish pufferfish fish sea swim ocean water yellow round'},
        {'char': '🐠', 'name': 'tropical fish fish sea swim ocean water yellow blue color'},
        {'char': '🐟', 'name': 'fish sea swim ocean water blue food lake river'},
        {'char': '🐬', 'name': 'dolphin sea swim ocean water clever jump blue friend'},
        {'char': '🐳', 'name': 'spouting whale whale sea swim ocean water giant spout blowhole'},
        {'char': '🐋', 'name': 'whale sea swim ocean water giant blue tail mammal'},
        {'char': '🦈', 'name': 'shark sea swim ocean water predator teeth gray danger hunter'},
        {'char': '🐊', 'name': 'crocodile alligator reptile swamp river green predator wild'},
        {'char': '🐅', 'name': 'tiger animal stripes hunter predator forest jungle safari'},
        {'char': '🐆', 'name': 'leopard cat spots hunter predator safari speed run'},
        {'char': '🦓', 'name': 'zebra horse black white stripes safari savannah'},
        {'char': '🦍', 'name': 'gorilla monkey giant forest wild black power strength'},
        {'char': '🦧', 'name': 'orangutan monkey orange forest wild climb tree hand'},
        {'char': '🦣', 'name': 'mammoth giant elephant tusks ice extinct brown woolly'},
        {'char': '🐘', 'name': 'elephant giant tusks gray trunk safari forest savannah'},
        {'char': '🦛', 'name': 'hippopotamus hippo river water gray giant safari africa'},
        {'char': '🦏', 'name': 'rhinoceros rhino horn gray giant safari africa grass'},
        {'char': '🐪', 'name': 'camel dromedary camel desert dry sand ride hot'},
        {'char': '🐫', 'name': 'bactrian camel camel desert dry sand ride hot two humps'},
        {'char': '🦒', 'name': 'giraffe yellow tall neck spots forest safari savannah'},
        {'char': '🦘', 'name': 'kangaroo pouch jump hop speed australia brown wild'},
        {'char': '🦬', 'name': 'bison buffalo horn giant wild brown grass prairie america'},
        {'char': '🐃', 'name': 'water buffalo buffalo horn giant farm plow wet marsh'},
        {'char': '🐂', 'name': 'ox bull cow farm horn strength pull plow'},
        {'char': '🐄', 'name': 'cow cow farm milk moo grass white spots pasture'},
        {'char': '🐎', 'name': 'horse speed run ride race fast saddle brown stall'},
        {'char': '🐖', 'name': 'pig pink farm oink pork mud snout pasture'},
        {'char': '🐏', 'name': 'ram sheep wool horn mountain white wild pasture'},
        {'char': '🐑', 'name': 'ewe sheep wool lamb white farm warm grass pasture'},
        {'char': '🦙', 'name': 'llama alpaca wool neck white brown mountain peru'},
        {'char': '🐐', 'name': 'goat farm horn mountain wild beard grass pasture'},
        {'char': '🦌', 'name': 'deer forest antlers brown wild run jump horn'},
        {'char': '🐕', 'name': 'dog pet animal puppy wag bark companion tail'},
        {'char': '🐩', 'name': 'poodle pet animal white curly hair style show'},
        {'char': '🦮', 'name': 'guide dog pet animal assistance help support smart lead'},
        {'char': '🐈', 'name': 'cat pet animal kitten meow purr tail claw companion'},
        {'char': '🐓', 'name': 'rooster chicken farm bird dawn morning cluck wake'},
        {'char': '🦃', 'name': 'turkey bird gobble thanksgiving dinner holiday farm feathers'},
        {'char': '🦚', 'name': 'peacock bird colorful feathers beauty tail proud green blue'},
        {'char': '🦜', 'name': 'parrot bird tropical colorful feathers speak fly jungle forest'},
        {'char': '🕊️', 'name': 'dove bird white fly peace freedom olive branch wing'},
        {'char': '🐇', 'name': 'rabbit bunny pet animal carrot long ears speed jump'},
        {'char': '🦝', 'name': 'raccoon wild animal mask tail trash night clever forest gray'},
        {'char': '🦨', 'name': 'skunk wild animal black white stripe tail smell stink danger'},
        {'char': '🦡', 'name': 'badger wild animal black white stripes hole ground fierce strong'},
        {'char': '🦦', 'name': 'otter wild animal river water swim lake cute brown fish'},
        {'char': '🦥', 'name': 'sloth wild animal tree slow forest crawl lazy branch'},
        {'char': '🐿️', 'name': 'chipmunk wild animal nut acorn tail forest tree cute brown'},
        {'char': '🦔', 'name': 'hedgehog wild animal needles defense roll spikes cute small brown'},
        {'char': '🐾', 'name': 'paw prints dog cat animal trace track step sand mud'},
        {'char': '🐉', 'name': 'dragon mythical fire reptile wings green magic history legend'},
        {'char': '🐲', 'name': 'dragon face mythical fire green magic dragon scale mask festival'},
        {'char': '🌵', 'name': 'cactus plant desert dry spike green hot sand warm'},
        {'char': '🎄', 'name': 'christmas tree pine forest green star light holiday celebration'},
        {'char': '🌲', 'name': 'evergreen tree pine forest green nature winter wood branch'},
        {'char': '🌳', 'name': 'deciduous tree forest green wood leaf nature park branch summer'},
        {'char': '🌴', 'name': 'palm tree beach summer island tropical warm sand coast'},
        {'char': '🪵', 'name': 'wood log tree forest fire bonfire timber cut'},
        {'char': '🌱', 'name': 'seedling sprout plant grow green garden nature leaf spring'},
        {'char': '🌿', 'name': 'herb plant leaf green tea seasoning salad nature medicine'},
        {'char': '☘️', 'name': 'shamrock clover green leaf luck holiday irish'},
        {'char': '🍀', 'name': 'four leaf clover green clover leaf luck st patrick'},
        {'char': '🍁', 'name': 'maple leaf autumn fall orange red canada forest leaf tree'},
        {'char': '🍂', 'name': 'fallen leaf autumn fall brown dry orange forest leaf wind'},
        {'char': '🍃', 'name': 'leaf fluttering in wind green leaf breeze wind air nature fresh'},
        {'char': '🍄', 'name': 'mushroom plant red forest fungus garden food super mario'},
        {'char': '🐚', 'name': 'spiral shell sea ocean beach sand sound spiral'},
        {'char': '🪸', 'name': 'coral plant sea ocean fish reef water pink green'},
        {'char': '🪨', 'name': 'rock stone gravel gray heavy hard ground mountain'},
        {'char': '🌾', 'name': 'sheaf of rice wheat harvest field agriculture farm grain autumn'},
        {'char': '💐', 'name': 'bouquet flower gift love valentine beauty spring rose tulip'},
        {'char': '🌷', 'name': 'tulip flower pink red spring garden beauty bulb'},
        {'char': '🌹', 'name': 'rose flower red love romantic valentine garden thorn beauty'},
        {'char': '🥀', 'name': 'wilted flower rose dead dry sad sorry fade drop'},
        {'char': '🌺', 'name': 'hibiscus flower pink red tropical island hawaii beauty warmth'},
        {'char': '🌸', 'name': 'cherry blossom flower pink spring japan sakura beauty petal'},
        {'char': '🌼', 'name': 'blossom flower yellow spring summer garden daisy beauty petal'},
        {'char': '🌻', 'name': 'sunflower flower yellow summer sun garden seed tall beauty'},
        {'char': '🌞', 'name': 'sun with face yellow sun summer warmth sky shine day light'},
        {'char': '🌝', 'name': 'full moon with face yellow night sky space light glow shine'},
        {'char': '🌛', 'name': 'first quarter moon with face yellow night sky crescent space light'},
        {'char': '🌜', 'name': 'last quarter moon with face yellow night sky crescent space light'},
        {'char': '🌚', 'name': 'new moon with face black dark night sky space shadow'},
        {'char': '🌕', 'name': 'full moon yellow white night sky space light glow orb'},
        {'char': '🌖', 'name': 'waning gibbous moon white night sky space shadow light'},
        {'char': '🌗', 'name': 'last quarter moon white half night sky space shadow light'},
        {'char': '🌘', 'name': 'waning crescent moon white crescent night sky space shadow light'},
        {'char': '🌑', 'name': 'new moon black dark night sky space shadow hollow orbit'},
        {'char': '🌒', 'name': 'waxing crescent moon white crescent night sky space shadow light'},
        {'char': '🌓', 'name': 'first quarter moon white half night sky space shadow light'},
        {'char': '🌔', 'name': 'waxing gibbous moon white night sky space shadow light'},
        {'char': '🌙', 'name': 'crescent moon yellow crescent night sky space dream sleep ramadan'},
        {'char': '🌎', 'name': 'globe earth americas space blue planet map ocean continent land'},
        {'char': '🌍', 'name': 'globe earth europe africa space blue planet map ocean continent land'},
        {'char': '🌏', 'name': 'globe earth asia australia space blue planet map ocean continent land'},
        {'char': '🪐', 'name': 'ringed planet saturn space science galaxy orbit celestial'},
        {'char': '💫', 'name': 'dizzy star spin loop circle yellow gold space sparkle magic'},
        {'char': '⭐️', 'name': 'star yellow gold priority favorite rank star score rate'},
        {'char': '🌟', 'name': 'glowing star yellow gold star sparkle shine light priority win'},
        {'char': '✨', 'name': 'sparkles star shine light gold clean clean magic fairy'},
        {'char': '⚡️', 'name': 'high voltage lightning bolt thunder electric energy power speed yellow'},
        {'char': '☄️', 'name': 'comet asteroid space rock fire tail sky ice science'},
        {'char': '💥', 'name': 'collision explode bang fire dynamic hit strike action orange'},
        {'char': '🔥', 'name': 'fire burn hot heat warm cook grill bonfire camp energy speed'},
        {'char': '🌪️', 'name': 'tornado storm wind cloud weather grey twist spin rotate air'},
        {'char': '🌈', 'name': 'rainbow sky rain weather sun colorful arch color magic red green'},
        {'char': '☀️', 'name': 'sun yellow summer warmth sky shine day light dry heat clear'},
        {'char': '🌤️', 'name': 'sun behind small cloud sun weather sky light shadow white grey'},
        {'char': '⛅️', 'name': 'sun behind cloud sun weather sky light shadow white grey'},
        {'char': '🌥️', 'name': 'sun behind large cloud sun weather sky light shadow white grey'},
        {'char': '🌦️', 'name': 'sun behind rain cloud sun weather rain sky water drop cloud'},
        {'char': '☁️', 'name': 'cloud grey white sky weather shade overcast soft puff'},
        {'char': '🌧️', 'name': 'cloud with rain rain weather sky water drop storm wet shadow'},
        {'char': '⛈️', 'name': 'cloud with lightning and rain thunder lightning rain storm weather heavy'},
        {'char': '🌩️', 'name': 'cloud with lightning lightning thunder storm weather electric yellow sky'},
        {'char': '🌨️', 'name': 'cloud with snow snow weather winter ice cold white sky flake'},
        {'char': '❄️', 'name': 'snowflake snow winter cold ice crystal white slide freeze sky'},
        {'char': '☃️', 'name': 'snowman with snow snowman winter cold ice snow white holiday hat'},
        {'char': '⛄️', 'name': 'snowman snowman winter cold ice snow white holiday sport'},
        {'char': '🌬️', 'name': 'wind face wind blow weather air puff breath cold cloud'},
        {'char': '💨', 'name': 'dash of wind speed run fast quick wind air puff escape'},
        {'char': '💧', 'name': 'droplet water drop tear rain sweat clean health blue liquid'},
        {'char': '💦', 'name': 'sweat droplets water splash run wash bath clean wet rain bubble'},
        {'char': '🫧', 'name': 'bubbles soap bubble bath water liquid floating round clean'},
        {'char': '☔️', 'name': 'umbrella with rain drops rain umbrella protection water drop safe shield'},
        {'char': '🌊', 'name': 'water wave sea ocean water swim surf blue storm tide beach'},
        {'char': '🌫️', 'name': 'fog weather gray cloud steam air wet morning dark'},
      ]
    },
    {
      'id': 'food',
      'label': '🍏 Food',
      'emojis': [
        {'char': '🍏', 'name': 'green apple fruit apple sweet green healthy diet'},
        {'char': '🍎', 'name': 'red apple fruit apple sweet red healthy diet teacher'},
        {'char': '🍐', 'name': 'pear fruit yellow green sweet healthy diet'},
        {'char': '🍊', 'name': 'tangerine orange fruit orange vitamin round fresh citrus juice'},
        {'char': '🍋', 'name': 'lemon yellow fruit sour acid tea yellow citrus juice'},
        {'char': '🍌', 'name': 'banana yellow fruit sweet tropical potassium monkey breakfast peel'},
        {'char': '🍉', 'name': 'watermelon green red fruit pink sweet summer water seeds beach'},
        {'char': '🍇', 'name': 'grapes purple green fruit sweet wine cluster vine juice'},
        {'char': '🍓', 'name': 'strawberry red fruit berry sweet summer seed red cake dessert'},
        {'char': '🫐', 'name': 'blueberries blue fruit berry sweet healthy antioxidant breakfast jam'},
        {'char': '🍈', 'name': 'melon cantaloupe green fruit sweet summer juicy water'},
        {'char': '🍒', 'name': 'cherries red fruit sweet twin pair cake dessert red'},
        {'char': '🍑', 'name': 'peach pink orange fruit sweet soft skin butt juicy summer'},
        {'char': '🥭', 'name': 'mango yellow orange fruit sweet tropical summer juicy vitamin'},
        {'char': '🍍', 'name': 'pineapple yellow fruit tropical sweet summer spiky crown'},
        {'char': '🥥', 'name': 'coconut brown fruit tropical water milk shell beach'},
        {'char': '🥝', 'name': 'kiwi green fruit sweet healthy vitamin fuzzy brown'},
        {'char': '🍅', 'name': 'tomato red fruit vegetable salad sauce ketchup garden'},
        {'char': '🍆', 'name': 'eggplant purple vegetable healthy cook dinner garden'},
        {'char': '🥑', 'name': 'avocado green fruit healthy toast salad guacamole fat'},
        {'char': '🥦', 'name': 'broccoli green vegetable healthy tree plant dinner salad'},
        {'char': '🥬', 'name': 'leafy green vegetable lettuce salad healthy green leaf plant'},
        {'char': '🥒', 'name': 'cucumber green vegetable fresh salad pickle water'},
        {'char': '🌶️', 'name': 'hot pepper spicy chili red vegetable fire hot sauce'},
        {'char': '🫑', 'name': 'bell pepper sweet pepper red green yellow vegetable salad'},
        {'char': '🌽', 'name': 'corn maize yellow vegetable summer farm cob butter'},
        {'char': '🥕', 'name': 'carrot orange vegetable healthy rabbit garden vitamin'},
        {'char': '🫒', 'name': 'olive green fruit oil salad mediterranean snack'},
        {'char': '🧄', 'name': 'garlic white vegetable cook seasoning sauce health vampire'},
        {'char': '🧅', 'name': 'onion brown vegetable cook seasoning sauce layer tear'},
        {'char': '🥔', 'name': 'potato brown vegetable cook french fry chip mash'},
        {'char': '🍠', 'name': 'roasted sweet potato orange vegetable cook baked autumn'},
        {'char': '🥐', 'name': 'croissant french bread pastry breakfast butter flaky'},
        {'char': '🥯', 'name': 'bagel bread breakfast cream cheese sandwich sesame'},
        {'char': '🍞', 'name': 'bread loaf toast sandwich breakfast bake wheat'},
        {'char': '🥖', 'name': 'baguette bread french loaf bread dinner crisp'},
        {'char': '🥨', 'name': 'pretzel bread snack salt twisted baked german'},
        {'char': '🧀', 'name': 'cheese wedge cheese yellow dairy slice snack'},
        {'char': '🥚', 'name': 'egg breakfast protein boil fry scramble omelette'},
        {'char': '🍳', 'name': 'cooking frying pan egg breakfast bacon cook chef'},
        {'char': '🥞', 'name': 'pancakes breakfast stack syrup butter sweet maple'},
        {'char': '🧇', 'name': 'waffle breakfast syrup butter sweet belgian'},
        {'char': '🥓', 'name': 'bacon pork meat breakfast crispy fat strip'},
        {'char': '🥩', 'name': 'cut of meat beef steak pork chop dinner grill'},
        {'char': '🍗', 'name': 'poultry leg chicken turkey drumstick meat dinner bone'},
        {'char': '🍖', 'name': 'meat on bone ham bone roast dinner feast'},
        {'char': '🌭', 'name': 'hot dog sausage bun fast food snack baseball'},
        {'char': '🍔', 'name': 'hamburger burger beef fast food lunch dinner snack'},
        {'char': '🍟', 'name': 'french fries potato fast food snack mcdonald salty'},
        {'char': '🍕', 'name': 'pizza italian cheese pepperoni slice dinner party'},
        {'char': '🥪', 'name': 'sandwich bread lunch snack meat cheese veggie'},
        {'char': '🥙', 'name': 'stuffed flatbread gyro wrap falafel lunch mediterranean'},
        {'char': '🫓', 'name': 'flatbread bread naan pita tortilla mediterranean wrap'},
        {'char': '🌮', 'name': 'taco mexican tortilla meat cheese salsa lunch'},
        {'char': '🌯', 'name': 'burrito mexican tortilla wrap meat beans rice'},
        {'char': '🫔', 'name': 'tamale mexican corn masa leaf wrapped filling'},
        {'char': '🥗', 'name': 'green salad vegetable healthy bowl lettuce tomato cucumber'},
        {'char': '🥘', 'name': 'shallow pan of food paella pan dinner rice seafood'},
        {'char': '🍲', 'name': 'pot of food stew soup hot pot dinner broth'},
        {'char': '🫕', 'name': 'fondue cheese chocolate pot melted dip swiss'},
        {'char': '🥫', 'name': 'canned food can vegetables soup tin metal preserve'},
        {'char': '🍝', 'name': 'spaghetti pasta italian tomato sauce noodle dinner'},
        {'char': '🍜', 'name': 'steaming bowl ramen noodle soup japanese asian broth'},
        {'char': '🍛', 'name': 'curry rice indian spicy sauce dinner food'},
        {'char': '🍣', 'name': 'sushi japanese rice fish raw seaweed roll wasabi'},
        {'char': '🍱', 'name': 'bento box japanese lunch box compartment rice fish'},
        {'char': '🥟', 'name': 'dumpling asian chinese japanese potsticker gyoza wonton'},
        {'char': '🍤', 'name': 'fried shrimp tempura shrimp crispy japanese appetizer'},
        {'char': '🍙', 'name': 'rice ball onigiri japanese snack rice seaweed triangle'},
        {'char': '🍘', 'name': 'rice cracker snack japanese crispy seaweed'},
        {'char': '🍥', 'name': 'fish cake with swirl narutomaki japanese ramen topping'},
        {'char': '🥠', 'name': 'fortune cookie chinese dessert cookie prediction'},
        {'char': '🥮', 'name': 'moon cake chinese festival mid autumn pastry dessert'},
        {'char': '🍢', 'name': 'oden japanese skewer stew fish cake daikon'},
        {'char': '🍡', 'name': 'dango japanese dumpling dessert skewer sweet rice'},
        {'char': '🍧', 'name': 'shaved ice dessert sweet cold summer fruit syrup'},
        {'char': '🍨', 'name': 'ice cream dessert sweet cold vanilla bowl'},
        {'char': '🍦', 'name': 'soft ice cream soft serve dessert sweet cold cone'},
        {'char': '🥧', 'name': 'pie pastry dessert fruit bake crust filling'},
        {'char': '🍰', 'name': 'shortcake cake dessert strawberry cream sweet birthday'},
        {'char': '🎂', 'name': 'birthday cake candle celebration party happy'},
        {'char': '🧁', 'name': 'cupcake dessert sweet frosting cake party'},
        {'char': '🍮', 'name': 'custard flan dessert caramel pudding sweet creamy'},
        {'char': '🍭', 'name': 'lollipop candy sweet stick summer fair treat'},
        {'char': '🍬', 'name': 'candy sweet sugar treat wrapper candy'},
        {'char': '🍫', 'name': 'chocolate bar sweet dark milk dessert snack'},
        {'char': '🍿', 'name': 'popcorn movie snack cinema butter salted'},
        {'char': '🍩', 'name': 'doughnut donut dessert coffee snack sugar glaze'},
        {'char': '🍪', 'name': 'cookie dessert snack chocolate chip bake'},
        {'char': '🌰', 'name': 'chestnut brown autumn nut roast winter food'},
        {'char': '🥜', 'name': 'peanuts nuts peanut butter snack allergy legume'},
        {'char': '🫘', 'name': 'beans legume kidney food soup chili'},
        {'char': '🍯', 'name': 'honey pot sweet bee golden syrup bear'},
        {'char': '🥛', 'name': 'glass of milk drink dairy calcium white'},
        {'char': '🍼', 'name': 'baby bottle milk drink infant formula'},
        {'char': '☕️', 'name': 'hot beverage coffee tea warm drink morning'},
        {'char': '🍵', 'name': 'teacup without handle tea green japanese drink cup'},
        {'char': '🧃', 'name': 'juice box drink pack apple box straw children'},
        {'char': '🥤', 'name': 'cup with straw drink soda milkshake fast food'},
        {'char': '🧋', 'name': 'bubble tea boba tea taiwanese milk drink tapioca'},
        {'char': '🍶', 'name': 'sake japanese rice wine drink bottle pour'},
        {'char': '🍺', 'name': 'beer mug drink alcohol beer ale pub brew'},
        {'char': '🍻', 'name': 'clinking beer mugs cheers drink toast celebration party'},
        {'char': '🥂', 'name': 'clinking glasses cheers toast celebration party drink wine'},
        {'char': '🍷', 'name': 'wine glass drink red white alcohol celebration'},
        {'char': '🥃', 'name': 'tumbler glass whiskey whisky drink alcohol liquor'},
        {'char': '🍸', 'name': 'cocktail glass drink martini alcohol party'},
        {'char': '🍹', 'name': 'tropical drink cocktail fruit summer umbrella vacation'},
        {'char': '🧉', 'name': 'mate yerba mate tea argentina drink south america'},
        {'char': '🍾', 'name': 'bottle with popping cork champagne celebrate wine party'},
        {'char': '🧊', 'name': 'ice cube cold water drink freezer cocktail'},
        {'char': '🥢', 'name': 'chopsticks japanese chinese asian eat food utensil'},
        {'char': '🍽️', 'name': 'fork and knife with plate meal dinner restaurant food'},
        {'char': '🍴', 'name': 'fork and knife utensil eat cutlery dinner'},
        {'char': '🥄', 'name': 'spoon utensil eat soup stir measure cutlery'},
      ]
    },
    {
      'id': 'activity',
      'label': '⚽️ Activity',
      'emojis': [
        {'char': '⚽️', 'name': 'soccer ball football sport game goal pitch'},
        {'char': '🏀', 'name': 'basketball ball sport hoop game nba'},
        {'char': '🏈', 'name': 'american football ball sport nfl gridiron'},
        {'char': '⚾️', 'name': 'baseball ball sport game bat pitch'},
        {'char': '🥎', 'name': 'softball ball sport game bat pitcher'},
        {'char': '🎾', 'name': 'tennis ball sport racket game court'},
        {'char': '🏐', 'name': 'volleyball ball sport game net'},
        {'char': '🏉', 'name': 'rugby football ball sport oval kick'},
        {'char': '🥏', 'name': 'flying disc frisbee sport ultimate throw'},
        {'char': '🎱', 'name': 'pool 8 ball billiard snooker game sport'},
        {'char': '🪀', 'name': 'yo yo toy spin string play'},
        {'char': '🏓', 'name': 'ping pong table tennis paddle ball sport'},
        {'char': '🏸', 'name': 'badminton racket shuttlecock sport game'},
        {'char': '🏒', 'name': 'ice hockey stick puck sport game rink'},
        {'char': '🏑', 'name': 'field hockey stick ball sport game'},
        {'char': '🥍', 'name': 'lacrosse stick ball sport goal'},
        {'char': '🏹', 'name': 'bow and arrow archery sport target shoot'},
        {'char': '🤿', 'name': 'diving mask scuba snorkel dive ocean'},
        {'char': '🥊', 'name': 'boxing glove punch sport fight gym'},
        {'char': '🥋', 'name': 'martial arts uniform karate taekwondo judo belt'},
        {'char': '🥅', 'name': 'goal net soccer hockey score'},
        {'char': '⛳️', 'name': 'flag in hole golf sport tee green'},
        {'char': '⛸️', 'name': 'ice skate figure skating sport winter blade'},
        {'char': '🎽', 'name': 'running shirt singlet sport race'},
        {'char': '🎿', 'name': 'skis ski winter sport snow mountain'},
        {'char': '🛷', 'name': 'sled sleigh winter snow slide ride'},
        {'char': '🥌', 'name': 'curling stone sport ice sweep winter'},
        {'char': '🎯', 'name': 'direct hit bullseye target dart goal aim'},
        {'char': '🪗', 'name': 'accordion musical instrument squeeze box play'},
        {'char': '🪘', 'name': 'drum musical instrument beat rhythm conga'},
        {'char': '🎮', 'name': 'video game controller play console nintendo'},
        {'char': '🕹️', 'name': 'joystick arcade game controller retro play'},
        {'char': '🎰', 'name': 'slot machine casino gamble jackpot reel'},
        {'char': '🎲', 'name': 'game die dice board game random number'},
        {'char': '🧩', 'name': 'puzzle piece jigsaw fit completion challenge'},
        {'char': '🧸', 'name': 'teddy bear plush toy soft cuddle childhood'},
        {'char': '🪅', 'name': 'pinata party candy mexican celebration hit'},
        {'char': '🪩', 'name': 'mirror ball disco dance party music glitter'},
        {'char': '🎨', 'name': 'artist palette paint color creative art draw'},
        {'char': '🖼️', 'name': 'framed picture frame art painting photo gallery'},
        {'char': '🧵', 'name': 'thread sewing needle stitch yarn craft'},
        {'char': '🪡', 'name': 'sewing needle stitch thread tailor craft'},
        {'char': '🧶', 'name': 'yarn wool knitting crochet craft ball'},
        {'char': '🎸', 'name': 'guitar musical instrument rock string play'},
        {'char': '🎹', 'name': 'musical keyboard piano organ music instrument play'},
        {'char': '🎺', 'name': 'trumpet musical instrument brass jazz play'},
        {'char': '🎻', 'name': 'violin musical instrument string classical bow play'},
        {'char': '🥁', 'name': 'drum musical instrument beat rhythm stick'},
        {'char': '🪕', 'name': 'banjo musical instrument string folk bluegrass play'},
        {'char': '🎧', 'name': 'headphone music listen audio sound earphone'},
        {'char': '🎤', 'name': 'microphone sing karaoke music speech vocal'},
        {'char': '🎬', 'name': 'clapper board movie film director action'},
        {'char': '🎟️', 'name': 'admission tickets ticket event concert movie'},
        {'char': '🎫', 'name': 'ticket admission event entrance permit'},
        {'char': '🎭', 'name': 'performing arts theater mask comedy drama play'},
        {'char': '🎪', 'name': 'circus tent performance carnival clown entertainment'},
        {'char': '🧗', 'name': 'person climbing rock climb sport mountain'},
        {'char': '🏋️', 'name': 'person lifting weights gym sport exercise strong'},
        {'char': '🚴', 'name': 'person biking bicycle cycling sport race'},
        {'char': '🏃', 'name': 'person running run jog sprint race sport'},
        {'char': '🚶', 'name': 'person walking walk stroll step move'},
        {'char': '🚗', 'name': 'car automobile vehicle drive red road'},
        {'char': '🚕', 'name': 'taxi cab car vehicle ride transport'},
        {'char': '🚙', 'name': 'suv sport utility vehicle car offroad'},
        {'char': '🚌', 'name': 'bus vehicle transport school transit public'},
        {'char': '🚎', 'name': 'trolleybus bus electric transit transport'},
        {'char': '🏎️', 'name': 'racing car formula f1 speed race sport'},
        {'char': '🚓', 'name': 'police car patrol law enforcement vehicle'},
        {'char': '🚑', 'name': 'ambulance medical emergency vehicle hospital health'},
        {'char': '🚒', 'name': 'fire engine truck firefighter emergency rescue'},
        {'char': '🚐', 'name': 'minibus van vehicle shuttle transport'},
        {'char': '🛻', 'name': 'pickup truck vehicle farm transport cargo'},
        {'char': '🚚', 'name': 'delivery truck van cargo transport vehicle'},
        {'char': '🚛', 'name': 'articulated lorry truck tractor trailer transport'},
        {'char': '🚜', 'name': 'tractor farm vehicle agriculture harvest field'},
        {'char': '🛵', 'name': 'motor scooter vespa bike transport moped'},
        {'char': '🏍️', 'name': 'motorcycle bike motorbike ride sport'},
        {'char': '🛺', 'name': 'auto rickshaw tuk tuk three wheel transport'},
        {'char': '🚲', 'name': 'bicycle bike cycle sport ride'},
        {'char': '🛴', 'name': 'kick scooter ride children toy transport'},
        {'char': '🛹', 'name': 'skateboard ride sport board trick'},
        {'char': '🛼', 'name': 'roller skate skate sport rollerblade'},
        {'char': '🚏', 'name': 'bus stop sign transport wait station'},
        {'char': '🛣️', 'name': 'motorway highway road drive asphalt'},
        {'char': '🛤️', 'name': 'railway track train rail road tracks'},
        {'char': '🚢', 'name': 'ship boat sea ocean transport cruise'},
        {'char': '⛵️', 'name': 'sailboat boat sail ocean sea wind'},
        {'char': '🚤', 'name': 'speedboat boat fast water ocean ride'},
        {'char': '🛥️', 'name': 'motor boat boat sea ocean water'},
        {'char': '🛳️', 'name': 'passenger ship cruise ferry ocean sea'},
        {'char': '⛴️', 'name': 'ferry boat transport sea ocean water'},
        {'char': '🛶', 'name': 'canoe kayak paddle boat water river'},
        {'char': '🛸', 'name': 'flying saucer ufo alien space sci fi'},
        {'char': '🚁', 'name': 'helicopter vehicle fly air transport rotor'},
        {'char': '🛩️', 'name': 'small airplane fly air travel private'},
        {'char': '✈️', 'name': 'airplane fly travel flight air plane'},
        {'char': '🛫', 'name': 'airplane departure takeoff fly travel airport'},
        {'char': '🛬', 'name': 'airplane arrival landing fly travel airport'},
        {'char': '🚀', 'name': 'rocket space ship launch nasa science'},
        {'char': '🛰️', 'name': 'satellite space orbit communication gps'},
        {'char': '⚓️', 'name': 'anchor ship boat sea ocean navy'},
        {'char': '🗺️', 'name': 'world map geography travel navigation globe'},
        {'char': '🧭', 'name': 'compass navigation direction travel north'},
        {'char': '🏔️', 'name': 'snow capped mountain peak snow climb mt'},
        {'char': '⛰️', 'name': 'mountain hill peak nature landscape'},
        {'char': '🌋', 'name': 'volcano lava eruption mountain fire hot'},
        {'char': '🗻', 'name': 'mount fuji japan mountain snow peak'},
        {'char': '🏕️', 'name': 'camping tent camp outdoor forest nature'},
        {'char': '🏖️', 'name': 'beach with umbrella sand ocean sun summer vacation'},
        {'char': '🏜️', 'name': 'desert sand dry hot dunes landscape'},
        {'char': '🏝️', 'name': 'desert island palm tree ocean sand tropical'},
        {'char': '🏞️', 'name': 'national park nature valley mountain river'},
        {'char': '🏛️', 'name': 'classical building column architecture museum'},
        {'char': '🏗️', 'name': 'building construction crane site building'},
        {'char': '🧱', 'name': 'brick wall construction building material clay'},
        {'char': '🏘️', 'name': 'houses neighborhood building city residential'},
        {'char': '🏚️', 'name': 'derelict house abandoned old ruin building'},
        {'char': '🏠', 'name': 'house home building residence roof door'},
        {'char': '🏡', 'name': 'house with garden home flower yard tree'},
        {'char': '🏢', 'name': 'office building skyscraper workplace corporate'},
        {'char': '🏣', 'name': 'japanese post office mail building'},
        {'char': '🏤', 'name': 'post office mail building european'},
        {'char': '🏥', 'name': 'hospital medical health building doctor'},
        {'char': '🏦', 'name': 'bank building finance money building'},
        {'char': '🏨', 'name': 'hotel building accommodation travel stay'},
        {'char': '🏩', 'name': 'love hotel heart building romantic'},
        {'char': '🏪', 'name': 'convenience store shop mart building'},
        {'char': '🏫', 'name': 'school building education learn classroom'},
        {'char': '🏬', 'name': 'department store shop mall retail'},
        {'char': '🏭', 'name': 'factory building industry manufacturing plant'},
        {'char': '🏯', 'name': 'japanese castle building landmark architecture'},
        {'char': '🏰', 'name': 'castle palace building kingdom fortress'},
        {'char': '💒', 'name': 'wedding chapel heart love marriage church'},
        {'char': '🗼', 'name': 'tokyo tower japan landmark building city'},
        {'char': '🗽', 'name': 'statue of liberty new york landmark usa'},
        {'char': '🕌', 'name': 'mosque islam building worship religion muslim'},
        {'char': '⛪️', 'name': 'church christian building worship religion cross'},
        {'char': '🛕', 'name': 'hindu temple building worship religion'},
        {'char': '🕍', 'name': 'synagogue jewish building worship religion'},
        {'char': '⛩️', 'name': 'shinto shrine japan gate torii religion'},
        {'char': '🕋', 'name': 'kaaba mecca islam muslim building worship'},
        {'char': '⛲️', 'name': 'fountain water park garden spray'},
        {'char': '⛺️', 'name': 'tent camp outdoor camping shelter'},
        {'char': '🌁', 'name': 'foggy weather fog bridge city mist'},
        {'char': '🌃', 'name': 'night with stars night sky star city dark'},
        {'char': '🏙️', 'name': 'cityscape skyline building city urban'},
        {'char': '🌅', 'name': 'sunrise sun morning sky ocean beach'},
        {'char': '🌄', 'name': 'sunrise over mountains sun morning mountain'},
        {'char': '🌇', 'name': 'sunset sun evening city sky building dusk'},
        {'char': '🌆', 'name': 'cityscape at dusk city evening sunset glow'},
        {'char': '🌉', 'name': 'bridge at night bridge light water reflection'},
        {'char': '🎠', 'name': 'carousel horse merry go round fair fun'},
        {'char': '🎡', 'name': 'ferris wheel fair carnival amusement park'},
        {'char': '🎢', 'name': 'roller coaster amusement park ride fun thrill'},
        {'char': '💈', 'name': 'barber pole haircut salon shop stripe sign'},
      ]
    },
    {
      'id': 'objects',
      'label': '💡 Objects',
      'emojis': [
        {'char': '⌚️', 'name': 'watch time wrist clock accessory wear'},
        {'char': '📱', 'name': 'mobile phone smartphone device screen tech'},
        {'char': '📲', 'name': 'mobile phone with arrow call incoming outgoing'},
        {'char': '💻', 'name': 'laptop computer notebook tech device work'},
        {'char': '⌨️', 'name': 'keyboard computer type device input'},
        {'char': '🖥️', 'name': 'desktop computer pc monitor work tech'},
        {'char': '🖨️', 'name': 'printer computer device output paper'},
        {'char': '🖱️', 'name': 'computer mouse device pointer click'},
        {'char': '🖲️', 'name': 'trackball computer mouse device input'},
        {'char': '💽', 'name': 'computer disk minidisk storage data'},
        {'char': '💾', 'name': 'floppy disk save storage retro computer'},
        {'char': '💿', 'name': 'optical disk cd dvd storage data'},
        {'char': '📀', 'name': 'dvd disk movie storage data video'},
        {'char': '📼', 'name': 'videocassette vhs tape retro movie'},
        {'char': '📷', 'name': 'camera photo picture capture device'},
        {'char': '📸', 'name': 'camera with flash photo picture capture'},
        {'char': '📹', 'name': 'video camera camcorder record film'},
        {'char': '🎥', 'name': 'movie camera film director cinema clap'},
        {'char': '📽️', 'name': 'film projector movie cinema retro'},
        {'char': '🎞️', 'name': 'film frames movie cinema strip frames'},
        {'char': '📞', 'name': 'telephone receiver handset call phone'},
        {'char': '☎️', 'name': 'telephone phone call contact classic'},
        {'char': '📟', 'name': 'pager beeper retro device message'},
        {'char': '📠', 'name': 'fax machine document send device'},
        {'char': '📺', 'name': 'television tv screen show watch'},
        {'char': '📻', 'name': 'radio audio music broadcast device'},
        {'char': '🎙️', 'name': 'studio microphone record podcast vocal'},
        {'char': '🎚️', 'name': 'level slider volume control audio mix'},
        {'char': '🎛️', 'name': 'control knobs dial audio mixer studio'},
        {'char': '🧭', 'name': 'compass navigation direction travel'},
        {'char': '⏰', 'name': 'alarm clock wake up morning time'},
        {'char': '⌛️', 'name': 'hourglass done time sand timer countdown'},
        {'char': '⏳', 'name': 'hourglass not done time sand timer counting'},
        {'char': '🔋', 'name': 'battery power energy charge full'},
        {'char': '🔌', 'name': 'electric plug power socket connect'},
        {'char': '💡', 'name': 'light bulb idea light bright creativity'},
        {'char': '🕯️', 'name': 'candle wax light fire flame'},
        {'char': '🪔', 'name': 'diya lamp oil indian festival light deepavali'},
        {'char': '🗑️', 'name': 'wastebasket trash garbage delete bin'},
        {'char': '🛢️', 'name': 'oil drum barrel petroleum fuel'},
        {'char': '💸', 'name': 'money with wings fly spend cash lose'},
        {'char': '💵', 'name': 'dollar banknote money currency usd'},
        {'char': '💴', 'name': 'yen banknote money currency japan'},
        {'char': '💶', 'name': 'euro banknote money currency europe'},
        {'char': '💷', 'name': 'pound banknote money currency uk'},
        {'char': '🪙', 'name': 'coin money gold silver metal currency'},
        {'char': '💰', 'name': 'money bag sack cash fortune treasure'},
        {'char': '💳', 'name': 'credit card payment money debit bank'},
        {'char': '💎', 'name': 'gem diamond jewel stone precious ring'},
        {'char': '⚖️', 'name': 'balance scale justice weigh law legal'},
        {'char': '🪜', 'name': 'ladder climb step height reach'},
        {'char': '🔧', 'name': 'wrench tool spanner fix repair'},
        {'char': '🔨', 'name': 'hammer tool build nail fix carpentry'},
        {'char': '⚒️', 'name': 'hammer and pick tool mining rock'},
        {'char': '🛠️', 'name': 'hammer and wrench tool repair fix'},
        {'char': '⛏️', 'name': 'pick tool mining mountain rock'},
        {'char': '🪚', 'name': 'carpenter saw wood cut tool'},
        {'char': '🔩', 'name': 'nut and bolt screw fastener hardware metal'},
        {'char': '⚙️', 'name': 'gear mechanical cog settings machine'},
        {'char': '🧱', 'name': 'brick wall construction building material clay'},
        {'char': '⛓️', 'name': 'chains chain link metal link'},
        {'char': '🧲', 'name': 'magnet attract metal magnetic science'},
        {'char': '🧯', 'name': 'fire extinguisher safety fire emergency'},
        {'char': '🔫', 'name': 'water pistol gun toy weapon play'},
        {'char': '💣', 'name': 'bomb explode explosive danger boom'},
        {'char': '🧨', 'name': 'firecracker fireworks bang celebration explode'},
        {'char': '🪓', 'name': 'axe tool wood chop lumberjack'},
        {'char': '🔪', 'name': 'kitchen knife chef cut cook weapon'},
        {'char': '🗡️', 'name': 'dagger weapon knife blade stab'},
        {'char': '⚔️', 'name': 'crossed swords fight battle war knight'},
        {'char': '🛡️', 'name': 'shield protect defend knight weapon armor'},
        {'char': '🚬', 'name': 'cigarette smoke tobacco nicotine'},
        {'char': '⚰️', 'name': 'coffin death funeral dead bury'},
        {'char': '⚱️', 'name': 'funeral urn cremation ash dead'},
        {'char': '🏺', 'name': 'amphora vase pottery ancient jar'},
        {'char': '🔮', 'name': 'crystal ball fortune future magic psychic'},
        {'char': '📿', 'name': 'prayer beads rosary religion buddhist'},
        {'char': '🧿', 'name': 'nazar amulet eye protection evil charm'},
        {'char': '💈', 'name': 'barber pole haircut salon shop stripe'},
        {'char': '🧫', 'name': 'petri dish biology lab culture bacteria'},
        {'char': '🧪', 'name': 'test tube science lab chemistry experiment'},
        {'char': '🔬', 'name': 'microscope science lab research zoom'},
        {'char': '🔭', 'name': 'telescope astronomy space stargazing science'},
        {'char': '📡', 'name': 'satellite antenna dish signal communication'},
        {'char': '💉', 'name': 'syringe needle injection medical vaccine'},
        {'char': '💊', 'name': 'pill medicine drug capsule health pharmacy'},
        {'char': '🩹', 'name': 'adhesive bandage band aid first aid medical'},
        {'char': '🩺', 'name': 'stethoscope doctor medical health heart'},
        {'char': '🚪', 'name': 'door entrance exit room home'},
        {'char': '🛗', 'name': 'elevator lift access floor building'},
        {'char': '🪞', 'name': 'mirror reflection look glass face'},
        {'char': '🪟', 'name': 'window frame glass view light house'},
        {'char': '🛏️', 'name': 'bed sleep bedroom rest hotel'},
        {'char': '🛋️', 'name': 'couch and lamp sofa furniture living room'},
        {'char': '🪑', 'name': 'chair seat sit furniture office'},
        {'char': '🚽', 'name': 'toilet bathroom restroom wc'},
        {'char': '🪠', 'name': 'plumber plunger toilet unclog tool'},
        {'char': '🚿', 'name': 'shower bath water bathroom clean'},
        {'char': '🛁', 'name': 'bathtub bath bubble relax soak'},
        {'char': '🧼', 'name': 'soap clean wash bath hygiene bar'},
        {'char': '🪥', 'name': 'toothbrush teeth clean dental hygiene'},
        {'char': '🪮', 'name': 'comb hair brush detangle groom'},
        {'char': '🧴', 'name': 'lotion bottle moisturizer cream dispenser'},
        {'char': '🧹', 'name': 'broom clean sweep witch fly tool'},
        {'char': '🧺', 'name': 'basket laundry picnic hamper woven'},
        {'char': '🧻', 'name': 'roll of paper toilet paper towel roll'},
        {'char': '🪣', 'name': 'bucket water mop wash clean container'},
        {'char': '🗝️', 'name': 'old key lock door antique vintage'},
        {'char': '🔑', 'name': 'key lock unlock door access entry'},
        {'char': '🪤', 'name': 'mouse trap rodent catch bait'},
        {'char': '📦', 'name': 'package box parcel delivery gift'},
        {'char': '🏷️', 'name': 'label tag price name sticker'},
        {'char': '✉️', 'name': 'envelope mail letter email send'},
        {'char': '📩', 'name': 'envelope with arrow outgoing mail sent'},
        {'char': '📨', 'name': 'incoming envelope mail receive letter'},
        {'char': '📧', 'name': 'e mail email envelope message digital'},
        {'char': '📤', 'name': 'outbox tray outgoing mail send'},
        {'char': '📥', 'name': 'inbox tray incoming mail receive'},
        {'char': '📪', 'name': 'closed mailbox with lowered flag mail delivered'},
        {'char': '📫', 'name': 'closed mailbox with raised flag mail waiting'},
        {'char': '📬', 'name': 'open mailbox with raised flag mail new'},
        {'char': '📭', 'name': 'open mailbox with lowered flag mail empty'},
        {'char': '📮', 'name': 'postbox mail letter post drop box'},
        {'char': '🗳️', 'name': 'ballot box vote election democracy'},
        {'char': '✏️', 'name': 'pencil write draw school stationery'},
        {'char': '✒️', 'name': 'black nib pen write fountain'},
        {'char': '🖋️', 'name': 'fountain pen write ink signature'},
        {'char': '🖊️', 'name': 'pen ballpoint write ink office'},
        {'char': '🖌️', 'name': 'paintbrush paint color art draw creative'},
        {'char': '🖍️', 'name': 'crayon draw color art kid childhood'},
        {'char': '📝', 'name': 'memo note document write paper'},
        {'char': '📁', 'name': 'file folder document organize directory'},
        {'char': '📂', 'name': 'open file folder document directory'},
        {'char': '🗂️', 'name': 'card index dividers organize tab folder'},
        {'char': '📅', 'name': 'calendar date event schedule day'},
        {'char': '📆', 'name': 'tear off calendar date day schedule'},
        {'char': '🗒️', 'name': 'spiral notepad note pad paper'},
        {'char': '🗓️', 'name': 'spiral calendar date day planner'},
        {'char': '🪪', 'name': 'identification card id identity badge'},
        {'char': '🗃️', 'name': 'card file box organize storage'},
        {'char': '🗄️', 'name': 'file cabinet office storage drawer'},
        {'char': '📋', 'name': 'clipboard note list document paper'},
        {'char': '📌', 'name': 'pushpin pin mark location attach'},
        {'char': '📍', 'name': 'round pushpin pin location map mark'},
        {'char': '📎', 'name': 'paperclip attach document office'},
        {'char': '🖇️', 'name': 'linked paperclips attach together documents'},
        {'char': '📏', 'name': 'straight ruler measure length draw'},
        {'char': '📐', 'name': 'triangular ruler measure angle architect'},
        {'char': '🧮', 'name': 'abacus count calculate math beads'},
        {'char': '🔐', 'name': 'locked with key security safe locked'},
        {'char': '🔏', 'name': 'locked with pen signature locked'},
        {'char': '🔒', 'name': 'locked padlock security private safe'},
        {'char': '🔓', 'name': 'unlocked padlock open security public'},
        {'char': '❤️', 'name': 'red heart love heart romantic valentine passion'},
        {'char': '🧡', 'name': 'orange heart love heart warm affection'},
        {'char': '💛', 'name': 'yellow heart love heart friend happiness'},
        {'char': '💚', 'name': 'green heart love heart nature envy'},
        {'char': '💙', 'name': 'blue heart love heart trust calm'},
        {'char': '💜', 'name': 'purple heart love heart royal mystical'},
        {'char': '🖤', 'name': 'black heart love heart dark evil'},
        {'char': '🤍', 'name': 'white heart love heart pure clean'},
        {'char': '🤎', 'name': 'brown heart love heart earth warm'},
        {'char': '💔', 'name': 'broken heart heartbreak sad love broken'},
        {'char': '❣️', 'name': 'heart exclamation love passion emphasize'},
        {'char': '💕', 'name': 'two hearts love couple romance'},
        {'char': '💞', 'name': 'revolving hearts love spin circle'},
        {'char': '💓', 'name': 'beating heart love pulse heartbeat alive'},
        {'char': '💗', 'name': 'growing heart love increase size pulse'},
        {'char': '💖', 'name': 'sparkling heart love sparkle shiny cute'},
        {'char': '💘', 'name': 'heart with arrow love cupid romance'},
        {'char': '💝', 'name': 'heart with ribbon love gift valentine box'},
        {'char': '💟', 'name': 'heart decoration love ornament symbol'},
        {'char': '☮️', 'name': 'peace symbol sign harmony'},
        {'char': '✝️', 'name': 'latin cross christian religion faith'},
        {'char': '☪️', 'name': 'star and crescent islam muslim religion'},
        {'char': '🕉️', 'name': 'om symbol hindu religion meditation'},
        {'char': '☸️', 'name': 'wheel of dharma buddhist religion symbol'},
        {'char': '✡️', 'name': 'star of david judaism religion symbol'},
        {'char': '🔯', 'name': 'six pointed star dotted star david'},
        {'char': '🕎', 'name': 'menorah hanukkah candelabrum jewish holiday'},
        {'char': '☯️', 'name': 'yin yang taoist balance symbol'},
        {'char': '☦️', 'name': 'orthodox cross christian religion faith'},
        {'char': '🛐', 'name': 'place of worship religion prayer god'},
        {'char': '♈️', 'name': 'aries ram zodiac sign constellation'},
        {'char': '♉️', 'name': 'taurus bull zodiac sign constellation'},
        {'char': '♊️', 'name': 'gemini twins zodiac sign constellation'},
        {'char': '♋️', 'name': 'cancer crab zodiac sign constellation'},
        {'char': '♎️', 'name': 'libra balance zodiac sign constellation'},
        {'char': '♍️', 'name': 'virgo maiden zodiac sign constellation'},
        {'char': '♎️', 'name': 'libra balance zodiac sign constellation'},
        {'char': '♏️', 'name': 'scorpius scorpion zodiac sign constellation'},
        {'char': '♐️', 'name': 'sagittarius archer zodiac sign constellation'},
        {'char': '♑️', 'name': 'capricorn sea goat zodiac sign constellation'},
        {'char': '♒️', 'name': 'aquarius water bearer zodiac sign constellation'},
        {'char': '♓️', 'name': 'pisces fish zodiac sign constellation'},
        {'char': '🆔', 'name': 'id button identification identity symbol'},
        {'char': '📯', 'name': 'postal horn post trumpet mail'},
        {'char': '🔔', 'name': 'bell notification ring alert sound'},
        {'char': '🔕', 'name': 'bell with slash mute silent quiet'},
        {'char': '📣', 'name': 'megaphone announcement loud speaker public'},
        {'char': '📢', 'name': 'loudspeaker announcement notification public'},
        {'char': '💬', 'name': 'speech balloon chat talk message bubble'},
        {'char': '💭', 'name': 'thought balloon think idea bubble dream'},
        {'char': '🗯️', 'name': 'right anger bubble speech angry shout'},
        {'char': '🏁', 'name': 'chequered flag race finish winner goal'},
        {'char': '🚩', 'name': 'triangular flag post pin marker'},
        {'char': '🎌', 'name': 'crossed flags japan celebration'},
        {'char': '🏴', 'name': 'black flag pirate dark anarchy'},
        {'char': '🏳️', 'name': 'white flag surrender truce peace'},
        {'char': '🏳️🌈', 'name': 'rainbow flag pride lgbtq gay'},
        {'char': '🏴☠️', 'name': 'pirate flag skull crossbones jolly roger'},
      ]
    }
  ];

  @override
  void initState() {
    super.initState();
    _serverService = widget.serverService;
    _serverService.addListener(_onServerStateChanged);
    _loadRecentEmojis();
  }

  Future<void> _loadRecentEmojis() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/recent_emojis.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        setState(() {
          _recentEmojis = list.cast<String>();
        });
      }
    } catch (e) {
      debugPrint('Error loading recent emojis: $e');
    }
  }

  Future<void> _saveRecentEmoji(String emoji) async {
    final updated = [emoji, ..._recentEmojis.where((e) => e != emoji)].take(8).toList();
    setState(() {
      _recentEmojis = updated;
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/recent_emojis.json');
      await file.writeAsString(jsonEncode(updated));
    } catch (e) {
      debugPrint('Error saving recent emojis: $e');
    }
  }

  @override
  void dispose() {
    _serverService.removeListener(_onServerStateChanged);
    _titleController.dispose();
    _titleFocusNode.dispose();
    _saveDebounceTimer?.cancel();
    _clientIpController.dispose();
    _clientPinController.dispose();
    super.dispose();
  }

  void _onServerStateChanged() {
    if (mounted) {
      setState(() {
        if (_selectedPage != null) {
          final updatedPage = _serverService.pages.firstWhere(
            (p) => p.id == _selectedPage!.id,
            orElse: () => _selectedPage!,
          );

          if (!_serverService.pages.any((p) => p.id == _selectedPage!.id)) {
            _selectedPage = null;
            _navigationHistory.clear();
            _pageCards = [];
          } else {
            _selectedPage = updatedPage;
            if (!_titleFocusNode.hasFocus) {
              _titleController.text = updatedPage.title;
            }
            _loadCardsForPage(updatedPage.id);
          }
        }

        _checkPendingConnections();
      });
    }
  }

  Future<void> _loadCardsForPage(String pageId) async {
    try {
      final cards = await _serverService.getCards(pageId);
      final sidePages = await _serverService.getSidePages(pageId);
      setState(() {
        _pageCards = cards;
        _sidePages = sidePages;
      });
    } catch (e) {
      debugPrint('Error loading cards: $e');
    }
  }

  Future<void> _refreshSelectedPage() async {
    final page = _selectedPage;
    if (page == null || _isRefreshingPage) return;

    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (_selectedPage != null) {
      final newTitle = _titleController.text.trim().isEmpty
          ? 'Untitled'
          : _titleController.text.trim();

      _serverService.updatePage(
        id: _selectedPage!.id,
        title: newTitle,
        emoji: _selectedPage!.emoji,
      );
    }
    setState(() => _isRefreshingPage = true);

    try {
      if (!_serverService.isClientMode) {
        await _serverService.loadDatabaseState();
      }
      if (!mounted) return;

      final refreshedPage = _serverService.pages
          .where((candidate) => candidate.id == page.id)
          .firstOrNull;

      if (refreshedPage == null) {
        setState(() {
          _selectedPage = null;
          _navigationHistory.clear();
          _pageCards = [];
          _sidePages = [];
        });
        return;
      }

      _selectedPage = refreshedPage;
      if (!_titleFocusNode.hasFocus) {
        _titleController.text = refreshedPage.title;
      }
      await _loadCardsForPage(refreshedPage.id);
    } catch (e) {
      debugPrint('Error refreshing page: $e');
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPage = false);
      }
    }
  }

  void _checkPendingConnections() {
    final pendingList = _serverService.pendingConnections;
    if (pendingList.isEmpty) return;

    for (int i = 0; i < pendingList.length; i++) {
      final pending = pendingList[i];
      _showPairingDialog(i, pending.remoteAddress);
    }
  }

  void _showPairingDialog(int index, String remoteAddress) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('Pairing Request'),
        content: Text(
          'Device at $remoteAddress wants to connect to your journal.\n\nAllow this connection?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              _serverService.rejectPendingClient(index);
              Navigator.pop(ctx);
            },
            child: const Text(
              'Deny',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _serverService.approvePendingClient(index);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF818CF8),
            ),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }

  void _selectPage(DbPage page, {bool pushToHistory = true}) {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (_selectedPage != null) {
      final newTitle = _titleController.text.trim().isEmpty
          ? 'Untitled'
          : _titleController.text.trim();

      _serverService.updatePage(
        id: _selectedPage!.id,
        title: newTitle,
        emoji: _selectedPage!.emoji,
      );
    }
    _titleFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    if (pushToHistory &&
        _selectedPage != null &&
        _selectedPage!.id != page.id) {
      _navigationHistory.add(_selectedPage!.id);
    }
    setState(() {
      _selectedPage = page;
      _titleController.text = page.title;
      _pageCards = [];
      _sidePages = [];
    });
    _loadCardsForPage(page.id);
  }

  void _goBack() {
    while (_navigationHistory.isNotEmpty) {
      final prevId = _navigationHistory.removeLast();
      final exists = _serverService.pages.any((p) => p.id == prevId);
      if (exists) {
        final prevPage = _serverService.pages.firstWhere((p) => p.id == prevId);
        _selectPage(prevPage, pushToHistory: false);
        return;
      }
    }
  }

  void _saveCurrentPage() {
    if (_selectedPage == null) return;

    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveDebounceTimer?.cancel();
      _saveDebounceTimer = null;
      if (_selectedPage != null) {
        final newTitle = _titleController.text.trim().isEmpty
            ? 'Untitled'
            : _titleController.text.trim();

        _serverService.updatePage(
          id: _selectedPage!.id,
          title: newTitle,
          emoji: _selectedPage!.emoji,
        );
      }
    });
  }

  void _saveCurrentPageImmediate() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (_selectedPage != null) {
      final newTitle = _titleController.text.trim().isEmpty
          ? 'Untitled'
          : _titleController.text.trim();

      _serverService.updatePage(
        id: _selectedPage!.id,
        title: newTitle,
        emoji: _selectedPage!.emoji,
      );
    }
  }

  Future<DbPage?> _createSubpage(
    String? parentId, {
    String relationType = 'subpage',
  }) async {
    final newPage = await _serverService.addPage(
      parentId: parentId,
      relationType: relationType,
      title: 'New Page',
      emoji: '📝',
    );

    await _serverService.addCard(
      pageId: newPage.id,
      type: 'markdown',
      content: '# New Page\n\nStart writing markdown here...',
    );

    _selectPage(newPage);

    if (parentId != null) {
      setState(() {
        _expandedPageIds.add(parentId);
      });
    }

    return newPage;
  }

  void _archiveSelectedPage(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('Archive Page?'),
        content: const Text(
          'This will archive this page and all subpages nested inside it. You can restore them later from the trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_selectedPage?.id == id) {
                setState(() {
                  _selectedPage = null;
                  _navigationHistory.clear();
                });
              }
              await _serverService.deletePage(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveDialog() async {
    final allPages = _serverService.pages;
    final currentPage = _selectedPage;
    if (currentPage == null) return;

    final selectedParent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('Move Page To...'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.folder_off_outlined,
                  color: Colors.grey,
                ),
                title: const Text(
                  'Root Level (No Parent)',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              ...allPages
                  .where(
                    (p) =>
                        p.id != currentPage.id && p.relationType != 'sidepage',
                  )
                  .map(
                    (page) => ListTile(
                      dense: true,
                      leading: Text(
                        page.emoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                      title: Text(
                        page.title.isEmpty ? 'Untitled' : page.title,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: page.parentId != null
                          ? const Text(
                              'subpage',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            )
                          : null,
                      onTap: () => Navigator.pop(ctx, page.id),
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );

    if (selectedParent != null) {
      final newParentId = selectedParent.isEmpty ? null : selectedParent;
      await _serverService.movePage(currentPage.id, newParentId);
    }
  }

  void _showEmojiPicker() {
    if (_selectedPage == null) return;

    String currentCategory = 'smileys';
    String emojiSearchQuery = '';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202020),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          List<String> allEmojis = [];
          if (emojiSearchQuery.isNotEmpty) {
            final q = emojiSearchQuery.toLowerCase();
            for (final cat in _emojiCategories) {
              for (final e in List<Map<String, dynamic>>.from(cat['emojis'])) {
                final name = e['name'].toString().toLowerCase();
                final char = e['char'].toString();
                if (name.contains(q) || char == q) {
                  allEmojis.add(char);
                }
              }
            }
          } else {
            final activeCategoryData = _emojiCategories.firstWhere(
              (cat) => cat['id'] == currentCategory,
              orElse: () => _emojiCategories.first,
            );
            allEmojis = List<Map<String, dynamic>>.from(activeCategoryData['emojis'])
                .map((e) => e['char'] as String)
                .toList();
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.70,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Text(
                        'Select Emoji Icon',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (_recentEmojis.isNotEmpty)
                        Text(
                          '${_recentEmojis.length} recent',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    autofocus: false,
                    onChanged: (v) => setSheetState(() => emojiSearchQuery = v),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search emojis (e.g. apple, heart, smile)...',
                      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF3E3E3E)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF3E3E3E)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF818CF8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Recent emojis
                if (_recentEmojis.isNotEmpty && emojiSearchQuery.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text(
                          'Recent',
                          style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () async {
                            setSheetState(() => _recentEmojis.clear());
                            try {
                              final dir = await getApplicationDocumentsDirectory();
                              final file = File('${dir.path}/recent_emojis.json');
                              if (await file.exists()) {
                                await file.delete();
                              }
                            } catch (_) {}
                          },
                          child: const Text('Clear', style: TextStyle(fontSize: 10, color: Color(0xFF818CF8))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 36,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _recentEmojis.length,
                      itemBuilder: (_, i) {
                        final e = _recentEmojis[i];
                        if (e.isEmpty) return const SizedBox.shrink();
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedPage = _selectedPage!.copyWith(emoji: e);
                            });
                            _saveCurrentPageImmediate();
                            Navigator.pop(context);
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            child: Text(e, style: const TextStyle(fontSize: 22)),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 12, color: Color(0xFF2D2D2D)),
                ],
                // Categories Tab Bar
                if (emojiSearchQuery.isEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: _emojiCategories.map((cat) {
                        final isActive = cat['id'] == currentCategory;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextButton(
                            onPressed: () {
                              setSheetState(() {
                                currentCategory = cat['id'] as String;
                              });
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: isActive
                                  ? const Color(0xFF818CF8).withOpacity(0.15)
                                  : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: Text(
                              cat['label'].toString().split(' ').first,
                              style: TextStyle(
                                color: isActive ? const Color(0xFF818CF8) : Colors.grey,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                if (emojiSearchQuery.isEmpty)
                  const Divider(height: 1, color: Color(0xFF2D2D2D)),
                // Grid of Emojis
                Expanded(
                  child: allEmojis.isEmpty && emojiSearchQuery.isNotEmpty
                      ? const Center(
                          child: Text('No emojis match your search', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(20),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                          itemCount: allEmojis.length,
                          itemBuilder: (context, index) {
                            final emoji = allEmojis[index].trim();
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedPage = _selectedPage!.copyWith(emoji: emoji);
                                });
                                _saveRecentEmoji(emoji);
                                _saveCurrentPageImmediate();
                                Navigator.pop(context);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Center(
                                child: Text(emoji, style: const TextStyle(fontSize: 26)),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<DbPage> _getPagePath(DbPage? page) {
    if (page == null) return [];
    final List<DbPage> path = [page];
    String? parentId = page.parentId;
    int depth = 0;
    while (parentId != null && depth < 20) {
      final pid = parentId;
      final parents = _serverService.pages.where((p) => p.id == pid).toList();
      if (parents.isNotEmpty) {
        final parent = parents.first;
        path.insert(0, parent);
        parentId = parent.parentId;
      } else {
        break;
      }
      depth++;
    }
    return path;
  }

  Widget _buildAppBarTitle() {
    if (_selectedPage == null) {
      return Row(
        children: [
          const Text(
            'Cero',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
          ),
          const SizedBox(width: 8),
          _buildLinkIndicator(),
        ],
      );
    }

    final path = _getPagePath(_selectedPage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: path.asMap().entries.map((entry) {
              final index = entry.key;
              final page = entry.value;
              final isLast = index == path.length - 1;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        '/',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  Text(
                    '${page.emoji} ${page.title.isEmpty ? 'Untitled' : page.title}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isLast ? const Color(0xFF818CF8) : Colors.grey,
                      fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                _selectedPage!.title.isEmpty
                    ? 'Untitled'
                    : _selectedPage!.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildLinkIndicator(),
          ],
        ),
      ],
    );
  }

  Widget _buildLinkIndicator() {
    final isActive = _serverService.isRunning ||
        (_serverService.isClientMode && _serverService.isClientPaired);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isActive ? 'LINK ON' : 'LINK OFF',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.green : Colors.grey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allPages = _serverService.pages;
    final rootPages = allPages
        .where((p) => p.parentId == null && p.relationType != 'sidepage')
        .toList();

    return PopScope(
      canPop: _navigationHistory.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _navigationHistory.isNotEmpty) {
          _goBack();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: (_selectedPage != null && _navigationHistory.isNotEmpty)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: _goBack,
              )
            : null,
        title: _buildAppBarTitle(),
        backgroundColor: const Color(0xFF191919),
        elevation: 0,
        actions: [
          if (_selectedPage != null) ...[
            IconButton(
              icon: _isRefreshingPage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: 'Refresh Page',
              onPressed: _isRefreshingPage ? null : _refreshSelectedPage,
            ),
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.view_sidebar_outlined),
                tooltip: 'Context Pages',
                onPressed: () {
                  Scaffold.of(context).openEndDrawer();
                },
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  _archiveSelectedPage(_selectedPage!.id);
                } else if (value == 'subpage') {
                  _createSubpage(_selectedPage!.id);
                } else if (value == 'sidepage') {
                  _createSubpage(_selectedPage!.id, relationType: 'sidepage');
                } else if (value == 'move') {
                  _showMoveDialog();
                } else if (value == 'close') {
                  setState(() {
                    _selectedPage = null;
                    _navigationHistory.clear();
                  });
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'subpage',
                  child: Row(
                    children: [
                      Icon(Icons.add_box_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Create Subpage'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sidepage',
                  child: Row(
                    children: [
                      const Icon(Icons.open_in_new, size: 18),
                      const SizedBox(width: 8),
                      const Text('Create Side Page'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'move',
                  child: Row(
                    children: [
                      Icon(Icons.drive_file_move_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Move To...'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.archive, size: 18, color: Colors.orangeAccent),
                      SizedBox(width: 8),
                      Text(
                        'Archive Page',
                        style: TextStyle(color: Colors.orangeAccent),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'close',
                  child: Row(
                    children: [
                      Icon(Icons.close, size: 18),
                      SizedBox(width: 8),
                      Text('Close Note'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      drawer: _buildDrawer(rootPages, allPages),
      endDrawer: _selectedPage != null ? _buildSubpagesEndDrawer() : null,
      body: _selectedPage == null
          ? _buildDashboard(rootPages)
          : _buildPageEditor(),
      ),
    );
  }

  Widget _buildDrawer(List<DbPage> rootPages, List<DbPage> allPages) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDrawerHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _showArchived
                    ? (_archivedPages
                          .map((page) => _buildArchivedPageTile(page))
                          .toList())
                    : rootPages
                          .map((page) => _buildPageTreeNode(page, allPages, 0))
                          .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ElevatedButton.icon(
                onPressed: () => _createSubpage(null),
                icon: const Icon(Icons.add),
                label: const Text('Add Root Page'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF818CF8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        if (!_showArchived) {
                          final archived = await _serverService.getArchivedPages();
                          setState(() {
                            _archivedPages = archived;
                            _showArchived = true;
                          });
                        } else {
                          setState(() {
                            _showArchived = false;
                          });
                        }
                      },
                      icon: Icon(
                        _showArchived ? Icons.list_alt : Icons.archive_outlined,
                        size: 16,
                      ),
                      label: Text(_showArchived ? 'Active' : 'Trash'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Color(0xFF2C2C2C)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context); // Close drawer
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SettingsScreen(serverService: _serverService),
                          ),
                        ).then((_) {
                          setState(() {});
                        });
                      },
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: const Text('Settings'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Color(0xFF2C2C2C)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildSubpagesEndDrawer() {
    if (_selectedPage == null) return const SizedBox();

    return Drawer(
      width: 240,
      backgroundColor: const Color(0xFF161616),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2C2C2C))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Context',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _sidePages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'No context pages yet.\n\nSide pages provide supplementary info about the current page.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF4A4A4A),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      itemCount: _sidePages.length,
                      itemBuilder: (context, idx) {
                        final sp = _sidePages[idx];
                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: const BorderSide(color: Color(0xFF2E2E2E)),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Text(
                              sp.emoji,
                              style: const TextStyle(fontSize: 16),
                            ),
                            title: Text(
                              sp.title.isEmpty ? 'Untitled' : sp.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: Color(0xFF64748B),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _selectPage(sp);
                            },
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _createSubpage(_selectedPage!.id, relationType: 'sidepage');
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Add Context Page',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF818CF8),
                  side: const BorderSide(color: Color(0xFF3E3E3E)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2C2C2C))),
      ),
      child: Column(
        children: [
          // Mode tabs
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_isClientModeTab) {
                      setState(() => _isClientModeTab = false);
                      _serverService.exitClientMode();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _isClientModeTab
                              ? Colors.transparent
                              : const Color(0xFF818CF8),
                          width: 2,
                        ),
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Host',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (!_isClientModeTab) {
                      setState(() => _isClientModeTab = true);
                      _serverService.enterClientMode();
                      _serverService.startDiscovery();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _isClientModeTab
                              ? const Color(0xFF818CF8)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Remote',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Tab content
          if (_isClientModeTab)
            _buildRemoteModePanel()
          else
            _buildHostModePanel(),
        ],
      ),
    );
  }

  Widget _buildHostModePanel() {
    final isRunning = _serverService.isRunning;
    final clientsCount = _serverService.clients.length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cero Sync Hub',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Local Database Truth',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              Switch.adaptive(
                value: isRunning,
                activeColor: const Color(0xFF818CF8),
                onChanged: (val) async {
                  if (val) {
                    await _serverService.startServer();
                  } else {
                    await _serverService.stopServer();
                  }
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF191919),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Server IP:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      _serverService.localIp,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Port:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '${_serverService.wsPort}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Auth PIN:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      _serverService.authPin.isEmpty
                          ? '—'
                          : _serverService.authPin,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF818CF8),
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Connections:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '$clientsCount active',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_serverService.pendingConnections.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Pending Pairings:',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            ...List.generate(_serverService.pendingConnections.length, (i) {
              final p = _serverService.pendingConnections[i];
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.remoteAddress,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _serverService.approvePendingClient(i),
                      child: const Text('Allow', style: TextStyle(fontSize: 11, color: Colors.green)),
                    ),
                    TextButton(
                      onPressed: () => _serverService.rejectPendingClient(i),
                      child: const Text('Deny', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildRemoteModePanel() {
    final isConnected = _serverService.isClientConnected;
    final isPaired = _serverService.isClientPaired;
    final discoveredServers = _serverService.discoveredServers;
    final clientError = _serverService.clientError;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remote Connection',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Connect to a Cero host',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          // Discovered servers
          if (!isConnected && discoveredServers.isNotEmpty) ...[
            const Text(
              'Discovered Hosts:',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: ListView(
                children: discoveredServers.map((server) {
                  return Card(
                    color: const Color(0xFF191919),
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        server.deviceName,
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        server.ip,
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
                      ),
                      trailing: const Icon(Icons.link, size: 14, color: Color(0xFF818CF8)),
                      onTap: () {
                        _clientIpController.text = server.ip;
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 16, color: Color(0xFF2C2C2C)),
          ],
          // Connection form
          if (!isConnected) ...[
            if (discoveredServers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'No hosts found. Make sure the host server is running.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            TextField(
              controller: _clientIpController,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Host IP address',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: Color(0xFF191919),
                border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _clientPinController,
                    style: const TextStyle(fontSize: 12, color: Colors.white, letterSpacing: 2),
                    decoration: const InputDecoration(
                      hintText: 'PIN',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: Color(0xFF191919),
                      border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: () async {
                      final ip = _clientIpController.text.trim();
                      final pin = _clientPinController.text.trim();
                      if (ip.isEmpty || pin.isEmpty) return;
                      await _serverService.connectToHost(ip, _serverService.wsPort, pin);
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Connect', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
          // Connection status
          if (isConnected) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        isPaired ? Icons.check_circle : Icons.hourglass_empty,
                        size: 14,
                        color: isPaired ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPaired ? 'Connected & Paired' : 'Waiting for host approval...',
                        style: TextStyle(
                          fontSize: 11,
                          color: isPaired ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        await _serverService.disconnectFromHost();
                        setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Disconnect', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (clientError.isNotEmpty && !isConnected) ...[
            const SizedBox(height: 8),
            Text(
              clientError,
              style: const TextStyle(fontSize: 10, color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageTreeNode(DbPage page, List<DbPage> allPages, int depth) {
    final children = allPages
        .where((p) => p.parentId == page.id && p.relationType != 'sidepage')
        .toList();
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedPageIds.contains(page.id);
    final isSelected = _selectedPage?.id == page.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 12.0),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF818CF8).withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.only(left: 8, right: 12),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedPageIds.remove(page.id);
                        } else {
                          _expandedPageIds.add(page.id);
                        }
                      });
                    },
                    child: Icon(
                      hasChildren
                          ? (isExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right)
                          : Icons.description_outlined,
                      size: 16,
                      color: isSelected
                          ? const Color(0xFF818CF8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(page.emoji, style: const TextStyle(fontSize: 14)),
                ],
              ),
              title: Text(
                page.title.isEmpty ? 'Untitled' : page.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF818CF8)
                      : const Color(0xFFCBD5E1),
                ),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.add, size: 14, color: Color(0xFF64748B)),
                tooltip: 'Add subpage',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _createSubpage(page.id),
              ),
              onTap: () {
                Navigator.pop(context);
                _selectPage(page);
              },
            ),
          ),
        ),
        if (hasChildren && isExpanded)
          ...children.map(
            (child) => _buildPageTreeNode(child, allPages, depth + 1),
          ),
      ],
    );
  }

  Widget _buildArchivedPageTile(DbPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Card(
        color: const Color(0xFF191919),
        margin: EdgeInsets.zero,
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Text(page.emoji, style: const TextStyle(fontSize: 16)),
          title: Text(
            page.title.isEmpty ? 'Untitled' : page.title,
            style: const TextStyle(
              fontSize: 13,
              decoration: TextDecoration.lineThrough,
              color: Colors.grey,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.restore_outlined,
                  size: 18,
                  color: Colors.green,
                ),
                tooltip: 'Restore',
                onPressed: () async {
                  await _serverService.restorePage(page.id);
                  final archived = await _serverService.getArchivedPages();
                  setState(() {
                    _archivedPages = archived;
                  });
                },
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_forever_outlined,
                  size: 18,
                  color: Colors.redAccent,
                ),
                tooltip: 'Delete permanently',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF202020),
                      title: const Text('Permanently Delete?'),
                      content: const Text('This action cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
                          child: const Text('Delete Forever'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _serverService.hardDeletePage(page.id);
                    final archived = await _serverService.getArchivedPages();
                    setState(() {
                      _archivedPages = archived;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(List<DbPage> rootPages) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Text('📓', style: TextStyle(fontSize: 72))),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Cero Personal Journal',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                'Offline-first markdown notes, synced directly to your devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            const SizedBox(height: 32),
            if (rootPages.isEmpty) ...[
              const Center(
                child: Text(
                  'No journal entries created yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _createSubpage(null),
                icon: const Icon(Icons.add),
                label: const Text('Create First Page'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF818CF8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ] else ...[
              const Text(
                'Recent Notes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rootPages.take(4).length,
                itemBuilder: (context, idx) {
                  final page = rootPages[idx];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: Text(
                        page.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: Text(
                        page.title.isEmpty ? 'Untitled' : page.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        page.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      onTap: () => _selectPage(page),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPageEditor() {
    if (_selectedPage == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Focus(autofocus: true, child: SizedBox.shrink()),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: _showEmojiPicker,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _selectedPage!.emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Untitled',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  onChanged: (val) => _saveCurrentPage(),
                ),
              ),
            ],
          ),
        ),
          Expanded(
            child: CardColumn(
              cards: _pageCards,
              allPages: _serverService.pages,
              selectedPage: _selectedPage!,
              scrollController: _cardScrollController,
              onNavigateToPage: _selectPage,
              onCardUpdated: (cardId, content) async {
                await _serverService.updateCard(id: cardId, content: content);
                _loadCardsForPage(_selectedPage!.id);
              },
              onCardAdded: (pageId, type, content) async {
                await _serverService.addCard(
                  pageId: pageId,
                  type: type,
                  content: content,
                );
                _loadCardsForPage(pageId);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_cardScrollController.hasClients) {
                    _cardScrollController.animateTo(
                      _cardScrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
              },
              onCardDeleted: (cardId) async {
                await _serverService.deleteCard(cardId);
                _loadCardsForPage(_selectedPage!.id);
              },
              onCardsReordered: (cardIds) async {
                await _serverService.reorderCards(cardIds: cardIds);
                _loadCardsForPage(_selectedPage!.id);
              },
              onCreateNewPage: (parentId) async {
                return await _createSubpage(parentId);
              },
            ),
          ),
      ],
    );
  }
}