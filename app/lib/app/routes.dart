/// All route paths in one place. Build locations with the helpers, never by
/// hand-concatenating strings in widgets.
abstract final class Routes {
  static const splash = '/splash';
  static const connect = '/connect';
  static const briefing = '/briefing';
  static const inbox = '/inbox';
  static const projects = '/projects';
  static const control = '/control';

  static const tabs = [briefing, inbox, projects, control];
}
