/// Android / desktop: preferences are kept in memory while the app runs.
library;

bool _collapsed = false;

bool readSidebarCollapsed() => _collapsed;

void writeSidebarCollapsed(bool value) => _collapsed = value;

/// Always true here: the notice is about browser storage, and there is
/// nowhere to remember a dismissal, so returning false would nag every launch.
bool readStorageNoticeSeen() => true;

void writeStorageNoticeSeen() {}

/// Does nothing: there is no page to reload outside the browser.
void reloadPage() {}
