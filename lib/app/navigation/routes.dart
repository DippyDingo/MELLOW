/// Every route path of the app, in one place.
///
/// Screens navigate with `context.push(AppRoutes.thread(id))` and never build
/// path strings inline; this keeps deep links and integration tests honest.
abstract final class AppRoutes {
  static const String conversations = '/conversations';
  static const String contacts = '/contacts';
  static const String favorites = '/favorites';
  static const String settings = '/settings';

  static const String threadPattern = '/conversations/:id';
  static const String contactPattern = '/contacts/:id';

  static const String compose = '/compose';
  static const String addAccount = '/settings/accounts/add';
  static const String appearance = '/settings/appearance';
  static const String accounts = '/settings/accounts';
  static const String privacy = '/settings/privacy';
  static const String sync = '/settings/sync';
  static const String gmailConnect = '/settings/accounts/add/gmail';
  static const String about = '/settings/about';
  static const String storage = '/settings/storage';

  static String thread(String id) => '/conversations/$id';

  static String contact(String id) => '/contacts/$id';
}
